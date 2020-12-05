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
M.channels = { }

-- default quit/part message. default to ""
M.quit_msg = "*thud*"
M.part_msg = "*confused shouting*"

-- set these to nil to not respond to CTCP messages.
M.ctcp_version = "lurch (beta)"
M.ctcp_source  = "https://github.com/lptstr/lurch"
M.ctcp_ping    = true

-- if set to false, will simply filter out mirc colors.
M.show_mirc_colors = true

M.left_col_width = 10
M.right_col_width = nil -- defaults to $(terminal_width - left_col_width)

return M
