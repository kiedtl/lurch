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
mirc.tty_eq[mirc.BLACK]        = { "\x1b[30m",  "\x1b[40m" }
mirc.tty_eq[mirc.RED]          = { "\x1b[31m",  "\x1b[41m" }
mirc.tty_eq[mirc.GREEN]        = { "\x1b[32m",  "\x1b[42m" }
mirc.tty_eq[mirc.YELLOW]       = { "\x1b[33m",  "\x1b[43m" }
mirc.tty_eq[mirc.BLUE]         = { "\x1b[34m",  "\x1b[44m" }
mirc.tty_eq[mirc.MAGENTA]      = { "\x1b[35m",  "\x1b[45m" }
mirc.tty_eq[mirc.CYAN]         = { "\x1b[36m",  "\x1b[46m" }
mirc.tty_eq[mirc.GREY]         = { "\x1b[37m",  "\x1b[47m" }
mirc.tty_eq[mirc.LIGHTGREY]    = { "\x1b[38m",  "\x1b[48m" }
mirc.tty_eq[mirc.LIGHTRED]     = { "\x1b[91m", "\x1b[101m" }
mirc.tty_eq[mirc.LIGHTGREEN]   = { "\x1b[92m", "\x1b[102m" }
mirc.tty_eq[mirc.LIGHTYELLOW]  = { "\x1b[93m", "\x1b[103m" }
mirc.tty_eq[mirc.LIGHTBLUE]    = { "\x1b[94m", "\x1b[104m" }
mirc.tty_eq[mirc.LIGHTMAGENTA] = { "\x1b[95m", "\x1b[105m" }
mirc.tty_eq[mirc.LIGHTCYAN]    = { "\x1b[96m", "\x1b[106m" }
mirc.tty_eq[mirc.WHITE]        = { "\x1b[97m", "\x1b[107m" }

function mirc.remove(text)
	text = text:gsub("[\x02\x1f\x1d\x16\x06\x0f]", "")
	text = text:gsub("\x03[0-9][0-9]?,[0-9][0-9]?", "")
	text = text:gsub("\x03[0-9][0-9]?", "")
	text = text:gsub("\x03", "")
	return text
end

function mirc.to_tty_seq(text)
	-- convert attributes using a simple search-and-replace.
	text = text:gsub(mirc.BOLD,      "\x1b[1m")
	text = text:gsub(mirc.UNDERLINE, "\x1b[4m")
	text = text:gsub(mirc.ITALIC,    "\x1b[3m")
	text = text:gsub(mirc.INVERT,    "\x1b[7m")
	text = text:gsub(mirc.BLINK,     "\x1b[5m")
	text = text:gsub(mirc.RESET,     "\x1b[0m")

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

	text = text:gsub(mirc.COLOR, "\x1b[m")
	return text
end

return mirc
