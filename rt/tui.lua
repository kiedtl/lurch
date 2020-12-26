local inspect  = require('inspect')
local mirc     = require('mirc')
local tb       = require('tb')
local util     = require('util')
local format   = string.format
local assert_t = util.assert_t

local M = {}

M.linefmt_func    = nil
M.prompt_func     = nil
M.statusline_func = nil
M.termtitle_func  = nil
M.set_colors      = {}
M.colors          = {}
M.tty_height      = 80
M.tty_width       = 24

function M.refresh()
    M.tty_height, M.tty_width = lurch.tb_size()
end

function M.highlight(text, text_as, no_bold)
    assert_t({text, "string", "text"})
    if not text_as then text_as = text end

    -- store nickname highlight color, so that we don't have to
    -- calculate the text's hash each time
    if not M.set_colors[text_as] then
        -- add one to the hash value, as the hash value may be 0
        M.set_colors[text_as] = lurch.hash(text_as) % (#M.colors - 1)
        M.set_colors[text_as] = M.set_colors[text_as] + 1
        M.set_colors[text_as] = M.colors[M.set_colors[text_as]]
    end

    local color = M.set_colors[text_as]
    local esc = "\x02"
    if no_bold then esc = "" end

    if color then
        esc = esc .. format("\x04%003d", color)
    end

    return format("%s%s\x0f", esc, text)
end

function M.prompt(inp, cursor)
    assert_t({inp, "string", "inp"}, {cursor, "number", "cursor"})

    -- if we've scrolled up, don't draw the input.
    if bufs[cbuf].scroll ~= 0 then
        lurch.tb_writeline(M.tty_height - 1, "\x16\x02 -- more -- \x0f")
        lurch.tb_setcursor(tb.TB_HIDE_CURSOR, tb.TB_HIDE_CURSOR)
    else
        M.prompt_func(inp, cursor)
    end
end

function M.statusline()
    M.statusline_func()
    M.termtitle_func()
end

function M.format_line(timestr, left, right, timew, leftw, rightw)
    -- rightw can be nil
    assert_t(
        { timestr, "string", "timestr" }, { timew, "number", "timew" },
        { left, "string", "left" },   { right, "string", "right" },
        { leftw, "number", "leftw" }  --{ rightw, "number", "rightw" }
    )

    -- fold message to width (see /bin/fold)
    local infow = leftw + timew
    local width = (rightw or M.tty_width - infow)
    right = util.fold(right, width - 4)
    right = right:gsub("\n", format("\n%s", (" "):rep(infow + 4)))

    -- Strip escape sequences from the left column so that
    -- we can calculate how much padding to add for alignment, and
    -- not get confused by the invisible escape sequences.
    local raw = mirc.remove(left)

    -- Generate a cursor right sequence based on the length of
    -- the above "raw" word. The nick column is a fixed width
    -- of LEFT_PADDING so it's simply 'LEFT_PADDING - word_len'
    local left_pad = (leftw + 1) - lurch.utf8_dwidth(raw)
    local time_pad = (timew + 1) - lurch.utf8_dwidth(timestr)
    if #raw > leftw then left_pad = 0 end
    if #timestr > timew then time_pad = 0 end

    return M.linefmt_func(time_pad, left_pad, timestr, left, right)
end

function M.buffer_text(timew, leftw, rightw)
    if not bufs[cbuf].history then return end

    -- keep one blank line in between statusline and text,
    -- and don't overwrite the prompt/inputline.
    local linestart = 1
    local lineend = M.tty_height - 2
    local line = lineend

    -- beginning at the bottom of the terminal, draw each line
    -- of text from that buffer's history, then move up.
    -- If there is nothing to draw, just clear the line and
    -- move on.
    --
    -- this bottom-up approach is used because we don't know in
    -- advance how many lines a particular history entry will take
    -- up, and thus don't know how many history events will fit
    -- on the screen.
    local h_st  = #bufs[cbuf].history - (M.tty_height-4)
    local h_end = #bufs[cbuf].history
    local scr   = bufs[cbuf].scroll

    for i = (h_end - scr), (h_st - scr), -1 do
        local msg = bufs[cbuf].history[i]

        if msg then
            -- fold the text to width. this is done now, instead
            -- of when prin_*() is called, so that when the terminal
            -- size changes we can fold text according to the new
            -- terminal width when the screen is redrawn.
            local out = M.format_line(msg[1], msg[2], msg[3],
                timew, leftw, rightw)

            -- Reset the colors before drawing the line
            lurch.tb_writeline(line, mirc.RESET)

            -- since we're drawing bottom-up, we need to iterate
            -- backwards.
            util.revgmatch(out, "([^\n]+)\n?", function(_, tline)
                lurch.tb_writeline(line, tline)
                line = line - 1
                if line == linestart then
                    return util.MAP_BREAK
                end
            end)
        else
            line = line - 1
        end

        if line == linestart then break end
    end
end

function M.redraw(inbuf, incurs, timew, leftw, rightw)
    M.refresh()
    lurch.tb_clear()

    M.statusline()
    M.buffer_text(timew, leftw, rightw)
    M.prompt(inbuf, incurs)
end

return M
