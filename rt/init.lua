-- lurch: an extendable irc client in lua
-- (c) Kiëd Llaentenn

local rt = {}

local inspect = require('inspect')

local irc       = require('irc')
local callbacks = require('callbacks')
local config    = require('config')
local mirc      = require('mirc')
local util      = require('util')
local tui       = require('tui')
local tb        = require('tb')
local tbrl      = require('tbrl')

local printf    = util.printf
local eprintf   = util.eprintf
local panic     = util.panic
local format    = string.format
local hcol      = tui.highlight

L_ERR   = "-!-"
L_NRM   = "--"

DBGFILE = "/tmp/lurch_debug"
MAINBUF = config.host

server  = { caps = {} }  -- Server information
nick    = config.nick    -- The current nickname
cbuf = nil               -- The current buffer
bufs = {}                -- List of all opened buffers

--local buf_add
--local buf_idx
--local buf_cur
--local buf_idx_or_add
--local buf_with_nick
--local buf_addname
--local msg_pings
--local writelog
--local buf_switch
--local prin_irc
--local prin_cmd
--local prin
--local parseirc
--local parsecmd

-- a simple wrapper around irc.send.
function send(fmt, ...)
    if os.getenv("LURCH_DEBUG") then
        util.append(DBGFILE,
            format(">> %s\n", format(fmt, ...)))
    end

    irc.send(fmt, ...)
end

-- add a new buffer. statusbar() should be run after this
-- to add the new buffer to the statusline.
function buf_add(name)
    assert(name)

    local newbuf = {}
    newbuf.history = {}     -- lines in buffer.
    newbuf.name    = name
    newbuf.unreadh = 0      -- high-priority unread messages
    newbuf.unreadl = 0      -- low-priority unread messages
    newbuf.pings   = 0      -- maximum-priority unread messages
    newbuf.scroll  = 0      -- scroll offset.
    newbuf.names   = {}     -- nicknames in buffer/channel.
    newbuf.access  = {}     -- privilege for nicknames. (e.g. ~, @, +)

    local n_idx = #bufs + 1
    bufs[n_idx] = newbuf
    return n_idx
end

-- check if a buffer exists, and if so, return the index
-- for that buffer.
function buf_idx(name)
    for i = 1, #bufs do
        if bufs[i].name == name then return i end
    end
    return nil
end

function buf_cur()
    return bufs[cbuf].name
end

function buf_idx_or_add(name)
    local idx = buf_idx(name)
    if not idx then idx = buf_add(name) end
    return idx
end

function buf_with_nick(name, fn, mainbuf)
    for i, buf in ipairs(bufs) do
        if buf.names[nick] then
            if not mainbuf and buf.name == MAINBUF then
            else
                fn(i, buf)
            end
        end
    end
end

function buf_addname(bufidx, name)
    bufs[bufidx].names[name] = true
    bufs[buf_idx(MAINBUF)].names[name] = true
end

-- switch to a buffer and redraw the screen.
function buf_switch(ch)
    if bufs[ch] then
        cbuf = ch

        -- reset scroll, unread notifications
        bufs[ch].scroll  = 0
        bufs[ch].unreadl = 0; bufs[ch].unreadh = 0
        bufs[ch].pings   = 0

        tui.redraw(tbrl.bufin[tbrl.hist], tbrl.cursor)
    end
end

-- check if a message will ping a user.
function msg_pings(sender, msg)
    -- can't ping yourself.
    if sender and sender == nick then
        return false
    end

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

function writelog(time, dest, left, right_fmt, ...)
    local logdir  = format("%s/logs/%s", __LURCH_EXEDIR, dest)
    local logfile = format("%s/%s.txt", logdir, os.date("%Y-%m-%d", time))

    lurch.mkdirp(logdir)

    local logentry = format("%s\t%s\t\t%s\n",
        os.date("%Y-%m-%dT%H:%M:%SZ", time), left, right_fmt:format(...))

    util.append(logfile, mirc.remove(logentry))
end

-- print a response to an irc message.
local last_ircevent = nil
function prin_irc(prio, dest, left, right_fmt, ...)
    -- get the offset defined in the configuration and parse it.
    local offset = assert(util.parse_offset(config.tz))
    local time

    -- if server-time is available, use that time instead of the
    -- local time.
    if server.caps["server-time"] and last_ircevent and last_ircevent.tags.time then
        -- the server-time is stored as a tag in the IRC message, in the
        -- format yyyy-mm-ddThh:mm:ss.sssZ, but is in the UTC timezone.
        -- convert it to the timezone the user wants.
        local srvtime = last_ircevent.tags.time
        local utc_time   = util.time_from_iso8601(srvtime)
        time = utc_time + (offset * 60 * 60)

        prin(prio, os.date("%H:%M", time), dest, left, right_fmt, ...)
    else
        time = util.time_with_offset(offset)
        prin(prio, os.date("%H:%M", time), dest, left, right_fmt, ...)
    end

    -- don't log batch messages.
    if not last_ircevent or (last_ircevent and not last_ircevent.tags.time) then
        writelog(time, dest, left, right_fmt, ...)
    end
end

