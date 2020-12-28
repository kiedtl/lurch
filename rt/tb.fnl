;
; Termbox constants.
;
; Used by the termbox readline code.
;

(var M {})

(tset M TB_KEY_F1                (- 0xFFFF  0))
(tset M TB_KEY_F2                (- 0xFFFF  1))
(tset M TB_KEY_F3                (- 0xFFFF  2))
(tset M TB_KEY_F4                (- 0xFFFF  3))
(tset M TB_KEY_F5                (- 0xFFFF  4))
(tset M TB_KEY_F6                (- 0xFFFF  5))
(tset M TB_KEY_F7                (- 0xFFFF  6))
(tset M TB_KEY_F8                (- 0xFFFF  7))
(tset M TB_KEY_F9                (- 0xFFFF  8))
(tset M TB_KEY_F10               (- 0xFFFF  9))
(tset M TB_KEY_F11               (- 0xFFFF 10))
(tset M TB_KEY_F12               (- 0xFFFF 11))
(tset M TB_KEY_INSERT            (- 0xFFFF 12))
(tset M TB_KEY_DELETE            (- 0xFFFF 13))
(tset M TB_KEY_HOME              (- 0xFFFF 14))
(tset M TB_KEY_END               (- 0xFFFF 15))
(tset M TB_KEY_PGUP              (- 0xFFFF 16))
(tset M TB_KEY_PGDN              (- 0xFFFF 17))
(tset M TB_KEY_ARROW_UP          (- 0xFFFF 18))
(tset M TB_KEY_ARROW_DOWN        (- 0xFFFF 19))
(tset M TB_KEY_ARROW_LEFT        (- 0xFFFF 20))
(tset M TB_KEY_ARROW_RIGHT       (- 0xFFFF 21))
(tset M TB_KEY_MOUSE_LEFT        (- 0xFFFF 22))
(tset M TB_KEY_MOUSE_RIGHT       (- 0xFFFF 23))
(tset M TB_KEY_MOUSE_MIDDLE      (- 0xFFFF 24))
(tset M TB_KEY_MOUSE_RELEASE     (- 0xFFFF 25))
(tset M TB_KEY_MOUSE_WHEEL_UP    (- 0xFFFF 26))
(tset M TB_KEY_MOUSE_WHEEL_DOWN  (- 0xFFFF 27))

(tset M TB_KEY_CTRL_TILDE                 0x00)
(tset M TB_KEY_CTRL_2                     0x00) ; clash with 'CTRL_TILDE'
(tset M TB_KEY_CTRL_A                     0x01)
(tset M TB_KEY_CTRL_B                     0x02)
(tset M TB_KEY_CTRL_C                     0x03)
(tset M TB_KEY_CTRL_D                     0x04)
(tset M TB_KEY_CTRL_E                     0x05)
(tset M TB_KEY_CTRL_F                     0x06)
(tset M TB_KEY_CTRL_G                     0x07)
(tset M TB_KEY_BACKSPACE                  0x08)
(tset M TB_KEY_CTRL_H                     0x08) ; clash with 'CTRL_BACKSPACE'
(tset M TB_KEY_TAB                        0x09)
(tset M TB_KEY_CTRL_I                     0x09) ; clash with 'TAB'
(tset M TB_KEY_CTRL_J                     0x0A)
(tset M TB_KEY_CTRL_K                     0x0B)
(tset M TB_KEY_CTRL_L                     0x0C)
(tset M TB_KEY_ENTER                      0x0D)
(tset M TB_KEY_CTRL_M                     0x0D) ; clash with 'ENTER'
(tset M TB_KEY_CTRL_N                     0x0E)
(tset M TB_KEY_CTRL_O                     0x0F)
(tset M TB_KEY_CTRL_P                     0x10)
(tset M TB_KEY_CTRL_Q                     0x11)
(tset M TB_KEY_CTRL_R                     0x12)
(tset M TB_KEY_CTRL_S                     0x13)
(tset M TB_KEY_CTRL_T                     0x14)
(tset M TB_KEY_CTRL_U                     0x15)
(tset M TB_KEY_CTRL_V                     0x16)
(tset M TB_KEY_CTRL_W                     0x17)
(tset M TB_KEY_CTRL_X                     0x18)
(tset M TB_KEY_CTRL_Y                     0x19)
(tset M TB_KEY_CTRL_Z                     0x1A)
(tset M TB_KEY_ESC                        0x1B)
(tset M TB_KEY_CTRL_LSQ_BRACKET           0x1B) ; clash with 'ESC'
(tset M TB_KEY_CTRL_3                     0x1B) ; clash with 'ESC'
(tset M TB_KEY_CTRL_4                     0x1C)
(tset M TB_KEY_CTRL_BACKSLASH             0x1C) ; clash with 'CTRL_4'
(tset M TB_KEY_CTRL_5                     0x1D)
(tset M TB_KEY_CTRL_RSQ_BRACKET           0x1D) ; clash with 'CTRL_5'
(tset M TB_KEY_CTRL_6                     0x1E)
(tset M TB_KEY_CTRL_7                     0x1F)
(tset M TB_KEY_CTRL_SLASH                 0x1F) ; clash with 'CTRL_7'
(tset M TB_KEY_CTRL_UNDERSCORE            0x1F) ; clash with 'CTRL_7'
(tset M TB_KEY_SPACE                      0x20)
(tset M TB_KEY_BACKSPACE2                 0x7F)
(tset M TB_KEY_CTRL_8                     0x7F) ; clash with 'BACKSPACE2'

(tset M TB_MOD_ALT                        0x01)
(tset M TB_MOD_MOTION                     0x02)

(tset M TB_DEFAULT                        0x00)
(tset M TB_BLACK                          0x01)
(tset M TB_RED                            0x02)
(tset M TB_GREEN                          0x03)
(tset M TB_YELLOW                         0x04)
(tset M TB_BLUE                           0x05)
(tset M TB_MAGENTA                        0x06)
(tset M TB_CYAN                           0x07)
(tset M TB_WHITE                          0x08)

(tset M TB_BOLD                     0x01000000)
(tset M TB_UNDERLINE                0x02000000)
(tset M TB_REVERSE                  0x04000000)

(tset M TB_EVENT_KEY                         1)
(tset M TB_EVENT_RESIZE                      2)
(tset M TB_EVENT_MOUSE                       3)

(tset M TB_EUNSUPPORTED_TERMINAL            -1)
(tset M TB_EFAILED_TO_OPEN_TTY              -2)
(tset M TB_EPIPE_TRAP_ERROR                 -3)

(tset M TB_HIDE_CURSOR                      -1)

(tset M TB_INPUT_CURRENT                     0)
(tset M TB_INPUT_ESC                         1)
(tset M TB_INPUT_ALT                         2)
(tset M TB_INPUT_MOUSE                       4)

(tset M TB_OUTPUT_CURRENT                    0)
(tset M TB_OUTPUT_NORMAL                     1)
(tset M TB_OUTPUT_256                        2)
(tset M TB_OUTPUT_216                        3)
(tset M TB_OUTPUT_GRAYSCALE                  4)
(tset M TB_OUTPUT_TRUECOLOR                  5)

M
