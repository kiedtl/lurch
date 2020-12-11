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
mirc.tty_eq[mirc.BLACK]        = { "\x1b2\x00",  "\x1b7\x00" }
mirc.tty_eq[mirc.RED]          = { "\x1b2\x01",  "\x1b7\x01" }
mirc.tty_eq[mirc.GREEN]        = { "\x1b2\x02",  "\x1b7\x02" }
mirc.tty_eq[mirc.YELLOW]       = { "\x1b2\x03",  "\x1b7\x03" }
mirc.tty_eq[mirc.BLUE]         = { "\x1b2\x04",  "\x1b7\x04" }
mirc.tty_eq[mirc.MAGENTA]      = { "\x1b2\x05",  "\x1b7\x05" }
mirc.tty_eq[mirc.CYAN]         = { "\x1b2\x06",  "\x1b7\x06" }
mirc.tty_eq[mirc.GREY]         = { "\x1b2\x07",  "\x1b7\x07" }
mirc.tty_eq[mirc.LIGHTGREY]    = { "\x1b2\x08",  "\x1b7\x08" }
mirc.tty_eq[mirc.LIGHTRED]     = { "\x1b2\x09",  "\x1b7\x09" }
mirc.tty_eq[mirc.LIGHTGREEN]   = { "\x1b2\x0a",  "\x1b7\x0a" }
mirc.tty_eq[mirc.LIGHTYELLOW]  = { "\x1b2\x0b",  "\x1b7\x0b" }
mirc.tty_eq[mirc.LIGHTBLUE]    = { "\x1b2\x0c",  "\x1b7\x0c" }
mirc.tty_eq[mirc.LIGHTMAGENTA] = { "\x1b2\x0d",  "\x1b7\x0d" }
mirc.tty_eq[mirc.LIGHTCYAN]    = { "\x1b2\x0e",  "\x1b7\x0e" }
mirc.tty_eq[mirc.WHITE]        = { "\x1b2\x0f",  "\x1b7\x0f" }

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
