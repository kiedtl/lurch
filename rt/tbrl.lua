-- tbrl: readline for termbox.

local tb = require('tb')
local inspect = require('inspect')
local M = {}

M.bufin = ""
M.cursor = 0

M.enter_callback = nil

function M.insert_at_curs(text)
	M.bufin = M.bufin:gsub(("."):rep(M.cursor), "%1" .. text, 1)
	M.cursor = M.cursor + 1
end

local function _backspace()
	if M.cursor == 0 then return end
	M.bufin = M.bufin:sub(1, M.cursor-1) ..
		M.bufin:sub(M.cursor+1, #M.bufin)
	M.cursor = M.cursor - 1
end
local function _home() M.cursor = 0 end
local function _end()  M.cursor = #M.bufin end
local function _left()
	if M.cursor > 0 then M.cursor = M.cursor - 1 end
end
local function _right()
	if M.cursor < #M.bufin then M.cursor = M.cursor + 1 end
end

M.bindings = {}
M.bindings = {
	[tb.TB_KEY_BACKSPACE] = _backspace,
	[tb.TB_KEY_BACKSPACE2] = _backspace,

	[tb.TB_KEY_DELETE] = function(_)
		M.bufin = M.bufin:sub(1, M.cursor) ..
			M.bufin:sub(M.cursor+2, #M.bufin)
	end,

	[tb.TB_KEY_HOME]        = _home,  [tb.TB_KEY_CTRL_A] = _home,
	[tb.TB_KEY_END]         = _end,   [tb.TB_KEY_CTRL_E] = _end,
	[tb.TB_KEY_ARROW_LEFT]  = _left,  [tb.TB_KEY_CTRL_B] = _left,
	[tb.TB_KEY_ARROW_RIGHT] = _right, [tb.TB_KEY_CTRL_F] = _right,

	[tb.TB_KEY_CTRL_K] = function(_)
		M.bufin = M.bufin:sub(1, M.cursor)
	end,

	[tb.TB_KEY_SPACE] = function(_) M.insert_at_curs(" ") end,
	[tb.TB_KEY_ENTER] = function(_)
		if M.enter_callback then
			M.enter_callback(M.bufin)
		end

		M.bufin = ""; M.cursor = 0
	end
}

function M.bind_keyseq(key, fn)
	M.bindings[key] = fn
end

function M.on_event(event, enter_callback)
	if event.type == tb.TB_EVENT_KEY then
		M.on_key_event(event, enter_callback, keyseq_callback)
	end
end

function M.on_key_event(event, enter_callback)
	-- The key event could be a key combo or an entered character.
	if event.ch ~= 0 then
		M.insert_at_curs(utf8.char(event.ch))
	elseif event.key ~= 0 then
		if M.bindings[event.key] then
			(M.bindings[event.key])(event.key)
		end
	end
end

return M