-- print text in response to a command.
function prin_cmd(dest, left, right_fmt, ...)
    local priority = 0
    if left == L_ERR then priority = 2 end

    -- get the offset defined in the configuration and parse it.
    local offset = assert(util.parse_offset(config.tz))

    local now = util.time_with_offset(offset)
    prin(priority, os.date("%H:%M", now), dest, left, right_fmt, ...)
end

function prin(priority, timestr, dest, left, right_fmt, ...)
    assert(timestr)
    assert(dest)
    assert(left)
    assert(right_fmt)

    local redraw_statusbar = false

    local bufidx = buf_idx(dest)
    if not bufidx then
        bufidx = buf_add(dest)
        redraw_statusbar = true
    end

    local right = format(right_fmt, ...)
    --local out = tui.format_line(timestr, left, right_fmt, ...)

    -- Add the output to the history and wait for it to be drawn.
    local histsz = #bufs[bufidx].history
    bufs[bufidx].history[histsz + 1] = { timestr, left, right }

    -- if the buffer we're writing to is focused and is not scrolled up,
    -- draw the text; otherwise, add to the list of unread notifications
    local cbuf = bufs[cbuf]
    if dest == cbuf.name and cbuf.scroll ==  0 then
        tui.buffer_text()
    else
        if priority == 0 then
            bufs[bufidx].unreadl = bufs[bufidx].unreadl + 1
        elseif priority == 1 then
            bufs[bufidx].unreadh = bufs[bufidx].unreadh + 1
        elseif priority == 2 then
            bufs[bufidx].pings = bufs[bufidx].pings + 1
        end

        redraw_statusbar = true
    end

    if redraw_statusbar then tui.statusbar() end
end

local function none(_) end
local function default2(e) prin_irc(0, MAINBUF, "--", "There are %s %s", e.fields[3], e.msg) end
local function default(e) prin_irc(0, e.dest, "--", "%s", e.msg) end

