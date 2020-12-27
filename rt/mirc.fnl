;; mIRC color sequences
;;
;; TODO: unit tests

(local format string.format)
(local F (require :fun))

(var M {})

(tset M :BOLD      "\x02")
(tset M :UNDERLINE "\x1f")
(tset M :ITALIC    "\x1d")
(tset M :INVERT    "\x16")
(tset M :BLINK     "\x06")
(tset M :RESET     "\x0f")
(tset M :COLOR     "\x03")

;; non-standard extension
(tset M :_256COLOR "\x04")

(tset M :BLACK         01)
(tset M :RED           05)
(tset M :GREEN         03)
(tset M :YELLOW        07)
(tset M :BLUE          02)
(tset M :MAGENTA       06)
(tset M :CYAN          10)
(tset M :GREY          14)
(tset M :LIGHTGREY     15)
(tset M :LIGHTRED      04)
(tset M :LIGHTGREEN    09)
(tset M :LIGHTYELLOW   08)
(tset M :LIGHTBLUE     12)
(tset M :LIGHTMAGENTA  13)
(tset M :LIGHTCYAN     11)
(tset M :WHITE         00)

(lambda M.bold [text]
  (.. (.. M.BOLD text) M.RESET))

(lambda M.remove [text]
  (var text text)
  (set text (text:gsub "[\x02\x1f\x1d\x16\x06\x0f]"  ""))
  (set text (text:gsub "\x03[0-9][0-9]?,[0-9][0-9]?" ""))
  (set text (text:gsub "\x03[0-9][0-9]?" ""))
  (set text (text:gsub "\x03" ""))
  (set text (text:gsub "\x04[0-9][0-9][0-9]" ""))
  text)

;; make IRC mirc sequences visible in text.
(lambda M.show [text]
  (var fmt {
    M.BOLD      :B
    M.UNDERLINE :U
    M.ITALIC    :I
    M.INVERT    :R
    M.BLINK     :F
    M.RESET     :O
    M.COLOR     :C
  })

  (var buf "")
  (-?> (F.iter text)
    (F.map (lambda [_ char]
      (if (. fmt char)
        (set buf (format "%s%s%s%s%s%s" buf M.RESET
          M.INVERT (. fmt char) M.RESET char))
        (set buf (.. buf char))))))

  buf)

M
