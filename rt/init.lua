-- lurch: an extendable irc client in lua
-- (c) Kiëd Llaentenn

local rt = {}

local irc = require('irc')
local tui = require('tui')
local mirc = require('mirc')
local tty = require('tty')
local util = require('util')

local printf = util.printf
local eprintf = util.eprintf
local format = string.format

math.randomseed(os.time())

LEFT_PADDING = 10
RIGHT_PADDING = 80


HOST = "localhost"--"irc.freenode.net"
NICK = "inebriate|lurch"
PASS = nil
USER = nil
PORT = 6667
NAME = nil
JOIN = "#bots"

QUIT_MSG = "*thud*"
PART_MSG = "*confused yelling*"

CTCP_PING    = true
CTCP_VERSION = "lurch (beta)"
CTCP_SOURCE  = "(null)"

MIRC_COLORS_ENABLED = true

MAINBUF = "<server>"

colors = {}     -- List of colors used for nick highlighting
set_colors = {} -- list of cached colors used for each nick/text

nick = NICK     -- The current nickname
nicks = {}      -- Table of all nicknames

cur_buf = nil   -- The current buffer
buffers = {}    -- List of all opened buffers

-- add a new buffer. status() should be run after this
-- to add the new buffer to the statusline.
local function buf_add(name)
	local newbuf = {}
	newbuf.history = {}
	newbuf.name    = name
	newbuf.unread  = 0

	buffers[#buffers + 1] = newbuf
end

-- check if a buffer exists, and if so, return the index
-- for that buffer.
local function buf_idx(name)
	local idx = nil
	for i = 1, #buffers do
		if buffers[i].name == name then
			idx = i
			break
		end
	end
	return idx
end

local function panic(fmt, ...)
	tui.clean()
	eprintf(fmt, ...)
	os.exit(1)
end

local function load_nick_highlight_colors()
	-- read a list of newline-separated colors from ./colors.
	-- the colors are in RRGGBB and may or may not be prefixed
	-- with a #
	local data = util.read(__LURCH_EXEDIR .. "/conf/colors")

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

local function ncolor(text, text_as, no_bold)
	local access = ""

	assert(text)
	if not text_as then text_as = text end

	if text_as:find("^[~@%&+!]") then
		access = nick:gmatch("(.)")()
		text_as = nick:gsub("^.", "")
	end

	if not nicks[text_as] then
		nicks[text_as] = {}
	end

	-- store nickname highlight color, so that we don't have to
	-- calculate the nickname's hash each time
	if not set_colors[text_as] then
		-- add one to the hash value, as the hash value may be 0
		set_colors[text_as] = util.hash(text_as, #colors - 1)
		set_colors[text_as] = set_colors[text_as] + 1
	end

	local color = colors[set_colors[text_as]]
	local esc = "\x1b[1m"
	if no_bold then esc = "" end

	-- if no color could be found, just use the default of black
	if color then
		esc = esc .. format("\x1b[38;2;%s;%s;%sm", color.r, color.g, color.b)
	end

	return format("%s%s%s\x1b[m", access, esc, text)
end

local function status()
	local chanlist = " "
	for buf = 1, #buffers do
		local ch = buffers[buf].name

		if buf == cur_buf then
			local pnch = ncolor(format(" %d %s ", buf, ch), ch, true)
			chanlist = chanlist .. "\x1b[7m" .. pnch .. "\x1b[0m "
		else
			if buffers[buf].unread > 0 then
				local nch = ncolor(format(" %d %s %s%d ", buf, ch,
					"+", buffers[buf].unread), ch, true)
				chanlist = chanlist .. nch .. " "
			end
		end
	end

	tty.curs_save()
	tty.curs_move_to_line(0)

	tty.clear_line()
	printf("%s", chanlist)

	tty.curs_restore()
end

local function redraw()
	tui.refresh()

	tty.curs_save()
	tty.curs_hide()
	tty.clear()

	tty.curs_down(999)
	tty.curs_up(1)

	if buffers[cur_buf].history then
		for _, msg in ipairs(buffers[cur_buf].history) do
			printf("\r%s\n\r", msg)
		end
	end

	status()

	tty.curs_show()
	tty.curs_restore()
end

local function switch_buf(ch)
	if buffers[ch] then
		cur_buf = ch
		buffers[cur_buf].unread = 0
		redraw()
	end
end

local function prin(dest, left, right_fmt, ...)
	local right = format(right_fmt, ...)

	assert(dest)
	assert(left)
	assert(right)

	-- fold message to width
	right = util.fold(right, RIGHT_PADDING)
	right = right:gsub("\n", "\n            ")

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

	local out = format("\x1b[%sC%s %s", pad, left, right):gsub("\n+$", "")

	local bufidx = buf_idx(dest)
	if not bufidx then
		buf_add(dest)
		bufidx = buf_idx(dest)
		status()
	end

	if dest == buffers[cur_buf].name then
		tty.curs_hide()
		tty.curs_save()

		tty.curs_down(999)

		tty.clear_line()
		printf("%s\n", out)
		tty.clear_line()

		tty.curs_restore()
		tty.curs_show()
	else
		buffers[bufidx].unread = buffers[bufidx].unread + 1
		status()
	end

	-- save to buffer history.
	local histsz = #buffers[bufidx].history
	buffers[bufidx].history[histsz + 1] = out
end

local function none(_) end
local function default2(e) prin(MAINBUF, "--", "There are %s %s", e.fields[3], e.msg) end
local function default(e) prin(e.dest, "--", "%s", e.msg) end

local irchand = {
	["PING"] = function(e)   irc.send("PONG :%s", e.dest or "(null)") end,
	["AWAY"] = function(e)   prin(MAINBUF, "--", "Away status: %s", e.msg) end,
	["MODE"] = function(e)
		if (e.dest):find("#") then
			local mode = e.fields[3]
			for i = 4, #e.fields do
				if not e.fields[i] then break end
				mode = mode .. " " .. e.fields[i]
			end
			mode = mode .. " " .. e.msg
			prin(e.dest, "MODE", "[%s] by %s", mode, ncolor(e.nick))
		else
			prin(MAINBUF, "MODE", "%s", e.msg)
		end
	end,
	["NOTICE"] = function(e)
		if e.host then
			prin(e.nick, "NOTE", "%s: %s", e.nick, e.msg)
		else
			prin(MAINBUF, "NOTE", "%s", e.msg)
		end
	end,
	["PART"] = function(e)
		prin(e.dest, "<--", "%s has left %s (%s)", ncolor(e.nick), e.dest, e.msg)
	end,
	["KICK"] = function(e)
		prin(e.dest, "<--", "%s has kicked %s (%s)", ncolor(e.nick), ncolor(e.fields[3]), e.msg)
	end,
	["INVITE"] = function(e)
		-- TODO: auto-join on invite?
		prin(MAINBUF, "--", "%s sent an invite to %s", e.nick, e.msg)
	end,
	["PRIVMSG"] = function(e)
		local sender = e.nick
		-- remove extra characters from nick that won't fit.
		if #sender > 10 then
			sender = (sender):sub(1, 9) .. "\x1b[m\x1b[37m+\x1b[m"
		end

		-- convert or remove mIRC IRC colors.
		if MIRC_COLORS_ENABLED then
			e.msg = mirc.to_tty_seq(e.msg)
		else
			e.msg = mirc.remove(e.msg)
		end

		prin(e.dest, ncolor(sender, e.nick), "%s", e.msg)
	end,
	["QUIT"] = function(e)
		if not nicks[e.nick] or not nicks[e.nick].joined then
			return
		end

		-- display quit message for all buffers that user has
		-- joined.
		for _, ch in ipairs(nicks[e.nick].joined) do
			prin(ch, "<--", "%s has quit %s (%s)", ncolor(e.nick), e.dest, e.msg)
		end
	end,
	["JOIN"] = function(e)
		if not buf_idx(e.dest) then
			buf_add(e.dest)
		end

		-- if we are the ones joining, then switch to that buffer.
		if e.nick == nick then
			switch_buf(#buffers)
		end

		-- sometimes the channel joined is contained in the message.
		if not e.dest or e.dest == "" then
			e.dest = e.msg
		end

		prin(e.dest, "-->", "%s has joined %s", ncolor(e.nick), e.dest)
	end,
	["NICK"] = function(e)
		-- copy across nick information.
		-- this preserves highlighting across nickname changes.
		if e.nick == nick then
			nick = e.msg
		else
			nicks[e.msg] = nicks[e.nick]
			nicks[e.nick] = nil
		end

		-- display nick message for all buffers that user has joined.
		local bufs = nil
		if e.nick == nick or not nicks[e.nick] then
			bufs = {}
			for i = 1, #buffers do
				bufs[#bufs + 1] = buffers[i].name
			end
		else
			bufs = nicks[e.nick].joined
		end

		for _, ch in ipairs(bufs) do
			prin(ch, "--@", "%s is now known as %s", ncolor(e.nick),
				ncolor(e.msg))
		end
	end,

	-- Welcome to the xyz Internet Relay Chat Network, foo!
	["001"] = default,

	-- Your host is irc.foo.net, running ircd-version
	["002"] = default,

	-- This server was created on January 1, 2020.
	["003"] = default,

	-- RPL_MYINFO
	-- <servername> <version> <available user modes> <available chan modes>
	-- I am not aware of any situation in which the user would need to see
	-- this useless information.
	["004"] = none,

	-- I'm not really sure what 005 is. RFC2812 states that this is RPL_BOUNCE,
	-- telling the user to try another server as the one they connected to has
	-- reached the maximum number of connected clients.
	--
	-- However, freenode sends something that seems to be something entirely
	-- different. Here's an example:
	--
	-- :card.freenode.net 005 nick CNOTICE KNOCK :are supported by this server
	--
	-- Anyway, I don't think anyone is interested in seeing this info.
	["005"] = none,

	-- There are x users online
	["251"] = default,

	-- There are x operators online
	["252"] = default2,

	-- There are x unknown connections
	["253"] = default2,

	-- There are x channels formed
	["254"] = default2,

	-- Some junk sent by freenode.
	["255"] = none, ["265"] = none,
	["266"] = none, ["250"] = none,

	-- WHOIS: RPL_WHOISUSER (response to /whois)
	-- <nick> <user> <host> * :realname
	["311"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] (%s!%s@%s): %s", ncolor(e.fields[3]),
			e.fields[3], e.fields[4], e.fields[5], e.msg)
	end,

	-- WHOIS: RPL_WHOISSERVER (response to /whois)
	-- <nick> <server> :serverinfo
	["312"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] %s (%s)", ncolor(e.fields[3]), e.fields[4], e.msg)
	end,

	-- End of WHOIS
	["318"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] End of WHOIS info.", ncolor(e.fields[3]))
	end,

	-- URL for channel
	["328"] = function(e) prin(e.dest, "URL", "%s", e.msg) end,

	-- WHOIS: <nick> is logged in as <user> (response to /whois)
	["330"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] is logged in as %s", ncolor(e.fields[3]),
			ncolor(e.fields[4]))
	end,

	-- No topic set
	["331"] = function(e) prin(e.dest, "-!-", "No topic set for %s", e.dest) end,

	-- TOPIC for channel
	["332"] = function(e) prin(e.dest, "TOPIC", "%s", e.msg) end,

	-- TOPIC last set by nick!user@host
	["333"] = function(e)
		-- sometimes, the nick is in the fields
		local n = (e.fields[4]):gmatch("(.-)!")()
		if n then
			prin(e.dest, "--", "Topic last set by %s (%s)", ncolor(n), e.fields[4])
		else
			local datetime = os.date("%Y-%m-%d %H:%M:%S", e.msg)
			prin(e.dest, "--", "Topic last set by %s on %s", ncolor(e.fields[4]), datetime)
		end
	end,

	-- invited <nick> to <chan> (response to /invite)
	["341"] = function(e)
		prin(e.fields[4], "--", "invited %s to %s", ncolor(e.fields[3]), e.fields[4])
	end,

	-- Reply to /names
	["353"] = function(e)
		local nicklist = ""

		for _nick in (e.msg):gmatch("([^%s]+)%s?") do
			nicklist = nicklist .. format("%s ", ncolor(_nick))

			if not nicks[_nick] then
				nicks[_nick] = {}
			end

			if not nicks[_nick].joined then
				nicks[_nick].joined = {}
			end

			if not util.contains(nicks[_nick].joined, e.dest) then
				local sz = #nicks[_nick].joined
				nicks[_nick].joined[sz + 1] = e.dest
			end
		end

		prin(e.dest, "NAMES", "%s", nicklist)
	end,

	-- End of /names
	["366"] = none,

	-- MOTD message
	["372"] = default,
	
	-- Beginning of MOTD
	["375"] = default,

	-- End of MOTD
	["376"] = function(fields, whom, mesg, dest)
		-- TODO: reenable
		--send(":%s JOIN %s", nick, JOIN)
	end,

	-- "xyz" is now your hidden host (set by foo)
	["396"] = function(e) prin(MAINBUF, "--", "%s %s", e.fields[3], e.msg) end,

	-- No such nick/channel
	["401"] = function(e) prin(MAINBUF, "-!-", "No such nick/channel %s", e.fields[3]) end,

	-- <nick> is already in channel (response to /invite)
	["443"] = function(e)
		prin(e.fields[4], "-!-", "%s is already in %s", ncolor(e.fields[3]),
			e.fields[4])
	end,

	-- cannot join channel (you are banned)
	["474"] = function(e)
		prin(e.fields[3], "-!-", "you're banned creep")
		local buf = buf_idx(e.fields[3])
		if buf then switch_buf(buf) end
	end,

	-- WHOIS: <nick> is using a secure connection (response to /whois)
	["671"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] uses a secure connection", ncolor(e.fields[3]))
	end,

	-- CTCP stuff.
	["CTCP_ACTION"] = function(e) prin(e.dest, MAINBUF, "%s %s", ncolor(e.nick or nick), e.msg) end,
	["CTCP_VERSION"] = function(e)
		if CTCP_VERSION then
			prin(MAINBUF, "CTCP", "%s requested VERSION (reply: %s)", e.nick, CTCP_VERSION)
			irc.send("NOTICE %s :\1VERSION %s\1", e.nick, CTCP_VERSION)
		end
	end,
	["CTCP_SOURCE"] = function(e)
		if CTCP_SOURCE then
			prin(MAINBUF, "CTCP", "%s requested SOURCE (reply: %s)", e.nick, CTCP_SOURCE)
			irc.send("NOTICE %s :\1SOURCE %s\1", e.nick, CTCP_SOURCE)
		end
	end,
	["CTCP_PING"] = function(e)
		if CTCP_PING then
			prin(MAINBUF, "CTCP", "PING from %s", e.nick)
			irc.send("NOTICE %s :%s", e.nick, e.fields[2])
		end
	end,

	[0] = function(e)
		prin(e.dest, e.fields[1] .. " --", "%s", e.msg or e.dest)
	end
}

local function parseirc(reply)
	-- DEBUG
	util.append("logs", reply .. "\n")

	local event = irc.parse(reply)
	if not event then return end

	-- The first element in the fields array points to
	-- the type of message we're dealing with.
	local cmd = event.fields[1]

	-- TODO: remove this
	i=require'inspect'
	if not cmd then panic("cmd null (ev=%s) on reply %s\n", i(event), reply) end

	-- When recieving MOTD messages and similar stuff from
	-- the IRCd, send it to the main tab
	if cmd:find("00.") or cmd:find("2[56].") or cmd:find("37.") then
		event.dest = MAINBUF
	end

	-- When recieving PMs, send it to the buffer named after
	-- the sender
	if event.dest == nick then event.dest = event.nick end

	local handler = irchand[cmd] or irchand[0]
	handler(event)
end

local function send_both(fmt, ...)
	-- this is a simple function to send the input to the
	-- terminal and to the server at the same time.
	irc.send(fmt, ...)
	parseirc(format(fmt, ...))
end

local cmdhand = {
	["/next"] = function(a, args, inp)
		switch_buf(cur_buf + 1)
	end,
	["/prev"] = function(a, args, inp)
		switch_buf(cur_buf - 1)
	end,
	["/invite"] = function(a, args, inp)
		if not (buffers[cur_buf].name):find("#") then
			prin(MAINBUF, "-!-", "/invite must be executed in a channel buffer.")
			return
		end

		if not a or a == "" then return end
		irc.send(":%s INVITE %s :%s", nick, a, buffers[cur_buf].name)
	end,
	["/names"] = function(a, args, inp)
		irc.send("NAMES %s", a or buffers[cur_buf].name)
	end,
	["/topic"] = function(a, args, inp)
		irc.send("TOPIC %s", a or buffers[cur_buf].name)
	end,
	["/whois"] = function(a, args, inp)
		if a and a ~= "" then irc.send("WHOIS %s", a) end
	end,
	["/join"] = function(a, args, inp)
		irc.send(":%s JOIN %s", nick, a)
		status()

		local bufidx = buf_idx(dest)
		if not bufidx then
			buf_add(dest)
			bufidx = buf_idx(dest)
			status()
		end

		switch_buf(bufidx)
	end,
	["/part"] = function(a, args, inp)
		if not (buffers[cur_buf].name):find("#") then
			prin(MAINBUF, "-!-", "/invite must be executed in a channel buffer.")
			return
		end

		local msg = inp
		if not inp or inp ~= "" then msg = PART_MSG end

		irc.send(":%s PART %s :%s", nick, buffers[cur_buf].name, msg)
	end,
	["/nick"] = function(a, args, inp)
		irc.send("NICK %s", a)
		nick = a
	end,
	["/msg"] = function(a, args, inp)
		send_both(":%s PRIVMSG %s :%s", nick, a, args)
	end,
	["/raw"] = function(a, args, inp)
		irc.send("%s %s", a, args)
	end,
	["/quit"] = function(a, args, inp)
		local msg = inp
		if not inp or inp ~= "" then msg = QUIT_MSG end

		irc.send("QUIT :%s", msg)
		eprintf("[lurch exited]\n")
		tui.clean()
		os.exit(0)
	end,
	["/me"] = function(a, args, inp)
		send_both(":%s PRIVMSG %s :\1ACTION %s %s\1", nick, buffers[cur_buf].name, a, args)
	end,
	[0] = function(a, args, inp)
		send_both(":%s PRIVMSG %s :%s", nick, buffers[cur_buf].name, inp)
	end
}

local function parsecmd(inp)
	-- clear the input line.
	printf("\r\x1b[2K\r")

	local _cmd, a, args = inp:gmatch("([^%s]+)%s?([^%s]*)%s?(.*)")()

	if _cmd then
		local ac = (cmdhand[_cmd] or cmdhand[0]); ac(a, args, inp)
	end
end

function rt.init()
	tui.refresh()

	local _nick = NICK or os.getenv("IRCNICK") or os.getenv("USER")
	local user = USER or os.getenv("IRCUSER") or os.getenv("USER")
	local name = NAME or "hii im drukn"

	local r, e = irc.connect(HOST, PORT, _nick, user, name, PASS)
	if not r then panic("error: %s\n", e) end

	load_nick_highlight_colors()

	buf_add(MAINBUF)
	switch_buf(1)

	lurch.bind_keyseq("\\C-n")
	lurch.bind_keyseq("\\C-p")
end

local sighand = {
	-- SIGHUP
	[1] = function() return true end,
	-- SIGINT
	[2] = function() return true end,
	-- SIGPIPE
	[13] = function() end,
	-- SIGUSR1
	[10] = function() end,
	-- SIGUSR2
	[12] = function() end,
	-- SIGWINCH
	[28] = function() redraw() end,
	-- catch-all
	[0] = function() return true end,
}

function rt.on_signal(sig)
	local quitmsg = QUIT_MSG or "*poof*"
	local handler = sighand[sig] or sighand[0]
	if (handler)() then
		tui.clean()
		irc.send("QUIT :%s", quitmsg)
		eprintf("[lurch exited]\n")
		os.exit(0)
	end
end

function rt.on_lerror(err)
	tui.clean()
	irc.send("QUIT :%s", "*poof*")
end

function rt.on_timeout()
	panic("fatal timeout\n");
end

function rt.on_reply(reply)
	--local reply, e = lurch.conn_receive()
	--if not reply then panic("%s", e) end

	for line in reply:gmatch("(.-\r\n)") do
		parseirc(line)
	end
end

function rt.on_input()
	tty.curs_down(999)
	tty.curs_show()
end

function rt.on_rl_input(inp)
	parsecmd(inp)
end


local keyseq_handler = {
	-- Ctrl+n, Ctrl+p
	[14] = function() switch_buf(cur_buf + 1) end,
	[16] = function() switch_buf(cur_buf - 1) end,
}

function rt.on_keyseq(key)
	if keyseq_handler[key] then
		(keyseq_handler[key])()
	end
end

return rt