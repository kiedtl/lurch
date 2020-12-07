local tty = require('tty')
local M = {}

M.tty_height = 80
M.tty_width  = 24

function M.clean()
	tty.line_wrap()
	tty.clear()
	tty.reset_scroll_area()
	tty.main_buffer()
	tty.curs_show()
	io.flush(1)
end

function M.refresh()
	M.tty_height, M.tty_width = tty.dimensions()

	assert(M.tty_height)
	assert(M.tty_width)

	tty.alt_buffer()
	tty.no_line_wrap()
	tty.clear()
	tty.set_scroll_area(M.tty_height - 1)
	tty.curs_move_to_line(999)
end

return M