local irchand = {
    ["PING"] = function(e)   send("PONG :%s", e.dest or e.msg) end,
    ["ACCOUNT"] = function(e)
        assert(server.caps["account-notify"])

        -- account-notify is enabled, and the server is notifying
        -- us that one user has logged in/out of an account
        local msg
        local account = e.fields[2] or e.msg
        if not account then
            msg = format("%s unidentified", hcol(e.nick))
        else
            msg = format("%s has identified as %s", hcol(e.nick), account)
        end

        buf_with_nick(e.nick, function(_, buf)
            prin_irc(0, buf.name, "--", "(Account) %s", msg)
        end)
    end,
    ["AWAY"] = function(e)
        assert(server.caps["away-notify"])

        -- away notify is enabled, and the server is giving us the
        -- status of a user in a channel.
        --
        -- TODO: keep track of how long users are away, and when they
        -- come back, set the message to "<nick> is back (gone <time>)"
        local msg
        if not e.msg or e.msg == "" then
            msg = format("%s is back", hcol(e.nick))
        else
            msg = format("%s is away: %s", hcol(e.nick), e.msg)
        end

        buf_with_nick(e.nick, function(_, buf)
            prin_irc(0, buf.name, "--", "(Away) %s", msg)
        end)
    end,
    ["MODE"] = function(e)
        if not e.dest then e.dest = e.msg end
        if (e.dest):find("#") then
            local mode = e.fields[3] or ""
            for i = 4, #e.fields do
                if not e.fields[i] then break end
                mode = mode .. " " .. e.fields[i]
            end
            mode = mode .. " " .. e.msg
            prin_irc(0, e.dest, "--", "Mode [%s] by %s", mode, hcol(e.nick))
        else
            prin_irc(0, MAINBUF, "--", "Mode %s", e.msg)
        end
    end,
    ["NOTICE"] = function(e)
        local prio = 1
        if msg_pings(e.nick, e.msg) then prio = 2 end

        local dest = e.dest
        if dest == "*" or not dest then dest = MAINBUF end

        if e.nick then
            prin_irc(1, dest, "NOTE", "<%s> %s", hcol(e.nick), e.msg)
        else
            prin_irc(1, dest, "NOTE", "%s", e.msg)
        end
    end,
    ["TOPIC"] = function(e)
        prin_irc(0, e.dest, "TOPIC", "%s changed the topic to \"%s\"", hcol(e.nick), e.msg)
    end,
    ["PART"] = function(e)
        prin_irc(0, e.dest, "<--", "%s has left %s (%s)",
            hcol(e.nick), e.dest, e.msg)
        local idx = buf_idx_or_add(e.dest)
        bufs[idx].names[e.nick] = false
    end,
    ["KICK"] = function(e)
        local p = 0
        if e.fields == nick then p = 2 end -- if the user was kicked, ping them
        prin_irc(p, e.dest, "<--", "%s has kicked %s (%s)", hcol(e.nick),
            hcol(e.fields[3]), e.msg)
    end,
    ["INVITE"] = function(e)
        -- TODO: auto-join on invite?
        prin_irc(2, MAINBUF, "--", "%s invited you to %s",
            e.nick, e.fields[3] or e.msg)
    end,
    ["PRIVMSG"] = function(e)
        local rsender = e.nick or e.from
        local sender = rsender
        local priority = 1

        -- remove extra characters from nick that won't fit.
        if #sender > (config.left_col_width-2) then
            sender = (sender):sub(1, config.left_col_width-3)
            sender = sender .. format("\x0f\x0314+\x0f")
        end

        if msg_pings(rsender, e.msg) then
            sender = format("<\x16%s\x0f>", hcol(sender, rsender))
            priority = 2
        else
            sender = format("<%s>", hcol(sender, rsender))
        end

        -- convert or remove mIRC IRC colors.
        if not config.mirc then
            e.msg = mirc.remove(e.msg)
        end

        prin_irc(priority, e.dest, sender, "%s", e.msg)
    end,
    ["QUIT"] = function(e)
        -- display quit message for all buffers that user has joined,
        -- except the main buffer.
        buf_with_nick(e.nick, function(i, buf)
            prin_irc(0, buf.name, "<--", "%s has quit (%s)", hcol(e.nick), e.msg)
            bufs[i].names[e.nick] = false
        end)
    end,
    ["JOIN"] = function(e)
        -- sometimes the channel joined is contained in the message.
        if not e.dest or e.dest == "" then e.dest = e.msg end

        -- if the buffer isn't open yet, create it.
        local bufidx = buf_idx_or_add(e.dest)

        -- add to the list of users in that channel.
        buf_addname(bufidx, e.nick)

        -- if we are the ones joining, then switch to that buffer.
        if e.nick == nick then buf_switch(#bufs) end

        prin_irc(0, e.dest, "-->", "%s has joined %s", hcol(e.nick), e.dest)
    end,
    ["NICK"] = function(e)
        -- copy across nick information (this preserves nick highlighting across
        -- nickname changes), and display the nick change for all bufs that
        -- have that user
        for _, buf in ipairs(bufs) do
            if buf.names[e.nick] or e.nick == nick then
                prin_irc(0, buf.name, "--@", "%s is now known as %s",
                    hcol(e.nick), hcol(e.msg))
                buf.names[e.nick] = nil; buf.names[e.msg] = true
            end
        end
        tui.set_colors[e.msg]  = tui.set_colors[e.nick]
        tui.set_colors[e.nick] = nil

        -- if the user changed the nickname, update the current nick.
        if e.nick == nick then nick = e.msg end
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

    -- WHOIS: <nick> has TLS cert fingerprint of sdflsd453lkd8
    ["276"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] %s", hcol(e.fields[3]), e.msg)
    end,

    -- WHOIS: <nick> is a registered nick
    ["307"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] %s", hcol(e.fields[3]), e.msg)
    end,

    -- WHOIS: RPL_WHOISUSER (response to /whois)
    -- <nick> <user> <host> * :realname
    ["311"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] (%s!%s@%s): %s", hcol(e.fields[3]),
            e.fields[3], e.fields[4], e.fields[5], e.msg)
    end,

    -- WHOIS: RPL_WHOISSERVER (response to /whois)
    -- <nick> <server> :serverinfo
    ["312"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] %s (%s)", hcol(e.fields[3]), e.fields[4], e.msg)
    end,

    -- WHOIS: <nick> has been idle for 45345 seconds, and has been online since 4534534534
    ["317"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] has been idle for %s",
            hcol(e.fields[3]), util.fmt_duration(tonumber(e.fields[4])))

        -- not all servers send the "has been online" bit...
        if e.fields[5] then
            prin_irc(0, buf_cur(), "WHOIS", "[%s] has been online since %s",
                hcol(e.fields[3]), os.date("%Y-%m-%d %H:%M", e.fields[5]))
        end
    end,

    -- End of WHOIS
    ["318"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] End of WHOIS info.", hcol(e.fields[3]))
    end,

    -- WHOIS: <user> has joined #chan1, #chan2, #chan3
    ["319"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] has joined %s", hcol(e.fields[3]), e.msg)
    end,

    -- URL for channel
    ["328"] = function(e) prin_irc(0, e.dest, "URL", "%s", e.msg) end,

    -- WHOIS: <nick> is logged in as <user> (response to /whois)
    ["330"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] is logged in as %s", hcol(e.fields[3]),
            hcol(e.fields[4]))
    end,

    -- No topic set
    ["331"] = function(e) prin_irc(0, e.dest, L_ERR, "No topic set for %s", e.dest) end,

    -- TOPIC for channel
    ["332"] = function(e) prin_irc(0, e.dest, "TOPIC", "%s", e.msg) end,

    -- TOPIC last set by nick!user@host
    ["333"] = function(e)
        -- sometimes, the nick is in the fields
        local n = (e.fields[4]):gmatch("(.-)!")()
        if n then
            prin_irc(0, e.dest, "--", "Topic last set by %s (%s)", hcol(n), e.fields[4])
        else
            local datetime = os.date("%Y-%m-%d %H:%M:%S", tonumber(e.msg))
            prin_irc(0, e.dest, "--", "Topic last set by %s on %s", hcol(e.fields[4]), datetime)
        end
    end,

    -- invited <nick> to <chan> (response to /invite)
    ["341"] = function(e)
        prin_irc(0, e.msg, "--", "Invited %s to %s", hcol(e.fields[3]), e.msg)
    end,

    -- Reply to /names
    ["353"] = function(e)
        -- if the buffer isn't open yet, create it.
        local bufidx = buf_idx_or_add(e.dest)

        local nicklist = ""

        for _nick in (e.msg):gmatch("([^%s]+)%s?") do
            local access = ""
            if _nick:find("[%~@%%&%+!]") then
                access = _nick:gmatch(".")()
                _nick = _nick:gsub(access, "")
            end

            nicklist = format("%s%s%s ", nicklist, access, hcol(_nick))

            -- TODO: update access with mode changes
            -- TODO: show access in PRIVMSGs
            buf_addname(bufidx, _nick)
            bufs[bufidx].access[_nick] = access
        end

        prin_irc(0, e.dest, "NAMES", "%s", nicklist)
    end,

    -- End of /names
    ["366"] = function(e)
        local dest   = assert(e.dest)
        local bufidx = assert(buf_idx(dest))

        -- print a nice summary of those in the channel.
        --
        -- peasants:   normals, those without a special mode
        -- loudmouths: those with +v (voices)
        -- halfwits:   those with +h (halfops)
        -- operators:  those with +o
        -- founders:   those with +q
        -- irccops:    those with +Y (server admins)
        local peasants,  loudmouths, halfwits
        local operators, founders,   irccops
        peasants  = 0; loudmouths = 0; halfwits = 0;
        operators = 0; founders   = 0; irccops  = 0;

        local total = 0

        util.kvmap(bufs[bufidx].names, function(k, _)
            local access = bufs[bufidx].access[k]
            if not access then return end

            if access == "!" then
                irccops = irccops + 1
            elseif access == "~" then
                founders = founders + 1
            elseif access == "@" then
                operators = operators + 1
            elseif access == "&" then
                halfwits = halfwits + 1
            elseif access == "+" then
                loudmouths = loudmouths + 1
            elseif access == "" then
                peasants = peasants + 1
            end

            total = total + 1
        end)

        local txt = ""
        if irccops    > 0 then txt = format("%s%s irccops, ",    txt, irccops)    end
        if founders   > 0 then txt = format("%s%s founders, ",   txt, founders)   end
        if operators  > 0 then txt = format("%s%s operators, ",  txt, operators)  end
        if halfwits   > 0 then txt = format("%s%s halfwits, ",   txt, halfwits)   end
        if loudmouths > 0 then txt = format("%s%s loudmouths, ", txt, loudmouths) end
        if peasants   > 0 then txt = format("%s%s peasants, ",   txt, peasants)   end
        txt = txt:sub(1, #txt - 2) -- trim comma
        txt = format("%s denizens of %s (%s)", total, hcol(dest), txt)

        prin_irc(0, dest, "NAMES", "%s", txt)
    end,

    -- MOTD message
    ["372"] = default,

    -- Beginning of MOTD
    ["375"] = default,

    -- End of MOTD
    ["376"] = function(_, _, _, _)
        for c = 1, #config.join do
            send(":%s JOIN %s", nick, config.join[c])
        end
    end,

    -- WHOIS: <nick> is connecting from <host>
    ["378"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] %s", hcol(e.fields[3]), e.msg)
    end,

    -- WHOIS: <nick> is using modes +abcd
    ["379"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] %s", hcol(e.fields[3]), e.msg)
    end,

    -- "xyz" is now your hidden host (set by foo)
    ["396"] = function(e) prin_irc(0, MAINBUF, "--", "%s %s", e.fields[3], e.msg) end,

    -- No such nick/channel
    ["401"] = function(e) prin_irc(0, MAINBUF, L_ERR, "No such nick/channel %s", e.fields[3]) end,

    -- Nickname is already in use
    ["433"] = function(e)
        assert(e.fields[3] == nick)
        local newnick = e.fields[3] .. "_" -- sprout a tail
        prin_irc(2, MAINBUF, L_ERR, "Nickname %s already in use; using %s",
            e.fields[3], newnick)
        send("NICK %s", newnick)
        nick = newnick
    end,

    -- <nick> is already in channel (response to /invite)
    ["443"] = function(e)
        prin_irc(0, e.fields[4], L_ERR, "%s is already in %s", hcol(e.fields[3]),
            e.fields[4])
    end,

    -- cannot join channel (you are banned)
    ["474"] = function(e)
        prin_irc(2, e.fields[3], L_ERR, "you're banned creep")
        local buf = buf_idx(e.fields[3])
        if buf then buf_switch(buf) end
    end,

    -- WHOIS: <nick> is using a secure connection (response to /whois)
    ["671"] = function(e)
        prin_irc(0, buf_cur(), "WHOIS", "[%s] uses a secure connection", hcol(e.fields[3]))
    end,

    -- You are now logged in as xyz
    ["900"] = function(e) prin_irc(0, MAINBUF, "--", "%s", e.msg) end,

    -- CTCP stuff.
    ["CTCP_ACTION"] = function(e)
        local sender_fmt = hcol(e.nick or nick)
        local prio = 1

        if msg_pings(e.nick or nick, e.msg) then
            prio = 2
            sender_fmt = format("\x16%s\x0f", sender_fmt)
        end

        if not config.mirc then
            e.msg = mirc.remove(e.msg)
        end

        prin_irc(prio, e.dest, "*", "%s %s", sender_fmt, e.msg)
    end,
    ["CTCP_VERSION"] = function(e)
        if config.ctcp_version then
            prin_irc(1, MAINBUF, "CTCP", "%s requested VERSION (reply: %s)", e.nick, config.ctcp_version)
            send("NOTICE %s :\1VERSION %s\1", e.nick, config.ctcp_version)
        end
    end,
    ["CTCP_SOURCE"] = function(e)
        if config.ctcp_source then
            prin_irc(1, MAINBUF, "CTCP", "%s requested SOURCE (reply: %s)", e.nick, config.ctcp_source)
            send("NOTICE %s :\1SOURCE %s\1", e.nick, config.ctcp_source)
        end
    end,
    ["CTCP_PING"] = function(e)
        if config.ctcp_ping then
            prin_irc(1, MAINBUF, "CTCP", "PING from %s", e.nick)
            send("NOTICE %s :%s", e.nick, e.fields[2])
        end
    end,

    -- IRCv3 capability negotiation
    ["CAP"] = function(e)
        local subcmd = (e.fields[3]):lower()
        if subcmd == "ls" then
            -- list of all capabilities supported by the server.
            server.caps = {}
            for cap in (e.msg):gmatch("([^%s]+)%s?") do
                server.caps[cap] = false
            end
        elseif subcmd == "ack" then
            -- the server has a capability we requested.
            server.caps[e.msg] = true
            prin_irc(0, MAINBUF, "--", "Enabling IRCv3 capability: %s", e.msg)
        elseif subcmd == "nak" then
            -- the server does not have a capability we requested.
            --
            -- since all caps are set to false/nil by default we don't really
            -- need to do this...
            server.caps[e.msg] = false

            prin_irc(0, MAINBUF, "--", "Disabling IRCv3 capability: %s", e.msg)
        end
    end,
}

