#!/usr/bin/env lua
--
-- lurch: an extendable irc client in lua
-- (c) Kiëd Llaentenn

local util = require('util')
local irc = require('irc')
local readline = require('readline')
local tty = require('tty')
local socket = require('socket')
local lfs = require('lfs')
local posix = require('posix')

local tcp = assert(socket.tcp())
local printf = util.printf
local eprintf = util.eprintf
local format = util.format

math.randomseed(os.time())

LEFT_PADDING = 10
RIGHT_PADDING = 80


HOST = "irc.freenode.net"
NICK = "inebriate|lurch"
PASS = nil
USER = nil
PORT = 6667
NAME = nil
JOIN = "#bots"

-- dimensions of the terminal
tty_width = 80
tty_height = 24

colors = {}    -- List of colors used for nick highlighting
nick = NICK    -- The current nickname
chan = 1       -- The current channel
channels = {}  -- List of all opened channels
nicks = {}     -- Table of all nicknames
history = {}   -- History of each buffer

local function clean()
	tty.line_wrap()
	tty.clear()
	tty.reset_scroll_area()
	tty.main_buffer()
end

local function panic(fmt, ...)
	clean()
	eprintf(fmt, ...)
	os.exit(1)
end

local function load_nick_highlight_colors()
	-- read a list of newline-separated colors from ./colors.
	-- the colors are in RRGGBB and may or may not be prefixed
	-- with a #
	local data = util.read("colors")

	-- iterate through each line, and parse each color into
	-- the R, G, and B values. this allows us to easily construct
	-- the appropriate escape codes to change text to that color
	-- later on.
	for line in data:gmatch("([^\n]+)\n?") do
		-- strip off any prefixed #
		line = line:gsub("^#", "")

		local r, g, b = line:gmatch("(..)(..)(..)")()

		colors[#colors + 1] = {}
		colors[#colors].r = tonumber(r, 16)
		colors[#colors].g = tonumber(g, 16)
		colors[#colors].b = tonumber(b, 16)
	end
end

local function send(fmt, ...)
	tcp:send(format(fmt, ...) .. "\n")
end

local function ncolor(nick)
	if not nicks[nick] then
		nicks[nick] = {}
	end

	-- store nickname highlight color, so that we don't have to
	-- calculate the nickname's hash each time
	if not nicks[nick].highlight then
		-- add one to the hash value, as the hash value may be 0
		nicks[nick].highlight = util.hash(nick, #colors - 1)
		nicks[nick].highlight = nicks[nick].highlight + 1
	end

	local color = colors[nicks[nick].highlight]
	local esc = "\x1b[1m"

	-- if no color could be found, just use the default of black
	if color then
		esc = format("\x1b[1;38;2;%s;%s;%sm", color.r, color.g, color.b)
	end

	return format("%s%s\x1b[m", esc, nick)
end

local function refresh()
	tty_height = tty.height()
	tty_width = tty.width()

	tty.alt_buffer()
	tty.no_line_wrap()
	tty.clear()
	tty.set_scroll_area(tty_height - 1)
	tty.curs_move_to_line(999)
	tty.curs_show()
end

local function status()
	local chanlist = " "
	for _, ch in ipairs(channels) do
		if ch == channels[chan] then
			chanlist = chanlist .. "\x1b[7m " .. ch .. " \x1b[0m "
		else
			chanlist = chanlist .. ch .. " "
		end
	end

	tty.curs_save()
	tty.curs_move_to_line(0)
	tty.clear_line()
	printf("%s", chanlist)
	tty.curs_restore()
end

local function redraw()
	--refresh()

	tty.curs_save()
	tty.curs_hide()

	tty.clear()

	tty.curs_down(999)
	tty.curs_up(1)

	if history[channels[chan]] then
		for _, msg in ipairs(history[channels[chan]]) do
			printf("\r%s\n\r", msg)
		end
	end

	status()

	tty.curs_restore()
	tty.curs_show()
end

local function connect()
	tcp:connect(HOST, PORT)

	local nick = NICK or os.getenv("IRCNICK") or os.getenv("USER")
	local user = USER or os.getenv("IRCUSER") or os.getenv("USER")
	local name = NAME or "hii im drukn"

	send("NICK %s", nick)
	send("USER %s %s %s :%s", user, user, user, name)
	if PASS then send("PASS %s", PASS) end
end

local function prin(dest, left, right_fmt, ...)
	local right = format(right_fmt, ...)

	assert(dest); assert(left); assert(right)

	-- Strip escape sequences from the first word in the message
	-- so that we can calculate how much padding to add for
	-- alignment.
	local raw = left:gsub("\x1b%[.-m", "")

	-- Generate a cursor right sequence based on the length of
	-- the above "raw" word. The nick column is a fixed width
	-- of LEFT_PADDING so it's simply 'LEFT_PADDING - word_len'
	local pad
	if #raw > 10 then
		pad = 0
	else
		pad = 11 - #raw
	end
	local out = format("\x1b[%sC%s %s", pad, left, right)

	-- TODO: rename "channels" to "buffers"; that's a more accurate
	-- description
	if not util.array_contains(channels, dest) then
		channels[#channels + 1] = dest
	end

	if dest == channels[chan] then
		tty.curs_hide()
		tty.curs_save()
		tty.curs_down(999)
		tty.curs_up(1)

		printf("\r\x1b[2K%s\n\r", out)

		tty.curs_restore()
		tty.curs_show()
	end

	if not history[dest] then
		history[dest] = {}
	end

	history[dest][#history[dest] + 1] = out
end

local none = function(whom, mesg, dest) end -- dummy action
local irchand = {
	["PING"] = function(whom, mesg, dest) send("PONG %s", dest) end,
	["NOTICE"] = function(whom, mesg, dest) prin(dest, "NOTE", "%s", mesg) end,
	["AWAY"] = function(whom, mesg, dest) prin(nick, "--", "Away status: %s", mesg) end,
	["ACTION"] = function(whom, mesg, dest)
		prin(dest, "*", "%s %s", ncolor(whom), mesg)
	end,

	["PART"] = function(whom, mesg, dest)
		prin(dest, "<--", "%s has left %s", ncolor(whom), dest)
	end,

	["PRIVMSG"] = function(whom, mesg, dest)
		-- remove extra characters from nick that won't fit.
		if whom:len() > 10 then
			whom = whom:sub(1, 9) .. "\x1b[m\x1b[37m+\x1b[m"
		end

		prin(dest, ncolor(whom), "%s", mesg)
	end,

	["QUIT"] = function(whom, mesg, dest)
		if not nicks[whom] or not nicks[whom].joined then
			return
		end

		-- display quit message for all channels that user has
		-- joined.
		for _, ch in ipairs(nicks[whom].joined) do
			prin(ch, "<--", "%s has quit %s", ncolor(whom), dest)
		end
	end,

	["JOIN"] = function(whom, mesg, dest)
		if not util.array_contains(channels, dest) then
			channels[#channels + 1] = dest
		end

		-- if we are the ones joining, then switch to that buffer.
		if whom == nick then
			chan = #channels
		end

		prin(mesg, "-->", "%s has joined %s", ncolor(whom), dest)
	end,

	["NICK"] = function(whom, mesg, dest)
		if whom == nick then nick = mesg end
		prin(dest, "--@", "%s is now %s", ncolor(whom), ncolor(mesg))
	end,

	-- End of MOTD
	["376"] = function(whom, mesg, dest)
		send(":%s JOIN %s", nick, JOIN)
	end,

	-- Reply to /names
	["353"] = function(whom, mesg, dest)
		local nicklist = ""

		for nick in mesg:gmatch("([^%s]+)%s?") do
			nicklist = format("%s%s ", nicklist, ncolor(nick))

			if not nicks[nick] then
				nicks[nick] = {}
			end

			if not nicks[nick].joined then
				nicks[nick].joined = {}
			end

			if not util.array_contains(nicks[nick].joined, dest) then
				local sz = #nicks[nick].joined
				nicks[nick].joined[sz + 1] = dest
			end
		end

		prin(dest, "NAMES", "%s", nicklist)
	end,

	-- End of /names
	["366"] = none,

	-- URL for channel
	["328"] = function(whom, mesg, dest) prin(dest, "URL", "%s", mesg) end,

	-- ???
	["333"] = none,

	-- "xyz" is now your hidden host (set by foo)
	["396"] = function(whom, mesg, dest) prin("*", "--", "%s %s", dest, mesg) end,

	[0] = function(cmd, whom, mesg, dest)
		text = mesg
		if not mesg or mesg == "" then
			text = dest
		end

		prin(dest, cmd .. " --", "%s", text)
	end
}

local function parseirc(reply)
	local fields, whom, dest, msg = irc.parse(reply)
	if not whom or whom == "" then whom = nick end

	-- The first element in the fields array points to
	-- the type of message we're dealing with.
	local cmd = fields[1]

	-- fold message to width
	local mesg = util.fold(msg, RIGHT_PADDING)
	mesg = mesg:gsub("\n", "\n            ")

	-- When recieving MOTD messages and similar stuff from
	-- the IRCd, send it to the main tab
	if cmd:find("00.") or cmd:find("2[56].") or cmd:find("37.") then
		dest = "*"
	end

	if irchand[cmd] then
		(irchand[cmd])(whom, mesg, dest)
	else
		(irchand[0])(cmd, whom, mesg, dest)
	end
end

local function send_both(fmt, ...)
	-- this is a simple function to send the input to the
	-- terminal and to the server at the same time.
	send(fmt, ...)
	parseirc(format(fmt, ...))
end

local cmdhand = {
	["/next"] = function(a, args, inp)
		if chan < #channels then
			chan = chan + 1
		end
		redraw()
	end,
	["/prev"] = function(a, args, inp)
		if chan > 1 then
			chan = chan - 1
		end
		redraw()
	end,
	["/join"] = function(a, args, inp)
		send(":%s JOIN %s", nick, a)
		status()

		if not util.array_contains(channels, dest) then
			channels[#channels + 1] = dest
		end

		-- if we are the ones joining, then switch to that buffer.
		if whom == nick then
			chan = #channels
		end
	end,
	["/nick"] = function(a, args, inp)
		send("NICK %s", a)
		nick = a
	end,
	["/msg"] = function(a, args, inp)
		send_both(":%s PRIVMSG %s :%s", nick, a, args)
	end,
	["/raw"] = function(a, args, inp)
		send("%s %s", a, args)
	end,
	["/quit"] = function(a, args, inp)
		send("QUIT :%s %s", a, args)
		eprintf("[lurch exited]\n")
		clean()
		os.exit(0)
	end,
	[0] = function(a, args, inp)
		send_both("PRIVMSG %s :%s", channels[chan], inp)
	end
}

local function parsecmd(inp)
	local _cmd, a, args = inp:gmatch("([^%s]+)%s?([^%s]*)%s?(.*)")()

	if _cmd then
		local ac = (cmdhand[_cmd] or cmdhand[0]); ac(a, args, inp)
	end

	-- clear the input line once we're done.
	printf("\r\x1b[2K\r")
end

local function main()
	refresh()
	connect()

	load_nick_highlight_colors()

	-- set readline's history file, so that we may manage
	-- it ourselves
	readline.set_options({ histfile='hist' })

	-- other misc options
	readline.set_readline_name('lurch')

	-- set completion list to nicknames
	-- TODO
	--readline.set_complete_list(names)

	-- create the server buffer.
	channels[#channels + 1] = "*"

	local linehandler = function(line)
		-- save the sent input to readline's history
		readline.add_history(line)
		parsecmd(line)
	end
	readline.handler_install("", linehandler)

	local fds = {
		[0] = { events = { IN = { true } } },
		[tcp:getfd()] = { events = { IN = { true } } }
	}

	while "pigs fly" do
		-- use poll(2) to monitor stdin and the tcp socket
		-- and check which one has data to read.
		--
		-- continue if there is neither user input or data from the
		-- irc server.
		if posix.poll(fds, 0) == 0 then
			goto continue
		end

		-- did the server send data?
		if fds[tcp:getfd()].revents.IN then
			local reply, tcp_status, _ = tcp:receive("*l")
			if tcp_status == "closed" then break end
			parseirc(reply)
		end

		-- is there user input?
		if fds[0].revents.IN then
			readline.read_char()
		end

		-- if the user has entered input or the server has sent
		-- data, redraw the status bar
		if fds[0].revents.IN or fds[tcp:getfd()].revents.IN then
			status()
		end

		::continue::
	end

	clean()
	os.exit(0)
end

local function luaerr(err)
	clean()
	printf("lua error:\n%s\n", debug.traceback(err, 6))
	os.exit(1)
end

xpcall(main, luaerr)
