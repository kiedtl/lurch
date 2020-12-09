local M = {}

M.server = "localhost"
M.port = 6667

M.nick = "inebriate|lurch"

-- server password. This is distinct from SASL or Nickserv IDENTIFY.
M.server_password = nil

-- If this is nil, it defaults to M.nick
M.user = nil

-- your "real name". if nil, defaults to the nickname.
M.name = "hii im drunk"

-- channels to join by on startup.
M.channels = { "#chaos" }

-- default quit/part message. default to ""
M.quit_msg = "*thud*"
M.part_msg = "*confused shouting*"

-- set these to nil to not respond to CTCP messages.
M.ctcp_version = "lurch (beta)"
M.ctcp_source  = "https://github.com/lptstr/lurch"
M.ctcp_ping    = true

-- if set to false, will simply filter out mirc colors.
M.show_mirc_colors = true

M.time_col_width = 5
M.right_col_width = nil -- defaults to $(terminal_width - left_col_width - time_col_width)
M.left_col_width = 10

-- words that will generate a notification if they appear in a message
M.pingwords = { "kiedtl" }

-- user defined commands. These take the place of aliases.
M.commands = { }

-- what timezone to display times in. (format: "UTC[+-]<offset>")
M.timezone = "UTC-3:00"

-- Attempt to prevent the ident from being received.
-- This is done by delaying the registration of the user after connecting to the
-- IRC server for a few seconds; by then, some servers will have their identd
-- requests time out.
M.no_ident = false

return M