CFGHND_CONTINUE = 0
CFGHND_RETURN   = 1

function parseirc(reply)
    local event = irc.parse(reply)
    if not event then return end

    last_ircevent = event

    -- The first element in the fields array points to
    -- the type of message we're dealing with.
    local cmd = event.fields[1]

    -- When recieving MOTD messages and similar stuff from
    -- the IRCd, send it to the main tab
    if cmd:find("00.") or cmd:find("2[56].") or cmd:find("37.") then
        event.dest = MAINBUF
    end

    -- When recieving PMs, send it to the buffer named after
    -- the sender
    if event.dest == nick then event.dest = event.nick end

    local cfghnd = config.handlers[cmd]
    if cfghnd then
        if cfghnd(event) == CFGHND_RETURN then
            return
        end
    end

    if not irchand[cmd] then
        local text = "(" .. event.fields[1] .. ")"
        for i = 2, #event.fields do
            text = text .. " " .. event.fields[i]
        end
        if event.msg and event.msg ~= "" then
            text = text .. " :" .. event.msg
        end

        prin_irc(0, MAINBUF, "><", "%s", text)
    else
        (irchand[cmd])(event)
    end
end

function send_both(fmt, ...)
    -- this is a simple function to send the input to the
    -- terminal and to the server at the same time.
    send(fmt, ...)

    -- don't send to the terminal if echo-message is enabled.
    if not server.caps["echo-message"] then
        parseirc(format(fmt, ...))
    end
