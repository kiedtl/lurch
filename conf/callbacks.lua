local mirc = require('mirc')
local tui  = require('tui')
local util = require('util')
local format = string.format
local M = {}

-- This is called at the beginning of lurch, and its purpose
-- it to print some nice text and ascii art on the main buffer.
-- Of course, you could just stuff this into on_startup().
--
-- This function should assume that the current buffer already
-- is the main buffer, and should not switch buffers.
function M.print_banner(version)
    -- the text to be printed. Note that completely blank lines
    -- won't get printed, so add a trailing space to empty lines.
    local text = "\n\
|     ._ _ |_    o ._  _    _ | o  _  ._ _|_\n\
| |_| | (_ | |   | |  (_   (_ | | (/_ | | |_\n\
 \n\
lurch %s (https://github.com/lptstr/lurch)\n\
(c) Kiëd Llaentenn. Lurch is GPLv3 software.\n\
 \n\
-- -- -- -- -- -- -- -- -- -- -- -- -- -- --\n\
 \n\
"
    text = format(text, version)

    -- print each line, one by one.
    for textline in text:gmatch("([^\n]+)\n?") do
        prin_cmd(buf_cur(), "--", "%s", textline)
    end
end

-- This is a sample prompt function. It's extremely barebones,
-- and does nothing beyond printing what the user has entered
-- and making the cursor visible. See fancy_promptf for a more
-- complex example.
--
-- See: callbacks.prompt
function M.simple_promptf(inp, cursor)
    -- strip off stuff from input that can't be shown on the
    -- screen, and show IRC formatting escape sequences nicely.
    inp = mirc.show(inp:sub(-(tui.tty_width - 1)))

    -- draw the input buffer and move the cursor to the appropriate
    -- position.
    lurch.tb_writeline(tui.tty_height-1, inp)
    lurch.tb_setcursor(cursor, tui.tty_height-1)
end

-- A more fully-featured prompt function. This prompt changes
-- dynamically as the user types and shows clearly how the input
-- will be interpreted: as a command, as a /note, as a /me, or
-- as a regular message. It was inspired by catgirl[0].
--
-- See: callbacks.prompt
-- [0]: https://git.causal.agency/catgirl
function M.fancy_promptf(inp, cursor)
    -- by default, the prompt is <NICK>, but if the user is
    -- typing a command, change to prompt to "/"; if the user
    -- has typed "/me", change the prompt to "* <NICK>"; if
    -- the user has type "/note", change to the prompt to
    -- "NOTE(<NICK>)".
    --
    -- In all these cases, redundant input is trimmed off (unless
    -- the cursor is on the redundant text, in which case the
    -- input is shown as-is).
    local prompt

    -- highlighted nickname.
    local hnick = tui.highlight(nick)

    if inp:find("/me ") == 1 and cursor >= 4 then
        prompt = format("* %s ", hnick)
        inp = inp:sub(5, #inp)
        cursor = cursor - 4
    elseif inp:find("/note ") == 1 and cursor >= 6 then
        prompt = format("NOTE(%s) ", hnick)
        inp = inp:sub(7, #inp)
        cursor = cursor - 6
    elseif inp:sub(1, 1) == "/" then
        -- if there are two slashes at the beginning of the input,
        -- indicate that it will be treated as a message instead
        -- of a command.
        if inp:sub(2, 2) == "/" then
            prompt = format("<%s> \x0314/\x0f", hnick)
        else
            prompt = format("\x0314/\x0f")
        end

        inp = inp:sub(2, #inp)
        cursor = cursor - 1
    else
        prompt = format("<%s> ", hnick)
    end

    -- strip escape sequences so that we may accurately calculate
    -- the prompt's length.
    local rawprompt = mirc.remove(prompt)

    -- strip off stuff from input that can't be shown on the
    -- screen
    local offset = (tui.tty_width - 1) - #rawprompt
    inp = inp:sub(-offset)

    -- show IRC formatting escape sequences nicely.
    inp = mirc.show(inp)

    -- draw the input buffer and move the cursor to the appropriate
    -- position.
    lurch.tb_writeline(tui.tty_height-1, format("%s%s", prompt, inp))
    lurch.tb_setcursor(cursor + #rawprompt, tui.tty_height-1)
end

-- The function that is called on every keypress. It should, at the
-- very least, draw the current input and make the cursor visible
-- in the correct location. By default, it is set to the fancy_promptf
-- function above, but feel free to set it to your own function and
-- delete the builtin ones if you so please.
M.prompt = M.fancy_promptf

return M
