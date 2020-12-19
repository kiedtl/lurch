local mirc   = require('mirc')
local format = string.format
local M = {}

M.tls  = true
M.host = "irc.tilde.chat"
M.port = 6697

M.nick = "inebriate|lurch"

-- server password. This is distinct from SASL or Nickserv IDENTIFY.
M.pass = nil

-- If this is nil, it defaults to M.nick
M.user = nil

-- your "real name". if nil, defaults to the nickname.
M.name = "o hai"

-- channels to join by on startup.
M.join = { "#chaos" }

-- default quit/part message. default to ""
M.quit_msg = "*thud*"
M.part_msg = "*confused shouting*"

-- set these to nil to not respond to CTCP messages.
M.ctcp_version = "lurch (beta)"
M.ctcp_source  = "https://github.com/lptstr/lurch"
M.ctcp_ping    = true

-- if set to false, will simply filter out mirc colors.
M.mirc = true

M.time_col_width = 5
M.right_col_width = nil -- defaults to $(terminal_width - left_col_width - time_col_width)
M.left_col_width = 12

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
