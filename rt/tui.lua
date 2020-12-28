local inspect = require("inspect")
local F = require("fun")
local mirc = require("mirc")
local tb = require("tb")
local util = require("util")
local format = string.format
local assert_t = util.assert_t
local M = {}
M["linefmt_func"] = nil
M["prompt_func"] = nil
M["statusline_func"] = nil
M["termtitle_func"] = nil
M["set_colors"] = {}
M["colors"] = {}
M["tty_height"] = 80
M["tty_width"] = 24
M.refresh = function()
    local y, x = lurch.tb_size()
    M["tty_height"] = y
    M["tty_width"] = x
    return nil
end
local function _hash(str)
    assert((nil ~= str), string.format("Missing argument %s on %s:%s", "str", "rt/tui.fnl", 26))
    local function _hash_fn(hsh, _, char)
        local hsh0 = hsh
        hsh0 = (hsh0 ~ utf8.codepoint(char))
        hsh0 = (hsh0 * 1541882171)
        hsh0 = (hsh0 ~ (hsh0 >> 15))
        return hsh0
    end
    local _0_0 = {F.iter(str)}
    if _0_0 then
        return F.foldl(0, _hash_fn, _0_0)
    else
        return _0_0
    end
end
M.highlight = function(text, _3ftext_as, _3fno_bold_3f)
    assert((nil ~= text), string.format("Missing argument %s on %s:%s", "text", "rt/tui.fnl", 36))
    assert_t({text, "string", "text"})
    local text0 = text
    local text_as = text_as
    local no_bold_3f = __fnl_global__no_5fbold_3f
    if not text_as then
        text_as = text0
    end
    if not M.set_colors[text_as] then
        local hash = (_hash(text_as) % (#M.colors - 1))
        hash = (hash + 1)
        local color = M.colors[hash]
        M["set_colors"][text_as] = color
    end
    local esc = mirc.BOLD
    if no_bold_3f then
        esc = ""
    end
    do
        local color = M.set_colors[text_as]
        if color then
            esc = (esc .. format("%s%003d", mirc._256COLOR, color))
        end
    end
    return format("%s%s%s", esc, text0, mirc.RESET)
end
M.prompt = function(inp, cursor)
    assert((nil ~= cursor), string.format("Missing argument %s on %s:%s", "cursor", "rt/tui.fnl", 61))
    assert((nil ~= inp), string.format("Missing argument %s on %s:%s", "inp", "rt/tui.fnl", 61))
    assert_t({inp, "string", "inp"}, {cursor, "number", "cursor"})
    if (bufs[cbuf].scroll ~= 0) then
        lurch.tb_writeline((M.tty_height - 1), "\22\2 -- more -- \15")
        return lurch.tb_setcursor(tb.TB_HIDE_CURSOR, tb.TB_HIDE_CURSOR)
    else
        return M.prompt_func(inp, cursor)
    end
end
M.statusline = function()
    M.statusline_func()
    return M.termtitle_func()
end
M.format_line = function(timestr, left, right, timew, leftw, _3frightw)
    assert((nil ~= leftw), string.format("Missing argument %s on %s:%s", "leftw", "rt/tui.fnl", 75))
    assert((nil ~= timew), string.format("Missing argument %s on %s:%s", "timew", "rt/tui.fnl", 75))
    assert((nil ~= right), string.format("Missing argument %s on %s:%s", "right", "rt/tui.fnl", 75))
    assert((nil ~= left), string.format("Missing argument %s on %s:%s", "left", "rt/tui.fnl", 75))
    assert((nil ~= timestr), string.format("Missing argument %s on %s:%s", "timestr", "rt/tui.fnl", 75))
    assert_t({timestr, "string", "timestr"}, {timew, "number", "timew"}, {left, "string", "left"}, {right, "string", "right"}, {leftw, "number", "leftw"})
    local right0 = right
    do
        local infow = (leftw + timew)
        local width = ((rightw or M.tty_width) - infow)
        local rpadd = string.rep(" ", (infow + 4))
        right0 = util.fold(right0, (width - 4))
        right0 = right0:gsub("\n", ("%1" .. rpadd))
    end
    local raw = mirc.remove(left)
    local left_pad = ((leftw + 1) - lurch.utf8_dwidth(raw))
    local time_pad = ((timew + 1) - lurch.utf8_dwidth(timestr))
    if (#raw > leftw) then
        left_pad = 0
    end
    if (#timestr > timew) then
        time_pad = 0
    end
    return M.linefmt_func(time_pad, left_pad, timestr, left, right0)
end
M.buffer_text = function(timew, leftw, _3frightw)
    assert((nil ~= leftw), string.format("Missing argument %s on %s:%s", "leftw", "rt/tui.fnl", 105))
    assert((nil ~= timew), string.format("Missing argument %s on %s:%s", "timew", "rt/tui.fnl", 105))
    local linestart = 1
    local lineend = (M.tty_height - 2)
    local h_st = (#bufs[cbuf].history - (M.tty_height - 4))
    local h_end = #bufs[cbuf].history
    local scr = bufs[cbuf].scroll
    local line = lineend
    local function _process_msg(msg)
        assert((nil ~= msg), string.format("Missing argument %s on %s:%s", "msg", "rt/tui.fnl", 126))
        local out = M.format_line(msg[1], msg[2], msg[3], timew, leftw, rightw)
        lurch.tb_writeline(line, mirc.RESET)
        local msglines = nil
        do
            local _0_0 = {out:gmatch("([^\n]+)\n?")}
            if _0_0 then
                local function _1_(_241)
                    return _241
                end
                msglines = F.map(_1_, _0_0)
            else
                msglines = _0_0
            end
        end
        line = (line - #msglines)
        do
            local _1_0 = {F.iter(msglines)}
            if _1_0 then
                local function _2_(_241, _242)
                    line = (line + 1)
                    if (line > linestart) then
                        return lurch.tb_writeline(line, _242)
                    end
                end
                F.map(_2_, _1_0)
            else
            end
        end
        line = (line - #msglines)
        return nil
    end
    local _0_0 = {F.range((h_end - scr), (h_st - scr), -1)}
    if _0_0 then
        local function _1_(_241)
            if (line > linestart) then
                local msg = bufs[cbuf].history[_241]
                if msg then
                    return _process_msg(msg)
                else
                    line = (line - 1)
                    return nil
                end
            end
        end
        return F.map(_1_, _0_0)
    else
        return _0_0
    end
end
M.redraw = function(inbuf, incurs, timew, leftw, _3frightw)
    assert((nil ~= leftw), string.format("Missing argument %s on %s:%s", "leftw", "rt/tui.fnl", 158))
    assert((nil ~= timew), string.format("Missing argument %s on %s:%s", "timew", "rt/tui.fnl", 158))
    assert((nil ~= incurs), string.format("Missing argument %s on %s:%s", "incurs", "rt/tui.fnl", 158))
    assert((nil ~= inbuf), string.format("Missing argument %s on %s:%s", "inbuf", "rt/tui.fnl", 158))
    M.refresh()
    lurch.tb_clear()
    M.statusline()
    M.buffer_text(timew, leftw, rightw)
    return M.prompt(inbuf, incurs)
end
return M