end

cmdhand = {
    ["/close"] = {
        REQUIRE_CHANBUF_OR_ARG = true,
        help = { "Close a buffer. The buffers after the one being closed are shifted left." },
        usage = "[buffer]",
        fn = function(a, _, _)
            local buf = a or cbuf
            if not tonumber(buf) then
                if not buf_idx(buf) then
                    prin_cmd(buf_cur(), L_ERR, "%s is not an open buffer.", a)
                    return
                else
                    buf = buf_idx(buf)
                end
            else
                buf = tonumber(buf)
            end

            if buf == 1 then
                prin_cmd(buf_cur(), L_ERR, "Cannot close main buffer.")
                return
            end

            bufs = util.remove(bufs, buf)
            while not bufs[cbuf] do
                cbuf = cbuf - 1
            end

            -- redraw, as the current buffer may have changed,
            -- and the statusbar needs to be redrawn anyway.
            tui.redraw(tbrl.bufin, tbrl.cursor)
        end,
    },
    ["/up"] = {
        help = {},
        fn = function(_, _, _)
            local scr = math.floor(tui.tty_height / 3)
            bufs[cbuf].scroll = bufs[cbuf].scroll + scr
            tui.redraw(tbrl.bufin[tbrl.hist], tbrl.cursor)
        end
    },
    ["/down"] = {
        help = {},
        fn = function(_, _, _)
            local scr = math.floor(tui.tty_height / 3)
            bufs[cbuf].scroll = bufs[cbuf].scroll - scr
            if bufs[cbuf].scroll < 0 then bufs[cbuf].scroll = 0 end
            tui.redraw(tbrl.bufin[tbrl.hist], tbrl.cursor)
        end
    },
    ["/clear"] = {
        help = { "Clear the current buffer." },
        fn = function(_, _, _)
            bufs[cbuf].history = {}
            bufs[cbuf].scroll = 0
            tui.redraw(tbrl.bufin, tbrl.cursor)
        end
    },
    ["/redraw"] = {
        help = { "Redraw the screen. Ctrl+L may also be used." },
        fn = function(_, _, _) tui.redraw(tbrl.bufin[tbrl.hist], tbrl.cursor) end,
    },
    ["/next"] = {
        help = { "Switch to the next buffer. Ctrl+N may also be used." },
        fn = function(_, _, _) buf_switch(cbuf + 1) end
    },
    ["/prev"] = {
        help = { "Switch to the previous buffer. Ctrl+P may also be used." },
        fn = function(_, _, _) buf_switch(cbuf - 1) end
    },
    ["/invite"] = {
        REQUIRE_CHANBUF = true,
        REQUIRE_ARG = true,
        help = { "Invite a user to the current channel." },
        usage = "<user>",
        fn = function(a, _, _)
            send(":%s INVITE %s :%s", nick, a, buf_cur())
        end
    },
    ["/names"] = {
        REQUIRE_CHANBUF_OR_ARG = true,
        help = { "See the users for a channel (the current one by default)." },
        usage = "[channel]",
        fn = function(a, _, _) send("NAMES %s", a or buf_cur()) end
    },
    ["/topic"] = {
        -- TODO: separate settopic command
        REQUIRE_CHANBUF_OR_ARG = true,
        help = { "See the current topic for a channel (the current one by default)." },
        usage = "[channel]",
        fn = function(a, _, _) send("TOPIC %s", a or buf_cur()) end
    },
    ["/whois"] = {
        REQUIRE_ARG = true,
        help = { "See WHOIS information for a user." },
        usage = "<user>",
        fn = function(a, _, _) send("WHOIS %s", a) end
    },
    ["/join"] = {
        REQUIRE_ARG = true,
        help = { "Join a channel; if already joined, focus that buffer." },
        usage = "[channel]",
        fn = function(a, _, _)
            send(":%s JOIN %s", nick, a)

            local bufidx = buf_idx_or_add(a)

            -- draw the new buffer
            tui.statusbar()
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
            send(":%s PART %s :%s", nick, buf_cur(), msg)
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

            send("QUIT :%s", msg)
            lurch.cleanup()
            eprintf("[lurch exited]\n")
            os.exit(0)
        end
    },
    ["/nick"] = {
        REQUIRE_ARG = true,
        help = { "Change nickname." },
        usage = "<nickname>",
        fn = function(a, _, _) send("NICK %s", a); nick = a; end
    },
    ["/msg"] = {
        REQUIRE_ARG = true,
        help = { "Privately message a user. Opens a new buffer." },
        usage = "<user> <message...>",
        fn = function(a, args, _)
            send_both(":%s PRIVMSG %s :%s", nick, a, args or "")
        end
    },
    ["/note"] = {
        REQUIRE_ARG = true,
        help = { "Send a NOTICE to a channel." },
        usage = "<user> <message...>",
        fn = function(a, args, _)
            send_both(":%s NOTICE %s :%s", nick, a, args or "")
        end,
    },
    ["/raw"] = {
        REQUIRE_ARG = true,
        help = { "Send a raw IRC command to the server." },
        usage = "<command> <args>",
        fn = function(a, args, _) send("%s %s", a, args) end
    },
    ["/me"] = {
        REQUIRE_ARG = true,
        REQUIRE_CHAN_OR_USERBUF = true,
        help = { "Send a CTCP action to the current channel." },
        usage = "<text>",
        fn = function(a, args, _)
            send_both(":%s PRIVMSG %s :\1ACTION %s %s\1", nick,
                buf_cur(), a, args)
        end,
    },
    ["/shrug"] = {
        REQUIRE_CHAN_OR_USERBUF = true,
        help = { "Send a shrug to the current channel." },
        fn = function(_, _, _)
            send_both(":%s PRIVMSG %s :¯\\_(ツ)_/¯", nick, buf_cur())
        end,
    },
    ["/help"] = {
        help = { "You know what this command is for." },
        usage = "[command]",
        fn = function(a, _, _)
            if not a or a == "" then
                -- all set up and ready to go !!!
                prin_cmd(buf_cur(), "--", "hello bastard !!!")
                return
            end

            local cmd = a
            if not (cmd:find("/") == 1) then cmd = "/" .. cmd end

            if not cmdhand[cmd] then
                prin_cmd(buf_cur(), L_ERR, "No such command '%s'", a)
                return
            end

            local cmdinfo = cmdhand[cmd]
            prin_cmd(buf_cur(), "--", "")
            prin_cmd(buf_cur(), "--", "Help for %s", cmd)

            if cmdinfo.usage then
                prin_cmd(buf_cur(), "--", "usage: %s %s", cmd, cmdinfo.usage)
            end

            prin_cmd(buf_cur(), "--", "")

            for i = 1, #cmdinfo.help do
                prin_cmd(buf_cur(), "--", "%s", cmdinfo.help[i])
                prin_cmd(buf_cur(), "--", "")
            end

            if cmdinfo.REQUIRE_CHANBUF then
                prin_cmd(buf_cur(), "--", "This command must be run in a channel buffer.")
                prin_cmd(buf_cur(), "--", "")
            elseif cmdinfo.REQUIRE_CHAN_OR_USERBUF then
                prin_cmd(buf_cur(), "--", "This command must be run in a channel or a user buffer.")
                prin_cmd(buf_cur(), "--", "")
            end
        end,
    },
    ["/list"] = {
        -- TODO: list user-defined commands.
        help = { "List builtin and user-defined lurch commands." },
        fn = function(_, _, _)
            prin_cmd(buf_cur(), "--", "")
            prin_cmd(buf_cur(), "--", "[builtin]")

            local cmdlist = ""
            for k, _ in pairs(cmdhand) do
                cmdlist = cmdlist .. k .. " "
            end

            prin_cmd(buf_cur(), "--", "%s", cmdlist)
        end,
    },
    ["/dump"] = {
        help = { "Dump lurch's state and internal variables into a temporary file to aid with debugging." },
        usage = "[file]",
        fn = function(a, _, _)
            local file = a
            if not file then file = os.tmpname() end

            local fp, err = io.open(file, "w")
            if not fp then
                prin_cmd(buf_cur(), L_ERR, "Couldn't open tmpfile %s", err)
                return
            end

            local state = {
                server = server,
                nick = nick, cbuf = cbuf,
                bufs = bufs,

                input_buf = tbrl.bufin,
                input_cursor = tbrl.cursor,
                input_hist = tbrl.hist,

                set_colors = tui.set_colors,
                colors = tui.colors,
            }

            local ret, err = fp:write(inspect(state))
            if not ret then
                prin_cmd(buf_cur(), L_ERR, "Could not open tmpfile: %s", err)
                return
            end

            prin_cmd(buf_cur(), L_ERR, "Wrote information to %s", file)
            fp:close()
        end,
    },
    ["/panic"] = {
        help = { "Summon a Lua panic to aid with debugging." },
        usage = "[errmsg]",
        fn = function(a, args, _)
            local msg = "/panic was run"
            if a then msg = format("%s %s", a, args or "") end
            error(msg)
        end,
    },
}

