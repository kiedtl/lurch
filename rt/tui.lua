local util   = require('util')
local tty    = require('tty')
local format = string.format

local M = {}

M.set_colors = {}
M.colors     = {}
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

function M.load_highlight_colors()
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

		M.colors[#M.colors + 1] = {}
		M.colors[#M.colors].r = tonumber(r, 16)
		M.colors[#M.colors].g = tonumber(g, 16)
		M.colors[#M.colors].b = tonumber(b, 16)
	end
end

function M.highlight(text, text_as, no_bold)
	assert(text)
	if not text_as then text_as = text end

	-- store nickname highlight color, so that we don't have to
	-- calculate the text's hash each time
	if not M.set_colors[text_as] then
		-- add one to the hash value, as the hash value may be 0
		M.set_colors[text_as] = util.hash(text_as, #M.colors - 1)
		M.set_colors[text_as] = M.set_colors[text_as] + 1
	end

	local color = M.colors[M.set_colors[text_as]]
	local esc = "\x1b[1m"
	if no_bold then esc = "" end

	-- if no color could be found, just use the default of black
	if color then
		esc = esc .. format("\x1b[38;2;%s;%s;%sm", color.r, color.g, color.b)
	end

	return format("%s%s\x1b[m", esc, text)
end

return M
