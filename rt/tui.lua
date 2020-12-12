local config  = require('config')
local inspect = require('inspect')
local mirc    = require('mirc')
local util    = require('util')
local format  = string.format

local M = {}

M.set_colors = {}
M.colors     = {}
M.tty_height = 80
M.tty_width  = 24

function M.refresh()
	M.tty_height, M.tty_width = lurch.tb_size()
end

function M.load_highlight_colors()
	-- read a list of newline-separated colors from ./conf/colors.
	-- the colors are terminal 256-bit colors.
	local data = util.read(__LURCH_EXEDIR .. "/conf/colors")

	for line in data:gmatch("([^\n]+)\n?") do
		M.colors[#M.colors + 1] = tonumber(line)
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
	local esc = "\x1b1m"
	if no_bold then esc = "" end

	-- if no color could be found, just use the default of black
	if color then
		esc = esc .. format("\x1b2%s", string.char(color))
	end

	return format("%s%s\x1brm", esc, text)
end

function M.inputbar(bufs, cbuf, nick, inp, cursor)
	-- if we've scrolled up, don't draw the input.
	if bufs[cbuf].scroll ~= #bufs[cbuf].history then
		lurch.tb_writeline(M.tty_height, "-- more --")
		lurch.tb_hidecursor()
		return
	end

	-- by default, the prompt is <NICK>, but if the user is
	-- typing a command, change to prompt to "/"; if the user
	-- has typed "/me", change the prompt to "* <NICK>".
	--
	-- Also, if the input is something like "//text", then the
	-- prompt should be "<NICK> /". In all these cases, redundant
	-- input is trimmed off.
	local prompt
	if inp:find("/me ") == 1 and cursor >= 4 then
		prompt = format("* %s ", M.highlight(nick))
		inp = inp:sub(5, #inp)
		cursor = cursor - 4
	elseif inp:sub(1, 1) == "/" then
		if inp:sub(2, 2) == "/" then
			prompt = format("<%s> \x1b2%s/\x1brm",
				M.highlight(nick), string.char(8))
		else
			prompt = format("\x1b2%s/\x1brm", string.char(8))
		end
		inp = inp:sub(2, #inp)
		cursor = cursor - 1
	else
		prompt = format("<%s> ", M.highlight(nick))
	end

	-- strip escape sequences so that we may accurately calculate
	-- the prompt's length.
	local rawprompt = prompt:gsub("\x1b..", "")

	-- strip off stuff from input that can't be shown on the
	-- screen
	inp = inp:sub(-(M.tty_width - #rawprompt))

	-- show IRC formatting escape sequences nicely.
	-- TODO: lurch esc module
	inp = inp:gsub(mirc.BOLD,      "\x1b3m\x1b2\8B\x1brm\x1b1m")
	inp = inp:gsub(mirc.UNDERLINE, "\x1b3m\x1b2\8U\x1brm\x1b4m")
	inp = inp:gsub(mirc.ITALIC,    "\x1b3m\x1b2\8I\x1brm\x1b5m")
	inp = inp:gsub(mirc.INVERT,    "\x1b3m\x1b2\8R\x1brm\x1b3m")
	inp = inp:gsub(mirc.RESET,     "\x1b3m\x1b2\8O\x1brm\x1brm")

	local curs_pos = cursor + #rawprompt
	if curs_pos > 0 then
		lurch.tb_showcursor(curs_pos, M.tty_height-1)
	else
		lurch.tb_showcursor(curs_pos, M.tty_height-1)
	end

	-- draw the input buffer and move the cursor to the appropriate
	-- position.
	lurch.tb_writeline(M.tty_height-1, format("%s%s", prompt, inp))
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
		local unread_ind = ""

		if bufs[buf].unreadl > 0 or bufs[buf].unreadh > 0 or bufs[buf].pings > 0 then
			if bufs[buf].pings > 0 then
				bold = true
				if bufs[buf].unreadh > 0 then
					unread_ind = format("+%d,%d", bufs[buf].pings, bufs[buf].unreadh)
				else
					unread_ind = format("+%d", bufs[buf].pings)
				end
			elseif bufs[buf].unreadh > 0 then
				if bufs[buf].unreadl > 0 then
					unread_ind = format("+%d (%d)", bufs[buf].unreadh, bufs[buf].unreadl)
				else
					unread_ind = format("+%d", bufs[buf].unreadh)
				end
			elseif bufs[buf].unreadl > 0 then
				unread_ind = format("(%d)", bufs[buf].unreadl)
			end
		end

		-- If there are no unread messages, don't display the buffer in the
		-- statusbar (unless it's the current buffer)
		local pnch
		if unread_ind ~= "" then
			pnch = M.highlight(format(" %d %s %s ", buf, ch, unread_ind),
				ch, not bold)
		elseif unread_ind == "" and buf == cbuf then
			pnch = M.highlight(format(" %d %s ", buf, ch), ch, true)
		end

		if buf == cbuf then
			chanlist = format("%s\x1b3m%s\x1brm ", chanlist, pnch)
		else
			if pnch then
				chanlist = format("%s%s ", chanlist, pnch)
			end
		end
	end

	lurch.tb_writeline(0, chanlist)

	-- set the terminal title. This is a big help when using terminal
	-- tabs to mimic a multi-server feature.
	tty.title("[%s] %s", config.server, bufs[cbuf].name)
end

function M.buffer_text(bufs, cbuf)
	-- keep one blank line in between statusbar and text.
	local line = 2

	-- beginning at the top of the terminal, draw each line
	-- of text from that buffer's history, then move down.
	-- If there is nothing to draw, just clear the line and
	-- move on.
	if bufs[cbuf].history then
		local hist_start = bufs[cbuf].scroll - (M.tty_height-4)
		for i = hist_start, bufs[cbuf].scroll do

			local msg = bufs[cbuf].history[i]
			if msg then lurch.tb_writeline(line, msg) end

			line = line + 1
			if line == (M.tty_height-1) then break end
		end
	end
end

function M.redraw(bufs, cbuf, nick, inbuf, incurs)
	M.refresh()
	lurch.tb_clear()

	M.buffer_text(bufs, cbuf)
	M.inputbar(bufs, cbuf, nick, inbuf, incurs)
	M.statusbar(bufs, cbuf)
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
	right = right:gsub("\n", format("\n%s", (" "):rep(infocol_width + 4)))

	-- Strip escape sequences from the left column so that
	-- we can calculate how much padding to add for alignment, and
	-- not get confused by the invisible escape sequences.
	local raw = left:gsub("\x1b..", "")

	-- Generate a cursor right sequence based on the length of
	-- the above "raw" word. The nick column is a fixed width
	-- of LEFT_PADDING so it's simply 'LEFT_PADDING - word_len'
	local left_pad = (config.left_col_width + 1) - #raw
	local time_pad = (config.time_col_width + 1) - #timestr
	if #raw > config.left_col_width then left_pad = 0 end
	if #timestr > config.time_col_width then time_pad = 0 end

	return format("\x1b2%s%s\x1brm%s %s%s %s", string.char(8), timestr,
		(" "):rep(time_pad), (" "):rep(left_pad), left, right)
end

return M