function parsecmd(inp)
    -- the input line clears itself, there's no need to clear it...

    -- split the input line into the command (first word), a (second
    -- word), and args (the rest of the input)
    local _cmd, a, args = inp:gmatch("([^%s]+)%s?([^%s]*)%s?(.*)")()
    if not _cmd then return end
    if a == "" then a = nil; args = nil end

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
    if _cmd:sub(1, 1) == "/" and _cmd:sub(2, 2) ~= "/" then
        if not cmdhand[_cmd] and not config.commands[_cmd] then
            prin_cmd(buf_cur(), "NOTE", "%s not implemented yet", _cmd)
            return
        end

        local hand = cmdhand[_cmd] or config.commands[_cmd]

        if hand.REQUIRE_CHANBUF and not (buf_cur()):find("#") then
            prin_cmd(buf_cur(), L_ERR,
                "%s must be executed in a channel buffer.", _cmd)
            return
        end

        if hand.REQUIRE_ARG and (not a or a == "") then
            prin_cmd(buf_cur(), L_ERR, "%s requires an argument.", _cmd)
            return
        end

        if hand.REQUIRE_CHANBUF_OR_ARG and (not a or a == "") and not (buf_cur()):find("#") then
            prin_cmd(buf_cur(), L_ERR,
                "%s must be executed in a channel buffer or must be run with an argument.", _cmd)
            return
        end

        if hand.REQUIRE_CHAN_OR_USERBUF and cbuf == 1 then
            prin_cmd(buf_cur(), L_ERR,
                "%s must be executed in a channel or user buffer.", _cmd)
        end

        (hand.fn)(a, args, inp)
    else
        -- make "//test" translate to "/test"
        if inp:sub(1, 2) == "//" then inp = inp:sub(2, #inp) end

        -- since the command doesn't exist, just send it as a message
        if buf_cur() == MAINBUF then
            prin_cmd(buf_cur(), L_ERR, "Stop trying to talk to lurch.")
        else
            -- split long messages, as servers don't like IRC messages
            -- that are longer than about 512 characters (but that limit
            -- includes the trailing \r\n, the "PRIVMSG <channel>" bit,
            -- and the sender, so split by 256 chars just to stay safe).
            for line in (util.fold(inp, 256)):gmatch("([^\n]+)\n?") do
                send_both(":%s PRIVMSG %s :%s", nick, buf_cur(), line)
            end
        end
    end
end

local keyseq_cmd_handler = {
    [tb.TB_KEY_CTRL_N] = "/next",
    [tb.TB_KEY_CTRL_P] = "/prev",
    [tb.TB_KEY_PGUP]   = "/up",
    [tb.TB_KEY_PGDN]   = "/down",
    [tb.TB_KEY_CTRL_L] = "/redraw",
    [tb.TB_KEY_CTRL_C] = "/quit",
}

local keyseq_func_handler = {
    [tb.TB_KEY_CTRL_B] = function() tbrl.insert_at_curs(mirc.BOLD) end,
    [tb.TB_KEY_CTRL_U] = function() tbrl.insert_at_curs(mirc.UNDERLINE) end,
    [tb.TB_KEY_CTRL_T] = function() tbrl.insert_at_curs(mirc.ITALIC) end,
    [tb.TB_KEY_CTRL_R] = function() tbrl.insert_at_curs(mirc.INVERT) end,
    [tb.TB_KEY_CTRL_O] = function() tbrl.insert_at_curs(mirc.RESET) end,
}

function rt.on_keyseq(key)
    if keyseq_func_handler[key] then
        (keyseq_func_handler[key])()
    elseif keyseq_cmd_handler[key] then
        parsecmd(keyseq_cmd_handler[key])
    end
end

function rt.init(args)
    tui.refresh()

    if tui.tty_width < 40 or tui.tty_height < 8 then
        panic("screen width too small (min 40x8)\n")
    end

    --
    -- for each option, if it begins with a "-", toggle
    -- the corresponding configuration value if it has no
    -- argument. If it does have an argument, set the
    -- configuration value to the argument.
    --
    -- For example: the following argument string:
    --    ./lurch -host irc.snoonet.org -port 6666 -mirc
    -- Will set config.host to irc.snoonet.org, config.port
    -- to 6666, and will toggle config.mirc.
    --
    local lastarg
    for i, arg in ipairs(args) do
        if arg:sub(1, 1) == "-" then
            arg = arg:sub(2, #arg)
            config[arg] = not config[arg]
            lastarg = arg
        elseif lastarg then
            config[lastarg] = arg
            lastarg = nil
        end
    end

    local _nick = config.nick or os.getenv("IRCNICK") or os.getenv("USER")
    local user  = config.user or os.getenv("IRCUSER") or os.getenv("USER")
    local name  = config.name or _nick

    local r, e = irc.connect(config.host, config.port, config.tls,
        _nick, user, name, config.pass, config.caps)
    if not r then panic("error: %s\n", e) end

    tui.load_highlight_colors()

    -- create the main buffer, switch to it, and set its color to plain
    -- white.
    tui.set_colors[MAINBUF] = 14
    buf_add(MAINBUF)
    buf_switch(1)
    callbacks.print_banner("beta")

    tbrl.bindings[tb.TB_KEY_CTRL_N] = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_CTRL_P] = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_PGUP]   = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_PGDN]   = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_CTRL_L] = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_CTRL_C] = rt.on_keyseq

    tbrl.bindings[tb.TB_KEY_CTRL_B] = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_CTRL_U] = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_CTRL_T] = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_CTRL_R] = rt.on_keyseq
    tbrl.bindings[tb.TB_KEY_CTRL_O] = rt.on_keyseq

    tbrl.enter_callback = parsecmd
    tbrl.resize_callback = function()
        tui.redraw(tbrl.bufin[tbrl.hist], tbrl.cursor)
    end
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
    [28] = function()
        tui.redraw(bufs, cbuf, nick, tbrl.bufin, tbrl.cursor)
    end,
    -- catch-all
    [0] = function() return true end,
}

