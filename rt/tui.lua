local config  = require('config')
local inspect = require('inspect')
local mirc    = require('mirc')
local tb      = require('tb')
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
    local esc = "\x02"
    if no_bold then esc = "" end

    if color then
        esc = esc .. format("\x04%003d", color)
    end

    return format("%s%s\x0f", esc, text)
end

function M.prompt(bufs, cbuf, nick, inp, cursor)
    -- if we've scrolled up, don't draw the input.
    if bufs[cbuf].scroll ~= #bufs[cbuf].history then
        lurch.tb_writeline(M.tty_height - 1, "\x16\x02 -- more -- \x0f")
        lurch.tb_setcursor(tb.TB_HIDE_CURSOR, tb.TB_HIDE_CURSOR)
        return
    end

    -- by default, the prompt is <NICK>, but if the user is
    -- typing a command, change to prompt to "/"; if the user
    -- has typed "/me", change the prompt to "* <NICK>".
    --
    -- In all these cases, redundant input is trimmed off (unless
    -- the cursor is on the redundant text, in which case the
    -- input is shown as-is).
    local prompt
    if inp:find("/me ") == 1 and cursor >= 4 then
        prompt = format("* %s ", M.highlight(nick))
        inp = inp:sub(5, #inp)
        cursor = cursor - 4
    elseif inp:sub(1, 1) == "/" then
        -- if there are two slashes at the beginning of the input,
        -- indicate that it will be treated as a message instead
        -- of a command.
        if inp:sub(2, 2) == "/" then
            prompt = format("<%s> \x0314/\x0f", M.highlight(nick))
        else
            prompt = format("\x0314/\x0f")
        end

        inp = inp:sub(2, #inp)
        cursor = cursor - 1
    else
        prompt = format("<%s> ", M.highlight(nick))
    end

    -- strip escape sequences so that we may accurately calculate
    -- the prompt's length.
    local rawprompt = mirc.remove(prompt)

    -- strip off stuff from input that can't be shown on the
    -- screen
    local offset = (M.tty_width - 1) - #rawprompt
    inp = inp:sub(-offset)

    -- show IRC formatting escape sequences nicely. Use a "marker"
    -- character of '\r' to prevent us from highlighting our own
    -- escape sequences.
    local tmp = ""
    local fmt = { [mirc.BOLD] = "B", [mirc.UNDERLINE] = "U",
        [mirc.ITALIC] = "I", [mirc.INVERT] = "R", [mirc.RESET] = "O" }
    for i = 1, #inp do
        local byte = inp:sub(i, i)
        if fmt[byte] then
            tmp = format("%s\x0f\x16%s\x0f%s", tmp, fmt[byte], byte)
        else
            tmp = tmp .. byte
        end
    end
    inp = tmp

    -- draw the input buffer and move the cursor to the appropriate
    -- position.
    lurch.tb_writeline(M.tty_height-1, format("%s%s", prompt, inp))
    lurch.tb_setcursor(cursor + #rawprompt, M.tty_height-1)
end

function M.simple_statusbar(bufs, cbuf)
    local chl = ""
    local l = 0
    local fst = cbuf

    while fst > 1 and l < (M.tty_width / 2) do
        l = l + lurch.utf8_dwidth(bufs[fst].name) + 3
        fst = fst - 1
    end

    l = 0
    while fst <= #bufs and l < M.tty_width do
        local ch = bufs[fst]
        if fst == cbuf then chl = chl .. mirc.RESET end

        chl = chl .. "  "; l = l + 1

        if ch.unreadh > 0 then chl = chl .. mirc.UNDERLINE end
        if ch.pings > 0   then chl = chl .. mirc.BOLD end

        chl = chl .. ch.name
        l = l + lurch.utf8_dwidth(ch.name)

        if ch.pings > 0   then chl = chl .. mirc.BOLD end
        if ch.unreadh > 0 then chl = chl .. mirc.UNDERLINE end

        if l < (M.tty_width - 1) then
            chl = chl .. "  "; l = l + 2
        end

        if fst == cbuf then chl = chl .. mirc.INVERT end

        fst = fst + 1
    end

    local padding = M.tty_width - #(mirc.remove(chl))
    chl = format("\x16%s%s\x0f", chl, (" "):rep(padding))
    lurch.tb_writeline(0, chl)

    -- set the terminal title. This is a big help when using terminal
    -- tabs to mimic a multi-server feature.
    util.settitle("[%s] %s", config.host, bufs[cbuf].name)
end

function M.fancy_statusbar(bufs, cbuf)
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
            chanlist = format("%s\x16%s\x0f ", chanlist, pnch)
        else
            if pnch then
                chanlist = format("%s%s ", chanlist, pnch)
            end
        end
    end

    lurch.tb_writeline(0, chanlist)

    -- set the terminal title. This is a big help when using terminal
    -- tabs to mimic a multi-server feature.
    util.settitle("[%s] %s", config.host, bufs[cbuf].name)
end

M.statusbar = M.fancy_statusbar

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
    M.prompt(bufs, cbuf, nick, inbuf, incurs)
    M.statusbar(bufs, cbuf)
end

function M.format_line(timestr, left, right_fmt, ...)
    assert(timestr)
    assert(left)
    assert(right_fmt)

    local right = format(right_fmt, ...)

    -- fold message to width (see /bin/fold)
    local infocol_width = config.left_col_width + config.time_col_width
    local width = (config.right_col_width or M.tty_width - infocol_width)
    right = util.fold(right, width - 4)
    right = right:gsub("\n", format("\n%s", (" "):rep(infocol_width + 4)))

    -- Strip escape sequences from the left column so that
    -- we can calculate how much padding to add for alignment, and
    -- not get confused by the invisible escape sequences.
    local raw = mirc.remove(left)

    -- Generate a cursor right sequence based on the length of
    -- the above "raw" word. The nick column is a fixed width
    -- of LEFT_PADDING so it's simply 'LEFT_PADDING - word_len'
    local left_pad = (config.left_col_width + 1) - #raw
    local time_pad = (config.time_col_width + 1) - #timestr
    if #raw > config.left_col_width then left_pad = 0 end
    if #timestr > config.time_col_width then time_pad = 0 end

    return format("\x0f\x0314%s\x0f%s %s%s %s", timestr,
        (" "):rep(time_pad), (" "):rep(left_pad), left, right)
end

return M
