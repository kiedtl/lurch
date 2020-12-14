-- mIRC color sequences
--
-- almost all IRC clients will support bold and reset,
-- most clients will support italic and underline, but very
-- few support blink. I'm not sure about support for invert.
--
-- TODO: add option to remove blink attribute; it's a bit
-- user-hostile.
-- TODO: unit tests

local mirc = {}

mirc.BOLD      = "\x02"
mirc.UNDERLINE = "\x1f"
mirc.ITALIC    = "\x1d"
mirc.INVERT    = "\x16"
mirc.BLINK     = "\x06"
mirc.RESET     = "\x0f"
mirc.COLOR     = "\x03"

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

-- tty escape sequence equivalents to mIRC colors.
mirc.tty_eq = {}
mirc.tty_eq[mirc.BLACK]        = { "\x1b2000m",  "\x1b7000m" }
mirc.tty_eq[mirc.RED]          = { "\x1b2001m",  "\x1b7001m" }
mirc.tty_eq[mirc.GREEN]        = { "\x1b2002m",  "\x1b7002m" }
mirc.tty_eq[mirc.YELLOW]       = { "\x1b2003m",  "\x1b7003m" }
mirc.tty_eq[mirc.BLUE]         = { "\x1b2004m",  "\x1b7004m" }
mirc.tty_eq[mirc.MAGENTA]      = { "\x1b2005m",  "\x1b7005m" }
mirc.tty_eq[mirc.CYAN]         = { "\x1b2006m",  "\x1b7006m" }
mirc.tty_eq[mirc.GREY]         = { "\x1b2007m",  "\x1b7007m" }
mirc.tty_eq[mirc.LIGHTGREY]    = { "\x1b2008m",  "\x1b7008m" }
mirc.tty_eq[mirc.LIGHTRED]     = { "\x1b2009m",  "\x1b7009m" }
mirc.tty_eq[mirc.LIGHTGREEN]   = { "\x1b2010m",  "\x1b7010m" }
mirc.tty_eq[mirc.LIGHTYELLOW]  = { "\x1b2011m",  "\x1b7011m" }
mirc.tty_eq[mirc.LIGHTBLUE]    = { "\x1b2012m",  "\x1b7012m" }
mirc.tty_eq[mirc.LIGHTMAGENTA] = { "\x1b2013m",  "\x1b7013m" }
mirc.tty_eq[mirc.LIGHTCYAN]    = { "\x1b2014m",  "\x1b7014m" }
mirc.tty_eq[mirc.WHITE]        = { "\x1b2015m",  "\x1b7015m" }

function mirc.remove(text)
    text = text:gsub("[\x02\x1f\x1d\x16\x06\x0f]", "")
    text = text:gsub("\x03[0-9][0-9]?,[0-9][0-9]?", "")
    text = text:gsub("\x03[0-9][0-9]?", "")
    text = text:gsub("\x03", "")
    return text
end

function mirc.to_tty_seq(text)
    -- convert attributes using a simple search-and-replace.
    text = text:gsub(mirc.BOLD,      "\x1b1m")
    text = text:gsub(mirc.UNDERLINE, "\x1b4m")
    text = text:gsub(mirc.ITALIC,    "\x1b5m")
    text = text:gsub(mirc.INVERT,    "\x1b3m")
    text = text:gsub(mirc.BLINK,     "\x1b6m")
    text = text:gsub(mirc.RESET,     "\x1brm")

    -- extract color-changing sequences, parse them, and convert
    -- them.
    for fg, bg in text:gmatch("\x03([0-9][0-9]?),([0-9][0-9]?)") do
        local nfg = tonumber(fg)
        local nbg = tonumber(bg)

        local tty_fg, tty_bg = "", ""
        if mirc.tty_eq[nfg] then tty_fg = mirc.tty_eq[nfg][1] end
        if mirc.tty_eq[nbg] then tty_bg = mirc.tty_eq[nbg][2] end

        text = text:gsub(("\x03%s,%s"):format(fg, bg), tty_fg .. tty_bg)
    end

    for fg in text:gmatch("\x03([0-9][0-9]?)") do
        local nfg = tonumber(fg)

        local tty_fg = ""
        if mirc.tty_eq[nfg] then tty_fg = mirc.tty_eq[nfg][1] end

        text = text:gsub(("\x03%s"):format(fg), tty_fg)
    end

    text = text:gsub(mirc.COLOR, "\x1brm")
    return text
end

return mirc
