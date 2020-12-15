// mIRC color sequences
//
// almost all IRC clients will support bold and reset,
// most clients will support italic and underline, but very
// few support blink. I'm not sure about support for invert.

#ifndef MIRC_H
#define MIRC_H

#define MIRC_BOLD       '\x02'
#define MIRC_UNDERLINE  '\x1f'
#define MIRC_ITALIC     '\x1d'
#define MIRC_INVERT     '\x16'
#define MIRC_BLINK      '\x06'
#define MIRC_RESET      '\x0f'
#define MIRC_COLOR      '\x03'

/* non-standard extension! */
#define MIRC_256COLOR   '\x04'

#define MIRC_BLACK          1
#define MIRC_RED            5
#define MIRC_GREEN          3
#define MIRC_YELLOW         7
#define MIRC_BLUE           2
#define MIRC_MAGENTA        6
#define MIRC_CYAN          10
#define MIRC_GREY          14
#define MIRC_LIGHTGREY     15
#define MIRC_LIGHTRED       4
#define MIRC_LIGHTGREEN     9
#define MIRC_LIGHTYELLOW    8
#define MIRC_LIGHTBLUE     12
#define MIRC_LIGHTMAGENTA  13
#define MIRC_LIGHTCYAN     11
#define MIRC_WHITE          0

size_t mirc_colors[16] = {
	[MIRC_BLACK]        =  0,
	[MIRC_RED]          =  1,
	[MIRC_GREEN]        =  2,
	[MIRC_YELLOW]       =  3,
	[MIRC_BLUE]         =  4,
	[MIRC_MAGENTA]      =  5,
	[MIRC_CYAN]         =  6,
	[MIRC_GREY]         =  7,
	[MIRC_LIGHTGREY]    =  8,
	[MIRC_LIGHTRED]     =  9,
	[MIRC_LIGHTGREEN]   = 10,
	[MIRC_LIGHTYELLOW]  = 11,
	[MIRC_LIGHTBLUE]    = 12,
	[MIRC_LIGHTMAGENTA] = 13,
	[MIRC_LIGHTCYAN]    = 14,
	[MIRC_WHITE]        = 15,
};

#endif
