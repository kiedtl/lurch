local tui = require('tui')
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
lurch %s   (https://github.com/lptstr/lurch)\n\
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

return M
