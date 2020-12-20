local mirc   = require('mirc')
local util   = require('util')
local format = string.format
local M = {}

-- Maximum number of times to try and reconnect to the server if
-- disconnected for any reason. Set to -1 for infinite reconnect.
--
-- NOTE: beware of this feature if you were K-lined for any reason;
-- lurch *might* try to reconnect even in those scenarios (though
-- this hasn't been confirmed, as the author of lurch has never
-- been K-lined before).
M.reconn = 4

M.tls  = true
M.host = "irc.tilde.chat"
M.port = 6697

M.nick = "inebriate|lurch"

-- Command that will give the server password as its output. The actual
-- password should not be stored here for obvious reasons.
--
-- This is distinct from the password used with SASL or Nickserv IDENTIFY,
-- but some IRC servers will accept passwords from here as if a NickServ
-- IDENTIFY command was run anyway.
--
-- By default, the command is 'pass show irc', which runs pash [0] and
-- shows the password entry 'irc'. This command can be substituted for the
-- equivalent pass command (or whatever your password manager is).
--
-- [0]: https://github.com/dylanaraps/pash
M.pass = "pash show irc"

-- If this is nil, it defaults to M.nick
M.user = nil

-- your "real name". if nil, defaults to the nickname.
M.name = "o hai"

-- channels to join by on startup.
M.join = { "#chaos" }

-- Mode to set when connected.
M.mode = "+i"

-- default quit/part message. default to ""
M.quit_msg = "*thud*"
M.part_msg = "*confused shouting*"

-- set these to nil to not respond to CTCP messages.
M.ctcp_version = "lurch (beta)"
M.ctcp_source  = "https://github.com/lptstr/lurch"
M.ctcp_ping    = true

-- if set to false, will simply filter out mirc colors.
M.mirc = true

-- Maximum widths for the various columns.
--
-- Columns:
--    time:  the column in which the time is shown.
--    left:  the column in which the nicknames, "NOTE", etc are shown.
--    right: the "main" column in which messages are shown.
--
-- By default, the right column width defaults to:
--    $(terminal_width - left_column_width - time_column_width)
--
-- If the width of a column exceeds the maximum width for that column,
-- it will either be folded to the correct width (for the right column),
-- trimmed (for the left column in case of channel messages), or displayed
-- as-is (for the time column, and for the left column).
--
M.time_col_width = 5
M.right_col_width = nil
M.left_col_width = 12

-- This function is used to provide the terminal colors that lurch
-- will use to highlight nicknames and channels. By default, it gets
-- these colors from conf/colors.
M.colors = function()
    -- read a list of newline-separated colors from conf/colors.
    -- the colors are terminal 256-bit colors. e.g. 3, 65, 245, &c
    local data = util.read(__LURCH_EXEDIR .. "/conf/colors")

    local colors = {}
    for line in data:gmatch("([^\n]+)\n?") do
        colors[#colors + 1] = tonumber(line)
    end

    return colors
end

-- Time/date format. This is shown to the left of every message. See
-- the documentation for os.date() for info on the various format sequences.
--
-- When changing this, be sure to update config.time_col_width as appropriate.
-- To disable time altogether, set this to an empty string and set the
-- config.time_col_width variable to 0.
M.timefmt = "%H:%M"

--
-- Function used to format each line.
--
-- time_pad: number of spaces used to pad the time column.
-- left_pad: same as time_pad, but for the left column.
-- time:     the time string, formatted with config.timefmt.
-- left:     the contents of the left column.
-- right:    the contents of the right column, already folded.
--
M.linefmt = function(time_pad, left_pad, time, left, right)
    time_pad = (" "):rep(time_pad)
    left_pad = (" "):rep(left_pad)

    -- \x0f\x0314%s\x0f: set the color to grey, print the time, and reset
    --      the color.
    -- %s %s%s %s: print the left padding, the left column, and the right
    --      column.
    return format("\x0f\x0314%s\x0f%s %s%s %s", time, time_pad,
        left_pad, left, right)

    -- Uncommenting this will cause the left column to be aligned to the left
    -- instead of to the right.
    --return format("\x0f\x0314%s\x0f%s %s%s %s", time, time_pad,
        --left, left_pad, right)
end

-- words that will generate a notification if they appear in a message
M.pingwords = { "kiedtl" }

-- user-defined commands. These take the place of aliases; the alias_to()
-- function below is a convenience function that can be used to quickly
-- alias commands.
local alias_to = function(text)
    return {
        help = { "" },
        fn = function(a, args, _)
            parsecmd(text .. (a or "") .. (args or ""))
        end,
    }
end

M.commands = {
    ["/shr"] = alias_to("/shrug"),
    ["/j"] = alias_to("/join"),
    ["/p"] = alias_to("/part"),
    ["/l"] = alias_to("/leave"),
}

-- user-defined handlers for IRC commands (not to be confused with lurch's
-- commands); usage of this feature requires knowledge of the IRC protocol
-- and all its quirks.
--
-- If the handler returns CFGHND_CONTINUE or nil, the normal handler will
-- be run; if it returns CFGHND_RETURN, then the default handler will not
-- be executed.
--
-- These handlers can be disabled by setting
-- config.handlers[<CMD>][<NAME>].disabled = true, or by using the /disable
-- command (e.g. /disable PRIVMSG quotes).
--
-- This can be used to implement triggers, as in Weechat.
M.handlers = {
    ["PRIVMSG"] = {
        -- if the message is a quote, display it in light yellow.
        ["quotes"] = {
            fn = function(e)
                if (e.msg):match("^>") then
                    e.msg = mirc.COLOR .. "08" .. e.msg .. mirc.RESET
                end

                return CFGHND_CONTINUE
            end
        },
    },
}

-- what timezone to display times in. (format: "UTC[+-]<offset>")
M.tz = "UTC-3:00"

-- Attempt to prevent the ident from being received.
-- This is done by delaying the registration of the user after connecting to the
-- IRC server for a few seconds; by then, some servers will have their identd
-- requests time out. Note that only a few IRCd's are susceptible to this.
M.no_ident = false

-- List of IRCv3 capabilities to enable.
--
-- Supported capabilities:
--   * server-time: enables adding the "time" IRCv3 tag to messages, thus
--        allowing us to accurately determine when a message was sent.
--   * away-notify: allows the server to notify us when a user changes their
--        away status
--   * account-notify: allows the server to notify us when a user logs in
--        or logs out of their NickServ account
--   * echo-message: normally, when the user sends a message, the server
--        does not let us know if the message was recieved or not. with this
--        enabled, the server will "echo" our messages back to us.
--
-- Note that these capabilities will only be enabled if the server
-- supports it.
--
M.caps = { "server-time", "away-notify", "account-notify", "echo-message" }

return M
