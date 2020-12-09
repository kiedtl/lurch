local config  = require('config')
local inspect = require('inspect')
local util    = require('util')
local tty     = require('tty')
local format  = string.format
local printf  = util.printf

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
	assert(type(text) == "string",
		format("text of type %s, not string", type(text)))
	if not text_as then text_as = text end
	assert(type(text_as) == "string",
		format("text_as of type %s, not string", type(text_as)))

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

function M.inputbar(bufs, cbuf, nick)
	tty.curs_down(999)

	-- if we've scrolled up, don't draw the input.
	if bufs[cbuf].scroll ~= #bufs[cbuf].history then
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
	if inp:find("/me ") == 1 and cursor >= 4 then
		prompt = format("* %s ", M.highlight(nick))
		inp = inp:sub(5, #inp)
		cursor = cursor - 4
	elseif inp:find("/") == 1 then
		prompt = "\x1b[90m/\x1b[m"
		inp = inp:sub(2, #inp)
		cursor = cursor - 1
	else
		prompt = format("<%s> ", M.highlight(nick))
	end
	local rawprompt = prompt:gsub("\x1b%[.-m", "")

	-- strip off stuff from input that can't be shown on the
	-- screen
	inp = inp:sub(-(M.tty_width - #rawprompt))

	-- draw the input buffer and move the cursor to the appropriate
	-- position.
	tty.clear_line()
	printf("%s%s", prompt, inp)

	local curs_pos = cursor + #rawprompt
	if curs_pos > 0 then
		printf("\r\x1b[%sC", curs_pos)
	else
		printf("\r")
	end
end

function M.statusbar(bufs, cbuf)
	assert(type(cbuf) == "number",
		format("cbuf of type %s, not number", type(cbuf)))
	assert(type(bufs) == "table",
		format("bufs of type %s, not table", type(bufs)))

	local chanlist = ""
	for buf = 1, #bufs do
		local ch = bufs[buf].name
		local bold = false

		if buf == cbuf then
			local pnch

			if bufs[buf].pings  > 0 then bold = true end
			if bufs[buf].unread > 0 then
				pnch = M.highlight(format(" %d %s %s%d ", buf, ch,
					"+", bufs[buf].unread), ch, not bold)
			else
				pnch = M.highlight(format(" %d %s ", buf, ch), ch, true)
			end

			chanlist = chanlist .. "\x1b[7m" .. pnch .. "\x1b[m "
		else
			if bufs[buf].pings  > 0 then bold = true end
			if bufs[buf].unread > 0 then
				local nch = M.highlight(format(" %d %s %s%d ", buf, ch,
					"+", bufs[buf].unread), ch, not bold)
				chanlist = chanlist .. nch .. " "
			end
		end
	end

	tty.curs_save()
	tty.curs_move_to_line(0)

	tty.clear_line()
	printf("%s\x1b[m", chanlist)

	tty.curs_restore()

	-- set the terminal title. This is a big help when using terminal
	-- tabs to mimic a multi-server feature.
	tty.title("[%s] %s", config.server, bufs[cbuf].name)
end

function M.redraw(bufs, cbuf, nick)
	M.refresh()

	tty.curs_save()
	tty.curs_hide()

	-- keep one blank line in between statusbar and text.
	tty.curs_move_to_line(3)

	-- beginning at the top of the terminal, draw each line
	-- of text from that buffer's history, then move down.
	-- If there is nothing to draw, just clear the line and
	-- move on.
	if bufs[cbuf].history then
		local start = bufs[cbuf].scroll - (M.tty_height-4)
		for i = start, bufs[cbuf].scroll do
			tty.clear_line()

			local msg = bufs[cbuf].history[i]
			if msg then printf("\x1b[0m%s", msg) end

			tty.curs_down(1)
		end
	end

	-- redraw statusbar bar and input line.
	M.statusbar(bufs, cbuf); M.inputbar(bufs, cbuf, nick)

	tty.curs_show()
	tty.curs_restore()
end

function M.format_line(timestr, left, right_fmt, ...)
	assert(timestr)
	assert(left)
	assert(right_fmt)

	local right = format(right_fmt, ...)

	-- fold message to width (see /bin/fold)
	local infocol_width = config.left_col_width + config.time_col_width
	local def_width = M.tty_width - infocol_width
	right = util.fold(right, config.right_col_width or def_width)
	right = right:gsub("\n", format("\n%s",
		util.strrepeat(" ", infocol_width + 4)))

	-- Strip escape sequences from the left column so that
	-- we can calculate how much padding to add for alignment, and
	-- not get confused by the invisible escape sequences.
	local raw = left:gsub("\x1b%[.-m", "")

	-- Generate a cursor right sequence based on the length of
	-- the above "raw" word. The nick column is a fixed width
	-- of LEFT_PADDING so it's simply 'LEFT_PADDING - word_len'
	local left_pad = (config.left_col_width + 1) - #raw
	local time_pad = (config.time_col_width + 1) - #timestr
	if #raw > config.left_col_width then left_pad = 0 end
	if #timestr > config.time_col_width then time_pad = 0 end

	return format("\x1b[90m%s\x1b[m\x1b[%sC \x1b[%sC%s %s",
		timestr, time_pad, left_pad, left, right)
end

function M.draw_line(bufs, cbuf, dest, out, nick)
	assert(dest)
	assert(out)

	tty.curs_hide(); tty.curs_save()
	tty.curs_down(999)

	tty.clear_line()
	printf("%s\n", out)
	tty.clear_line()

	tty.curs_restore(); tty.curs_show()

	-- since we overwrote the inputbar, redraw it
	M.inputbar(bufs, cbuf, nick)
end

return M
