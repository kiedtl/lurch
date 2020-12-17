-- mIRC color sequences
--
-- TODO: unit tests

local mirc = {}

mirc.BOLD      = "\x02"
mirc.UNDERLINE = "\x1f"
mirc.ITALIC    = "\x1d"
mirc.INVERT    = "\x16"
mirc.BLINK     = "\x06"
mirc.RESET     = "\x0f"
mirc.COLOR     = "\x03"

-- non-standard extension
mirc._256COLOR  = "\x04"

mirc.BLACK        = 01
mirc.RED          = 05
mirc.GREEN        = 03
mirc.YELLOW       = 07
mirc.BLUE         = 02
mirc.MAGENTA      = 06
mirc.CYAN         = 10
mirc.GREY         = 14
mirc.LIGHTGREY    = 15
mirc.LIGHTRED     = 04
mirc.LIGHTGREEN   = 09
mirc.LIGHTYELLOW  = 08
mirc.LIGHTBLUE    = 12
mirc.LIGHTMAGENTA = 13
mirc.LIGHTCYAN    = 11
mirc.WHITE        = 00

function mirc.remove(text)
    text = text:gsub("[\x02\x1f\x1d\x16\x06\x0f]", "")
    text = text:gsub("\x03[0-9][0-9]?,[0-9][0-9]?", "")
    text = text:gsub("\x03[0-9][0-9]?", "")
    text = text:gsub("\x03", "")
    text = text:gsub("\x04[0-9][0-9][0-9]", "")
    return text
end

return mirc
