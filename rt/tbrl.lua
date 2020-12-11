-- tbrl: readline for termbox.

local tb = require('tb')
local inspect = require('inspect')
local M = {}

M.bufin = ""
M.cursor = 0

M.bindings = {}

function M.on_event(event, enter_callback, keyseq_callback)
	if event.type == tb.TB_EVENT_KEY then
		M.on_key_event(event, enter_callback, keyseq_callback)
	end
end

function M.on_key_event(event, enter_callback, keyseq_callback)
	-- The key event could be a key combo or an entered character.
	if event.ch ~= 0 then
		local ch = utf8.char(event.ch)
		M.bufin = M.bufin:gsub(("."):rep(M.cursor), "%1" .. ch, 1)
		M.cursor = M.cursor + 1
	elseif event.key ~= 0 then
		if event.key == tb.TB_KEY_BACKSPACE
				or event.key == tb.TB_KEY_BACKSPACE2 then
			if M.cursor == 0 then return end
			M.bufin = M.bufin:sub(1, M.cursor+1) .. M.bufin:sub(M.cursor+3, #M.bufin)
			M.cursor = M.cursor - 1
		elseif event.key == tb.TB_KEY_SPACE then
			M.bufin = M.bufin:gsub(("."):rep(M.cursor), "%1 ")
			M.cursor = M.cursor + 1
		elseif event.key == tb.TB_KEY_ENTER then
			enter_callback(M.bufin)
			M.bufin = ""
			M.cursor = 0
		end

		if M.bindings[event.key] then
			keyseq_callback(event.key)
		end
	end
end

return M