function rt.on_disconnect(err)
    if not err then err = "server closed connection" end
    panic("disconnected: %s\n", err)
end

function rt.on_signal(sig)
    local quitmsg = config.quit_msg or "*poof*"
    local handler = sighand[sig] or sighand[0]
    if (handler)() then
        send("QUIT :%s", quitmsg)
        lurch.cleanup()
        eprintf("[lurch exited]\n")
        os.exit(0)
    end
end

function rt.on_lerror(_)
    send("QUIT :%s", "*poof*")
    lurch.cleanup()
end

function rt.on_timeout()
    panic("fatal timeout\n");
end

function rt.on_reply(reply)
    if os.getenv("LURCH_DEBUG") then
        util.append(DBGFILE, format("<< %s\n", reply))
    end

    parseirc(reply)
end

-- every time a key is pressed, redraw the prompt, and
-- write the input buffer.
function rt.on_input(event)
    tbrl.on_event(event)
    tui.prompt(tbrl.bufin[tbrl.hist], tbrl.cursor)
end

function rt.on_complete(text, from, to)
    local incomplete = text:sub(from, to)
    local matches = {}

    -- Possible matches:
    --     for start of line: "/<command>", "/#<channel>", "nick: "
    --     for middle of line: "nick "
    local possible = { nick }
    if from == 1 then
        for k, _ in pairs(cmdhand) do possible[#possible + 1] = k end
        for _, v in ipairs(bufs) do
            if (v.name):find("#") == 1 then
                possible[#possible + 1] = format("/%s", v.name)
            end
        end

        for k, _ in pairs(bufs[cbuf].names) do
            possible[#possible + 1] = format("%s:", k)
        end
    else
        for k, _ in pairs(bufs[cbuf].names) do
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
