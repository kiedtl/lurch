local util = require('util')
local printf = util.printf

local tty = {}

function tty.height()
	local tput = util.capture("tput lines")
	return tonumber(tput:trim_newline(), 10)
end

function tty.width()
	local tput = util.capture("tput cols")
	return tonumber(tput:trim_newline(), 10)
end

-- switch to alternate buffer and back
function tty.main_buffer()
	printf("\x1b[?1049l")
end
function tty.alt_buffer()
	printf("\x1b[?1049h")
end

-- enable/disable line wrapping
function tty.line_wrap()
	printf("\x1b[?7h")
end
function tty.no_line_wrap()
	printf("\x1b[?7l")
end

-- clear the screen
function tty.clear()
	printf("\x1b[2J")
end

-- clear from the cursor to the end of the current line
function tty.clear_line()
	printf("\r\x1b[K")
end

-- set scroll area
function tty.reset_scroll_area()
	printf("\x1b[;r")
end
function tty.set_scroll_area(area)
	printf("\x1b[3;%sr", area)
end

-- save or restore cursor position
function tty.curs_save()
	printf("\x1b7")
end
function tty.curs_restore()
	printf("\x1b8")
end

-- move cursor to X line
-- TODO: is this accurate?
function tty.curs_move_to_line(line)
	if line then
		printf("\x1b[%sH", line)
	else
		-- move cursor to line 0,0
		printf("\x1b[H")
	end
end

function tty.curs_show()
	printf("\x1b[?25h")
end

function tty.curs_hide()
	printf("\x1b[?25l")
end

function tty.curs_up(n)
	printf("\x1b[%sA", n or 1)
end

function tty.curs_down(n)
	printf("\x1b[%sB", n or 1)
end

return tty
