-- tbrl: readline for termbox.

local tb = require('tb')
local inspect = require('inspect')
local M = {}

M.bufin = { "" }
M.hist = #M.bufin
M.cursor = 0

M.enter_callback = nil
M.resize_callback = nil

local _ulen = function(s)
    return assert(utf8.len(s))
end
local _usub = function(s, i, j)
    i = utf8.offset(s, i)
    j = utf8.offset(s, j + 1) - 1
    return string.sub(s, i, j)
end

function M.insert_at_curs(text)
    if not text then return end
    M.bufin[M.hist] = lurch.utf8_insert(M.bufin[M.hist], M.cursor, text)
    M.cursor = M.cursor + 1
end

local function _backspace()
    if M.cursor == 0 then return end
    M.bufin[M.hist] = _usub(M.bufin[M.hist], 1, M.cursor-1) ..
        _usub(M.bufin[M.hist], M.cursor+1, _ulen(M.bufin[M.hist]))
    M.cursor = M.cursor - 1
end

local function _home() M.cursor = 0 end
local function _end() M.cursor = _ulen(M.bufin[M.hist]) end
local function _right()
    if M.cursor < _ulen(M.bufin[M.hist]) then M.cursor = M.cursor + 1 end
end
local function _left() if M.cursor > 0 then M.cursor = M.cursor - 1 end end
local function _up()
    if M.hist > 1 then
        M.hist = M.hist - 1
        M.cursor = _ulen(M.bufin[M.hist])
    end
end
local function _down()
    if M.hist < #M.bufin then
        M.hist = M.hist + 1
        M.cursor = _ulen(M.bufin[M.hist])
    end
end

-- TODO: Ctrl-_ undo
-- TODO: Ctrl-d delete at right of cursor
-- TODO:  Esc-d delete word at right of cursor
-- TODO:  Esc-h delete word at left of cursor
M.bindings = {}
M.bindings = {
    -- backspace
    [tb.TB_KEY_BACKSPACE] = _backspace,
    [tb.TB_KEY_BACKSPACE2] = _backspace,

    -- delete
    [tb.TB_KEY_DELETE] = function(_)
        M.bufin[M.hist] = _usub(M.bufin[M.hist], 1, M.cursor) ..
            _usub(M.bufin[M.hist], M.cursor+2, _ulen(M.bufin[M.hist]))
    end,

    -- cursor movement, history movement
    [tb.TB_KEY_HOME]        = _home,  [tb.TB_KEY_CTRL_A] = _home,
    [tb.TB_KEY_END]         = _end,   [tb.TB_KEY_CTRL_E] = _end,
    [tb.TB_KEY_ARROW_LEFT]  = _left,  [tb.TB_KEY_CTRL_B] = _left,
    [tb.TB_KEY_ARROW_RIGHT] = _right, [tb.TB_KEY_CTRL_F] = _right,
    [tb.TB_KEY_ARROW_UP]    = _up,    [tb.TB_KEY_CTRL_P] = _up,
    [tb.TB_KEY_ARROW_DOWN]  = _down,  [tb.TB_KEY_CTRL_N] = _down,

    -- delete from cursor until end of line
    [tb.TB_KEY_CTRL_K] = function(_)
        M.bufin[M.hist] = _usub(M.bufin[M.hist], 1, M.cursor)
    end,

    -- delete word to the left of cursor.
    [tb.TB_KEY_CTRL_W] = function(_)
        -- if the cursor is on a space, move left until we
        -- encounter a non-whitespace character.
        if _usub(M.bufin[M.hist], M.cursor, M.cursor) == " " then
            while _usub(M.bufin[M.hist], M.cursor, M.cursor) == " " do
                if M.cursor <= 0 then break end
                M.cursor = M.cursor - 1
            end
        end

        -- now that we're on a solid character, move left until
        -- we encounter another space.
        while _usub(M.bufin[M.hist], M.cursor, M.cursor) ~= " " do
            if M.cursor <= 0 then break end
            M.cursor = M.cursor - 1
        end

        -- delete whatever is after our cursor.
        M.bufin[M.hist] = _usub(M.bufin[M.hist], 1, M.cursor)
    end,

    -- space, enter
    [tb.TB_KEY_SPACE] = function(_) M.insert_at_curs(" ") end,
    [tb.TB_KEY_ENTER] = function(_)
        if M.enter_callback then
            M.enter_callback(M.bufin[M.hist])
        end

        -- if the user scrolled up in history and re-entered
        -- something, add that to the end of the history.
        if M.hist ~= #M.bufin then
            -- if the current entry is empty, overwrite it
            local idx = #M.bufin
            if M.bufin[idx] ~= "" then idx = #M.bufin + 1 end
            M.bufin[idx] = M.bufin[M.hist]
        end

        M.bufin[#M.bufin + 1] = ""; M.hist = #M.bufin
        M.cursor = 0
    end
}

function M.on_event(event)
    if event.type == tb.TB_EVENT_KEY
    or event.type == tb.TB_EVENT_MOUSE then
        -- The key event could be a key combo or a char.
        if event.ch ~= 0 and event.mod == 0 then
            M.insert_at_curs(utf8.char(event.ch))
        elseif event.ch ~= 0 and event.mod ~= 0 then
            if M.bindings[event.mod] then
                (M.bindings[event.mod])(event)
            end
        elseif event.key ~= 0 then
            if M.bindings[event.key] then
                (M.bindings[event.key])(event)
            end
        end
    elseif event.type == tb.TB_EVENT_RESIZE then
        if M.resize_callback then
            M.resize_callback()
        end
    end
end

return M
