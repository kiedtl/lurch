local M = {}

M.TB_KEY_F1               = (0xFFFF-0)
M.TB_KEY_F2               = (0xFFFF-1)
M.TB_KEY_F3               = (0xFFFF-2)
M.TB_KEY_F4               = (0xFFFF-3)
M.TB_KEY_F5               = (0xFFFF-4)
M.TB_KEY_F6               = (0xFFFF-5)
M.TB_KEY_F7               = (0xFFFF-6)
M.TB_KEY_F8               = (0xFFFF-7)
M.TB_KEY_F9               = (0xFFFF-8)
M.TB_KEY_F10              = (0xFFFF-9)
M.TB_KEY_F11              = (0xFFFF-10)
M.TB_KEY_F12              = (0xFFFF-11)
M.TB_KEY_INSERT           = (0xFFFF-12)
M.TB_KEY_DELETE           = (0xFFFF-13)
M.TB_KEY_HOME             = (0xFFFF-14)
M.TB_KEY_END              = (0xFFFF-15)
M.TB_KEY_PGUP             = (0xFFFF-16)
M.TB_KEY_PGDN             = (0xFFFF-17)
M.TB_KEY_ARROW_UP         = (0xFFFF-18)
M.TB_KEY_ARROW_DOWN       = (0xFFFF-19)
M.TB_KEY_ARROW_LEFT       = (0xFFFF-20)
M.TB_KEY_ARROW_RIGHT      = (0xFFFF-21)
M.TB_KEY_MOUSE_LEFT       = (0xFFFF-22)
M.TB_KEY_MOUSE_RIGHT      = (0xFFFF-23)
M.TB_KEY_MOUSE_MIDDLE     = (0xFFFF-24)
M.TB_KEY_MOUSE_RELEASE    = (0xFFFF-25)
M.TB_KEY_MOUSE_WHEEL_UP   = (0xFFFF-26)
M.TB_KEY_MOUSE_WHEEL_DOWN = (0xFFFF-27)

M.TB_KEY_CTRL_TILDE       = 0x00
M.TB_KEY_CTRL_2           = 0x00 -- clash with 'CTRL_TILDE'
M.TB_KEY_CTRL_A           = 0x01
M.TB_KEY_CTRL_B           = 0x02
M.TB_KEY_CTRL_C           = 0x03
M.TB_KEY_CTRL_D           = 0x04
M.TB_KEY_CTRL_E           = 0x05
M.TB_KEY_CTRL_F           = 0x06
M.TB_KEY_CTRL_G           = 0x07
M.TB_KEY_BACKSPACE        = 0x08
M.TB_KEY_CTRL_H           = 0x08 -- clash with 'CTRL_BACKSPACE'
M.TB_KEY_TAB              = 0x09
M.TB_KEY_CTRL_I           = 0x09 -- clash with 'TAB'
M.TB_KEY_CTRL_J           = 0x0A
M.TB_KEY_CTRL_K           = 0x0B
M.TB_KEY_CTRL_L           = 0x0C
M.TB_KEY_ENTER            = 0x0D
M.TB_KEY_CTRL_M           = 0x0D -- clash with 'ENTER'
M.TB_KEY_CTRL_N           = 0x0E
M.TB_KEY_CTRL_O           = 0x0F
M.TB_KEY_CTRL_P           = 0x10
M.TB_KEY_CTRL_Q           = 0x11
M.TB_KEY_CTRL_R           = 0x12
M.TB_KEY_CTRL_S           = 0x13
M.TB_KEY_CTRL_T           = 0x14
M.TB_KEY_CTRL_U           = 0x15
M.TB_KEY_CTRL_V           = 0x16
M.TB_KEY_CTRL_W           = 0x17
M.TB_KEY_CTRL_X           = 0x18
M.TB_KEY_CTRL_Y           = 0x19
M.TB_KEY_CTRL_Z           = 0x1A
M.TB_KEY_ESC              = 0x1B
M.TB_KEY_CTRL_LSQ_BRACKET = 0x1B -- clash with 'ESC'
M.TB_KEY_CTRL_3           = 0x1B -- clash with 'ESC'
M.TB_KEY_CTRL_4           = 0x1C
M.TB_KEY_CTRL_BACKSLASH   = 0x1C -- clash with 'CTRL_4'
M.TB_KEY_CTRL_5           = 0x1D
M.TB_KEY_CTRL_RSQ_BRACKET = 0x1D -- clash with 'CTRL_5'
M.TB_KEY_CTRL_6           = 0x1E
M.TB_KEY_CTRL_7           = 0x1F
M.TB_KEY_CTRL_SLASH       = 0x1F -- clash with 'CTRL_7'
M.TB_KEY_CTRL_UNDERSCORE  = 0x1F -- clash with 'CTRL_7'
M.TB_KEY_SPACE            = 0x20
M.TB_KEY_BACKSPACE2       = 0x7F
M.TB_KEY_CTRL_8           = 0x7F -- clash with 'BACKSPACE2'

M.TB_MOD_ALT    = 0x01
M.TB_MOD_MOTION = 0x02

M.TB_DEFAULT = 0x00
M.TB_BLACK   = 0x01
M.TB_RED     = 0x02
M.TB_GREEN   = 0x03
M.TB_YELLOW  = 0x04
M.TB_BLUE    = 0x05
M.TB_MAGENTA = 0x06
M.TB_CYAN    = 0x07
M.TB_WHITE   = 0x08

M.TB_BOLD      = 0x01000000
M.TB_UNDERLINE = 0x02000000
M.TB_REVERSE   = 0x04000000

M.TB_EVENT_KEY    = 1
M.TB_EVENT_RESIZE = 2
M.TB_EVENT_MOUSE  = 3

M.TB_EUNSUPPORTED_TERMINAL = -1
M.TB_EFAILED_TO_OPEN_TTY   = -2
M.TB_EPIPE_TRAP_ERROR      = -3

M.TB_HIDE_CURSOR = -1

M.TB_INPUT_CURRENT = 0
M.TB_INPUT_ESC     = 1
M.TB_INPUT_ALT     = 2
M.TB_INPUT_MOUSE   = 4

M.TB_OUTPUT_CURRENT   = 0
M.TB_OUTPUT_NORMAL    = 1
M.TB_OUTPUT_256       = 2
M.TB_OUTPUT_216       = 3
M.TB_OUTPUT_GRAYSCALE = 4
M.TB_OUTPUT_TRUECOLOR = 5

return M
