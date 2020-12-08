-- lurch: an extendable irc client in lua
-- (c) Kiëd Llaentenn

local rt = {}

local inspect = require('inspect')

local irc     = require('irc')
local config  = require('config')
local mirc    = require('mirc')
local util    = require('util')
local tui     = require('tui')
local tty     = require('tty')

local printf  = util.printf
local eprintf = util.eprintf
local format  = string.format

math.randomseed(os.time())

local MAINBUF = "<server>"

local colors = {}     -- List of colors used for nick highlighting
local set_colors = {} -- list of cached colors used for each nick/text

local nick = config.nick     -- The current nickname
local nicks = {}      -- Table of all nicknames

local cur_buf = nil   -- The current buffer
local buffers = {}    -- List of all opened buffers

local function nick_add(n)
	assert(n)

	local newnick = {}
	newnick.joined = {}
	newnick.access = {}

	nicks[n] = newnick
end

-- add a new buffer. statusbar() should be run after this
-- to add the new buffer to the statusline.
local function buf_add(name)
	assert(name)

	local newbuf = {}
	newbuf.history = {}
	newbuf.name    = name
	newbuf.unread  = 0
	newbuf.pings   = 0
	newbuf.scroll  = #newbuf.history
	newbuf.names   = {}
	newbuf.access  = {}

	buffers[#buffers + 1] = newbuf
	return #buffers
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

-- check if a message will ping a user.
local function msg_pings(msg)
	local rawmsg = mirc.remove(msg)
	local pingwords = config.pingwords
	pingwords[#pingwords + 1] = nick

	for _, pingw in ipairs(pingwords) do
		if rawmsg:find(pingw) then
			return true
		end
	end

	return false
end

local function load_highlight_colors()
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

local function highlight(text, text_as, no_bold)
	assert(text)
	if not text_as then text_as = text end

	-- store nickname highlight color, so that we don't have to
	-- calculate the text's hash each time
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

	return format("%s%s\x1b[m", esc, text)
end

local function inputbar()
	tty.curs_down(999)

	-- if we've scrolled up, don't draw the input.
	if buffers[cur_buf].scroll ~= #buffers[cur_buf].history then
		tty.curs_hide()
		tty.clear_line()
		printf("-- more --")
		return
	end

	tty.curs_show()

	local inp, cursor = lurch.rl_info()

	-- strip off trailing newline
	inp = inp:gsub("\n", "")

	-- by default, the prompt is <NICK>, but if the
	-- user is typing a command, change to prompt to an empty
	-- string; if the user has typed "/me", change the prompt
	-- to "* "
	local prompt
	if inp:find("/me ") == 1 then
		prompt = format("* %s ", highlight(nick))
		inp = inp:sub(5, #inp)
		cursor = cursor - 4
	elseif inp:find("/") == 1 then
		prompt = "\x1b[38m/\x1b[m"
		inp = inp:sub(2, #inp)
		cursor = cursor - 1
	else
		prompt = format("<%s> ", highlight(nick))
	end
	local rawprompt = prompt:gsub("\x1b%[.-m", "")

	-- strip off stuff from input that can't be shown on the
	-- screen
	inp = inp:sub(-(tui.tty_width - #rawprompt))

	-- draw the input buffer and move the cursor to the appropriate
	-- position.
	tty.clear_line()
	printf("%s%s", prompt, inp)
	printf("\r\x1b[%sC", cursor + #rawprompt)
end

local function statusbar()
	local chanlist = " "
	for buf = 1, #buffers do
		local ch = buffers[buf].name
		local bold = false

		if buf == cur_buf then
			if buffers[buf].pings  > 0 then bold = true end
			if buffers[buf].unread > 0 then
				local pnch = highlight(format(" %d %s %s%d ", buf, ch,
					"+", buffers[buf].unread), ch, not bold)
				chanlist = chanlist .. "\x1b[7m" .. pnch .. "\x1b[0m "
			else
				local pnch = highlight(format(" %d %s ", buf, ch), ch, true)
				chanlist = chanlist .. "\x1b[7m" .. pnch .. "\x1b[0m "
			end
		else
			if buffers[buf].pings  > 0 then bold = true end
			if buffers[buf].unread > 0 then
				local nch = highlight(format(" %d %s %s%d ", buf, ch,
					"+", buffers[buf].unread), ch, not bold)
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

	tty.curs_move_to_line(2)

	if buffers[cur_buf].history then
		local start = buffers[cur_buf].scroll - (tui.tty_height-4)
		for i = start, buffers[cur_buf].scroll do
			tty.clear_line()

			local msg = buffers[cur_buf].history[i]
			if msg then printf("\x1b[0m%s", msg) end

			tty.curs_down(1)
		end
	end

	-- redraw statusbar bar and input line.
	statusbar(); inputbar()

	tty.curs_show()
	tty.curs_restore()
end

local function buf_switch(ch)
	if buffers[ch] then
		cur_buf = ch
		buffers[cur_buf].unread = 0
		buffers[cur_buf].pings  = 0
		redraw()
	end
end

local function prin(dest, left, right_fmt, ...)
	local right = format(right_fmt, ...)

	assert(dest)
	assert(left)
	assert(right)

	-- fold message to width
	local default_width = tui.tty_width - config.left_col_width
	right = util.fold(right, config.right_col_width or default_width)
	right = right:gsub("\n", format("\n%s",
		util.strrepeat(" ", config.left_col_width + 2)))

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
		pad = (config.left_col_width + 1) - #raw
	end

	local out = format("\x1b[%sC%s %s", pad, left, right):gsub("\n+$", "")

	local bufidx = buf_idx(dest)
	if not bufidx then
		buf_add(dest)
		bufidx = buf_idx(dest)
		statusbar()
	end

	if dest == buffers[cur_buf].name and buffers[cur_buf].scroll == #buffers[cur_buf].history then
		tty.curs_hide()
		tty.curs_save()

		tty.curs_down(999)

		tty.clear_line()
		printf("%s\n", out)
		tty.clear_line()

		tty.curs_restore()
		tty.curs_show()

		-- since we overwrote the inputbar, redraw it
		inputbar()
	else
		buffers[bufidx].unread = buffers[bufidx].unread + 1
		statusbar()
	end

	-- save to buffer history and update the scroll offset.
	local prev_hist_sz = #buffers[cur_buf].history
	for line in out:gmatch("([^\n]+)\n?") do
		local histsz = #buffers[bufidx].history
		buffers[bufidx].history[histsz + 1] = line
	end
	if buffers[cur_buf].scroll == prev_hist_sz then
		buffers[bufidx].scroll = #buffers[bufidx].history
	end
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
			prin(e.dest, "--", "Mode [%s] by %s", mode, highlight(e.nick))
		else
			prin(MAINBUF, "--", "Mode %s", e.msg)
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
		prin(e.dest, "<--", "%s has left %s (%s)", highlight(e.nick), e.dest, e.msg)
	end,
	["KICK"] = function(e)
		prin(e.dest, "<--", "%s has kicked %s (%s)", highlight(e.nick), highlight(e.fields[3]), e.msg)
	end,
	["INVITE"] = function(e)
		-- TODO: auto-join on invite?
		prin(MAINBUF, "--", "%s sent an invite to %s", e.nick, e.msg)
	end,
	["PRIVMSG"] = function(e)
		local sender = e.nick or e.from

		-- remove extra characters from nick that won't fit.
		if #sender > (config.left_col_width-2) then
			sender = (sender):sub(1, config.left_col_width-3)
			sender = sender .. "\x1b[m\x1b[37m+\x1b[m"
		end

		if msg_pings(e.msg) then
			sender = format("<\x1b[7m%s\x1b[m>", highlight(sender, e.nick))

			-- normally, we'd wait for prin() to create the buffer,
			-- but since we need to manipulate the number of pings we
			-- can't wait
			if not buf_idx(e.dest) then buf_add(e.dest) end
			local bufidx = buf_idx(e.dest)
			buffers[bufidx].pings = buffers[bufidx].pings + 1
		else
			sender = format("<%s>", highlight(sender, e.nick))
		end

		-- convert or remove mIRC IRC colors.
		if config.show_mirc_colors then
			e.msg = mirc.to_tty_seq(e.msg)
		else
			e.msg = mirc.remove(e.msg)
		end

		prin(e.dest, sender, "%s", e.msg)
	end,
	["QUIT"] = function(e)
		-- display quit message for all buffers that user has joined.
		for _, buf in ipairs(buffers) do
			if not buffers[i].names[e.nick] then return end
			prin(buf, "<--", "%s has quit %s (%s)", highlight(e.nick), e.dest, e.msg)
		end
	end,
	["JOIN"] = function(e)
		-- sometimes the channel joined is contained in the message.
		if not e.dest or e.dest == "" then
			e.dest = e.msg
		end

		-- if the buffer isn't open yet, create it.
		local buf_idx = buf_idx(e.dest)
		if not buf_idx then buf_idx = buf_add(e.dest) end

		-- add to the list of users in that channel.
		buffers[buf_idx].names[e.nick] = true

		-- if we are the ones joining, then switch to that buffer.
		if e.nick == nick then buf_switch(#buffers) end

		prin(e.dest, "-->", "%s has joined %s", highlight(e.nick), e.dest)
	end,
	["NICK"] = function(e)
		-- if the user changed the nickname, update the current nick.
		if e.nick == nick then nick = e.msg end

		-- copy across nick information (this preserves nick highlighting across
		-- nickname changes), and display the nick change for all buffers that
		-- have that user
		set_colors[e.msg] = set_colors[e.nick]
		set_colors[e.nick] = nil
		for _, buf in ipairs(buffers) do
			if not buf.names[e.nick] then return end

			buf.names[e.nick] = nil; buf.names[e.msg]  = true
			prin(ch, "--@", "%s is now known as %s", highlight(e.nick),
				highlight(e.msg))
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
		prin(MAINBUF, "WHOIS", "[%s] (%s!%s@%s): %s", highlight(e.fields[3]),
			e.fields[3], e.fields[4], e.fields[5], e.msg)
	end,

	-- WHOIS: RPL_WHOISSERVER (response to /whois)
	-- <nick> <server> :serverinfo
	["312"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] %s (%s)", highlight(e.fields[3]), e.fields[4], e.msg)
	end,

	-- End of WHOIS
	["318"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] End of WHOIS info.", highlight(e.fields[3]))
	end,

	-- URL for channel
	["328"] = function(e) prin(e.dest, "URL", "%s", e.msg) end,

	-- WHOIS: <nick> is logged in as <user> (response to /whois)
	["330"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] is logged in as %s", highlight(e.fields[3]),
			highlight(e.fields[4]))
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
			prin(e.dest, "--", "Topic last set by %s (%s)", highlight(n), e.fields[4])
		else
			local datetime = os.date("%Y-%m-%d %H:%M:%S", e.msg)
			prin(e.dest, "--", "Topic last set by %s on %s", highlight(e.fields[4]), datetime)
		end
	end,

	-- invited <nick> to <chan> (response to /invite)
	["341"] = function(e)
		prin(e.fields[4], "--", "invited %s to %s", highlight(e.fields[3]), e.fields[4])
	end,

	-- Reply to /names
	["353"] = function(e)
		-- if the buffer isn't open yet, create it.
		local buf_idx = buf_idx(e.dest)
		if not buf_idx then buf_idx = buf_add(e.dest) end

		local nicklist = ""

		for _nick in (e.msg):gmatch("([^%s]+)%s?") do
			local access = ""
			if _nick:find("[%~@%%&%+!]") then
				access = _nick:gmatch(".")()
				_nick = _nick:gsub(access, "")
			end

			nicklist = format("%s%s%s ", nicklist, access, highlight(_nick))

			-- TODO: update access with mode changes
			buffers[buf_idx].names[_nick] = true
			buffers[buf_idx].access[_nick] = access
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
	["376"] = function(_, _, _, _)
		for c = 1, #config.channels do
			irc.send(":%s JOIN %s", nick, config.channels[c])
		end
	end,

	-- "xyz" is now your hidden host (set by foo)
	["396"] = function(e) prin(MAINBUF, "--", "%s %s", e.fields[3], e.msg) end,

	-- No such nick/channel
	["401"] = function(e) prin(MAINBUF, "-!-", "No such nick/channel %s", e.fields[3]) end,

	-- <nick> is already in channel (response to /invite)
	["443"] = function(e)
		prin(e.fields[4], "-!-", "%s is already in %s", highlight(e.fields[3]),
			e.fields[4])
	end,

	-- cannot join channel (you are banned)
	["474"] = function(e)
		prin(e.fields[3], "-!-", "you're banned creep")
		local buf = buf_idx(e.fields[3])
		if buf then buf_switch(buf) end
	end,

	-- WHOIS: <nick> is using a secure connection (response to /whois)
	["671"] = function(e)
		prin(MAINBUF, "WHOIS", "[%s] uses a secure connection", highlight(e.fields[3]))
	end,

	-- CTCP stuff.
	["CTCP_ACTION"] = function(e) prin(e.dest, "*", "%s %s", highlight(e.nick or nick), e.msg) end,
	["CTCP_VERSION"] = function(e)
		if config.ctcp_version then
			prin(MAINBUF, "CTCP", "%s requested VERSION (reply: %s)", e.nick, config.ctcp_version)
			irc.send("NOTICE %s :\1VERSION %s\1", e.nick, config.ctcp_version)
		end
	end,
	["CTCP_SOURCE"] = function(e)
		if config.ctcp_source then
			prin(MAINBUF, "CTCP", "%s requested SOURCE (reply: %s)", e.nick, config.ctcp_source)
			irc.send("NOTICE %s :\1SOURCE %s\1", e.nick, config.ctcp_source)
		end
	end,
	["CTCP_PING"] = function(e)
		if config.ctcp_ping then
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
	if not cmd then panic("cmd null (ev=%s) on reply %s\n", inspect(event), reply) end

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

local cmdhand
cmdhand = {
	["/up"] = {
		help = {},
		fn = function(_, _, _)
			local scr = tui.tty_height - 3
			if buffers[cur_buf].scroll >= 0 then
				buffers[cur_buf].scroll = buffers[cur_buf].scroll - scr
			end
			redraw()
		end
	},
	["/down"] = {
		help = {},
		fn = function(_, _, _)
			local scr = tui.tty_height - 3
			if buffers[cur_buf].scroll <= #buffers[cur_buf].history then
				buffers[cur_buf].scroll = buffers[cur_buf].scroll + scr
			end
			redraw()
		end
	},
	["/clear"] = {
		help = { "Clear the current buffer." },
		fn = function(_, _, _) buffers[cur_buf].history = {}; redraw() end
	},
	["/redraw"] = {
		help = { "Redraw the screen. Ctrl+L may also be used." },
		fn = function(_, _, _) redraw() end,
	},
	["/next"] = {
		help = { "Switch to the next buffer. Ctrl+N may also be used." },
		fn = function(_, _, _) buf_switch(cur_buf + 1) end
	},
	["/prev"] = {
		help = { "Switch to the previous buffer. Ctrl+P may also be used." },
		fn = function(_, _, _) buf_switch(cur_buf - 1) end
	},
	["/invite"] = {
		REQUIRE_CHANBUF = true,
		REQUIRE_ARG = true,
		help = { "Invite a user to the current channel." },
		usage = "<user>",
		fn = function(a, _, _)
			irc.send(":%s INVITE %s :%s", nick, a, buffers[cur_buf].name)
		end
	},
	["/names"] = {
		REQUIRE_CHANBUF_OR_ARG = true,
		help = { "See the users for a channel (the current one by default)." },
		usage = "[channel]",
		fn = function(a, _, _) irc.send("NAMES %s", a or buffers[cur_buf].name) end
	},
	["/topic"] = {
		-- TODO: separate settopic command
		REQUIRE_CHANBUF_OR_ARG = true,
		help = { "See the current topic for a channel (the current one by default)." },
		usage = "[channel]",
		fn = function(a, _, _) irc.send("TOPIC %s", a or buffers[cur_buf].name) end
	},
	["/whois"] = {
		REQUIRE_ARG = true,
		help = { "See WHOIS information for a user." },
		usage = "<user>",
		fn = function(a, _, _) irc.send("WHOIS %s", a) end
	},
	["/join"] = {
		REQUIRE_ARG = true,
		help = { "Join a channel; if already joined, focus that buffer." },
		usage = "[channel]",
		fn = function(a, _, _)
			irc.send(":%s JOIN %s", nick, a)
			statusbar()

			local bufidx = buf_idx(a)
			if not bufidx then
				buf_add(a)
				bufidx = buf_idx(a)
				statusbar()
			end

			buf_switch(bufidx)
		end
	},
	["/part"] = {
		REQUIRE_CHANBUF_OR_ARG = true,
		help = { "Part the current channel." },
		usage = "[part_message]",
		fn = function(a, args, _)
			local msg = config.part_msg
			if a and a ~= "" then msg = format("%s %s", a, args) end
			irc.send(":%s PART %s :%s", nick, buffers[cur_buf].name, msg)
		end
	},
	["/quit"] = {
		help = { "Exit lurch." },
		usage = "[quit_message]",
		fn = function(a, args, _)
			local msg
			if not a or a == "" then
				msg = config.quit_msg
			else
				msg = format("%s %s", a, args)
			end

			irc.send("QUIT :%s", msg)
			eprintf("[lurch exited]\n")
			tui.clean()
			os.exit(0)
		end
	},
	["/nick"] = {
		REQUIRE_ARG = true,
		help = { "Change nickname." },
		usage = "<nickname>",
		fn = function(a, _, _) irc.send("NICK %s", a); nick = a; end
	},
	["/msg"] = {
		REQUIRE_ARG = true,
		help = { "Privately message a user. Opens a new buffer." },
		usage = "<user> <message...>",
		fn = function(a, args, _)
			send_both(":%s PRIVMSG %s :%s", nick, a, args)
		end
	},
	["/raw"] = {
		REQUIRE_ARG = true,
		help = { "Send a raw IRC command to the server." },
		usage = "<command> <args>",
		fn = function(a, args, _) irc.send("%s %s", a, args) end
	},
	["/me"] = {
		REQUIRE_ARG = true,
		REQUIRE_CHAN_OR_USERBUF = true,
		help = { "Send a CTCP action to the current channel." },
		usage = "<text>",
		fn = function(a, args, _)
			send_both(":%s PRIVMSG %s :\1ACTION %s %s\1", nick,
				buffers[cur_buf].name, a, args)
		end,
	},
	["/shrug"] = {
		REQUIRE_CHAN_OR_USERBUF = true,
		help = { "Send a shrug to the current channel." },
		fn = function(_, _, _)
			send_both(":%s PRIVMSG %s :¯\\_(ツ)_/¯", nick, buffers[cur_buf].name)
		end,
	},
	["/help"] = {
		help = { "You know what this command is for." },
		usage = "[command]",
		fn = function(a, _, _)
			local curbuf = buffers[cur_buf].name

			if not a or a == "" then
				-- all set up and ready to go !!!
				prin(curbuf, "--", "hello bastard !!!")
				return
			end

			local cmd = a
			if not (cmd:find("/") == 1) then cmd = "/" .. cmd end

			if not cmdhand[cmd] then
				prin(curbuf, "-!-", "No such command '%s'", a)
				return
			end

			local cmdinfo = cmdhand[cmd]
			prin(curbuf, "--", "")
			prin(curbuf, "--", "Help for %s", cmd)

			if cmdinfo.usage then
				prin(curbuf, "--", "usage: %s %s", cmd, cmdinfo.usage)
			end

			prin(curbuf, "--", "")

			for i = 1, #cmdinfo.help do
				prin(curbuf, "--", "%s", cmdinfo.help[i])
				prin(curbuf, "--", "")
			end

			if cmdinfo.REQUIRE_CHANBUF then
				prin(curbuf, "--", "This command must be run in a channel buffer.")
				prin(curbuf, "--", "")
			elseif cmdinfo.REQUIRE_CHAN_OR_USERBUF then
				prin(curbuf, "--", "This command must be run in a channel or a user buffer.")
				prin(curbuf, "--", "")
			end
		end,
	},
	["/list"] = {
		-- TODO: list user-defined commands.
		help = { "List builtin and user-defined lurch commands." },
		fn = function(_, _, _)
			local curbuf = buffers[cur_buf].name
			prin(curbuf, "--", "")
			prin(curbuf, "--", "[builtin]")

			local cmdlist = ""
			for k, _ in pairs(cmdhand) do
				cmdlist = cmdlist .. k .. " "
			end

			prin(curbuf, "--", "%s", cmdlist)
		end,
	},
}

local function parsecmd(inp)
	-- the input line clears itself, there's no need to clear it...

	-- split the input line into the command (first word), a (second
	-- word), and args (the rest of the input)
	local _cmd, a, args = inp:gmatch("([^%s]+)%s?([^%s]*)%s?(.*)")()
	if not _cmd then return end

	-- if the command matches "/<number>", switch to that buffer.
	if _cmd:match("/%d+$") then
		buf_switch(tonumber(_cmd:sub(2, #_cmd)))
		return
	end

	-- if the command matches "/#<channel>", switch to that buffer.
	if _cmd:match("/#[^%s]+$") then
		local bufidx = buf_idx(_cmd:sub(2, #_cmd))
		if bufidx then buf_switch(bufidx) end
		return
	end

	-- if the command exists, then run it
	if _cmd:find("/") == 1 then
		if not cmdhand[_cmd] and not config.commands[_cmd] then
			prin(buffers[cur_buf].name, "NOTE", "%s not implemented yet", _cmd)
			return
		end

		local hand = cmdhand[_cmd] or config.commands[_cmd]

		if hand.REQUIRE_CHANBUF and not (buffers[cur_buf].name):find("#") then
			prin(buffers[cur_buf].name, "-!-",
				"%s must be executed in a channel buffer.", _cmd)
			return
		end

		if hand.REQUIRE_ARG and (not a or a == "") then
			prin(buffers[cur_buf].name, "-!-", "%s requires an argument.", _cmd)
			return
		end

		if hand.REQUIRE_CHANBUF_OR_ARG and (not a or a == "") and not (buffers[cur_buf].name):find("#") then
			prin(buffers[cur_buf].name, "-!-",
				"%s must be executed in a channel buffer or must be run with an argument.", _cmd)
			return
		end

		if hand.REQUIRE_CHAN_OR_USERBUF and cur_buf == 1 then
			prin(buffers[cur_buf].name, "-!-",
				"%s must be executed in a channel or user buffer.", _cmd)
		end

		(hand.fn)(a, args, inp)
	else
		-- since the command doesn't exist, just send it as a message
		local m = format(":%s PRIVMSG %s :%s", nick, buffers[cur_buf].name, inp)
		irc.send("%s", m); parseirc(m)
	end
end

function rt.init()
	tui.refresh()

	local _nick = config.nick or os.getenv("IRCNICK") or os.getenv("USER")
	local user  = config.user or os.getenv("IRCUSER") or os.getenv("USER")
	local name  = config.name or _nick

	local r, e = irc.connect(config.server, config.port,
		_nick, user, name, config.server_password)
	if not r then panic("error: %s\n", e) end

	load_highlight_colors()

	buf_add(MAINBUF)
	buf_switch(1)

	lurch.bind_keyseq("\\C-n")
	lurch.bind_keyseq("\\C-p")
	lurch.bind_keyseq("\\C-l")
	lurch.bind_keyseq("\\C-w")
	lurch.bind_keyseq("\\C-r")
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
	local quitmsg = config.quit_msg or "*poof*"
	local handler = sighand[sig] or sighand[0]
	if (handler)() then
		tui.clean()
		irc.send("QUIT :%s", quitmsg)
		eprintf("[lurch exited]\n")
		os.exit(0)
	end
end

function rt.on_lerror(_)
	tui.clean()
	irc.send("QUIT :%s", "*poof*")
end

function rt.on_timeout()
	panic("fatal timeout\n");
end

function rt.on_reply(reply)
	for line in reply:gmatch("(.-\r\n)") do
		parseirc(line)
	end
end

-- every time a key is pressed, redraw the prompt, and
-- write the input buffer.
function rt.on_input()
	inputbar()
end

function rt.on_rl_input(inp)
	parsecmd(inp)
end

local keyseq_handler = {
	-- Ctrl+l
	[12] = "/redraw",

	-- Ctrl+n, Ctrl+p
	[14] = "/next",
	[16] = "/prev",

	-- TODO: PageUp, PageDown
	[23] = "/up",
	[18] = "/down",
}

function rt.on_keyseq(key)
	if keyseq_handler[key] then
		parsecmd(keyseq_handler[key])
	end
end

function rt.on_complete(text, from, to)
	local incomplete = text:sub(from, to)
	local matches = {}

	-- Possible matches:
	--     for start of line: "/<command>", "/#<channel>", "nick: "
	--     for middle of line: "nick "
	local possible = {}
	if from == 1 then
		for k, _ in pairs(cmdhand) do possible[#possible + 1] = k end
		for _, v in ipairs(buffers) do
			if (v.name):find("#") == 1 then
				possible[#possible + 1] = format("/%s", v.name)
			end
		end

		for k, _ in pairs(buffers[cur_buf].names) do
			possible[#possible + 1] = format("%s:", k)
		end
	else
		for k, _ in pairs(buffers[cur_buf].names) do
			possible[#possible + 1] = format("%s", k)
		end
	end

	for _, v in ipairs(possible) do
		if incomplete == v:sub(1, #incomplete) then
			matches[#matches + 1] = v
		end
	end

	return matches
end

return rt
