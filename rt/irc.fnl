(local F (require :fun))
(local format string.format)
(local lurchconn (require :lurchconn))
(local util (require :util))

(var M {})
(tset M :_handlers {})

; Bookkeeping
(tset M :server {})
(tset M :server :connected (os.time))  ; last time we tried to connect
(tset M :server :caps {:all {}         ; IRCv3 caps the server ack'd/nak'd
                       :requested []}) ; IRCv3 caps we'd requested

; Strip "|<client>", trailing underscores, and the Matrix "marker"
; from nicknames
;
; "hkxumk|weechat" => "hkxumk"; "josh_" => "josh"; "jayd[m]" => "jay"
;
; (XXX: This isn't foolproof: "__attribute__" => "__attribute" :/)
(lambda M.normalise_nick [nick]
  (var nick nick)
  (if (nick:match "[^|]+|..+$")
    (set nick (nick:gsub "|.+$" "")))
  (if (nick:match "[^_]+_+$")
    (set nick (nick:gsub "_+$" "")))
  (if (nick:match ".-%[m%]$")
    (set nick (nick:gsub "%[m%]$" "")))
  nick)

(lambda M.connect [host port tls nick user name ?pass ?caps ?no_ident?]
  (tset M :server :connected (os.time))
  (var (success err) (lurchconn.init host port tls))

  (when success
    ; list and request IRCv3 capabilities. The responses are ignored
    ; for now; they will be processed later on.
    (when ?caps
      (tset M :server :caps :requested ?caps)
      (M.send "CAP LS")
      (-?>> [(F.iter ?caps)]
            (F.map #(M.send "CAP REQ :%s" $2)))
      (M.send "CAP END"))

    ; FIXME: ...are there servers that close the connection before
    ; 10 seconds? th eones I know close only after 10 seconds
    ; TODO: file that InspirCD bug and remove this code.
    (when ?no_ident? (util.sleep 9))

    ; send PASS before NICK/USER, as when USER+NICK is sent the
    ; user is registered and our chance to send the password is gone.
    (when ?pass (M.send "PASS :%s" ?pass))

    (M.send "USER %s localhost * :%s" user name)
    (M.send "NICK :%s" nick))

  (values success err))

;
; ported from the parse() function in https://github.com/dylanaraps/birch
;
; the following IRC message:
; @time=2020-09-07T01:14:11Z :onisamot!~onisamot@reghog.pink PRIVMSG #meat :ahah
; ^------------------------- ^------------------------------ ^------ ^---- ^----
; IRCv3 tags                 sender                          command arg   msg
;
; parses to:
; {
;      fields = { "PRIVMSG", "#meat" },
;      from = "onisamot!~onisamot@reghog.pink",
;      dest = "#meat", msg = "ahah",
;      host = "reghog.pink",
;      nick = "onisamot", user = "~onisamot",
;      tagn = 1, tags = {
;          time = "2020-09-07T01:14:11Z"
;      }
; }
;
(lambda M.parse [rawmsg]
  (var rawmsg rawmsg)
  (var event {})

  ; Remove the trailing \r\n from the raw message.
  (set rawmsg (rawmsg:gsub "\r\n$" ""))
  (if (not rawmsg) (return nil))

  (tset event :tags {})
  (tset event :tagn  0)
  (when (= (rawmsg:match :.) "@")
    ; grab everything until the next space
    (local tags (rawmsg:match "@(.-)%s"))
    (assert tags)

    (-?>> [(tags:gmatch "([^;]+);?")]
          (F.map (fn [tag]
            (let [key (tag:match "([^=]+)=?")
                  val (or (tag:match "[^=]+=([^;]+);?") "")]
              (tset event :tags key val)
              (tset event :tagn (+ event.tagn 1))))))

    ; since the first word and only the first word can be
    ; an IRC tag(s), we can just strip off the first word to
    ; remove the processed tags.
    (set rawmsg (rawmsg:match ".-%s(.+)")))

  ; the message had better not be all tags...
  (assert rawmsg)

  ; if the next word in the raw IRC message contains ':', '@',
  ; or '!', split it and grab the sender.
  (when (string.find (rawmsg:match "([^%s]+)%s?") "[:@!]")
    ; There are two types of senders: the server, or a user.
    ; The 'server' format is just :<server>, but the 'user' format
    ; is a bit more complicated: :<nick>!<user>@<host>
    (tset event :from (rawmsg:match ":?(.-)%s"))

    (if (rawmsg:find "[!@]")
      (do
        (tset event :nick (string.match event.from "(.-)!.-@.+"))
        (tset event :user (string.match event.from ".-!(.-)@.+"))
        (tset event :host (string.match event.from ".-!.-@(.+)")))
      (tset event :host event.from))

    ; strip out what was already processed
    (set rawmsg (rawmsg:gsub "^.-%s" "" 1)))

  ; Grab all the stuff before the next ':' and stuff it into
  ; a table for later. Anything after the ':' is the message.
  ;
  ; NOTE: the colon must be preceded by a space, as fields are
  ; allowed to have a ':' in them. (e.g. 314, MODE, etc)
  ;
  (var (data msg lastch) (values "" "" ""))
  (each [i char (F.iter rawmsg)]
    (if (or (not= char ":") (not= lastch " "))
      (set data (.. data char))
      (do
        (set msg (rawmsg:sub (+ i 1) (length rawmsg)))
        (lua :break))) ; yuck
    (set lastch char))
  (tset event :msg (or (msg:gsub "%s*$" "") ""))

  (assert data "IRC event fields == nil")
  (tset event :fields
    (-?>> [(data:gmatch "([^%s]+)%s?")] (F.collect #$)))

  (tset event :dest (. event.fields 2))

  ; If the field after the typical dest is a channel, use it in
  ; place of the regular field. This correctly catches MOTD, JOIN,
  ; and NAMES messages.
  (when (and (. event.fields 3) (not (event.dest:find "^#")))
    (if (string.find (. event.fields 3) "^[*#]")
      (tset event :dest (. event.fields 3))
      (string.find (. event.fields 3) "^[@=]")
      (tset event :dest (. event.fields 4))))

  ; If there is no dest, check if the message is a channel; if so,
  ; use that as the message.
  (when (and (not event.dest) (string.match event.msg "^#"))
    (tset event :dest event.msg))

  ; If the message itself contains text with surrounding '\x01',
  ; we're dealing with CTCP. Simply set the type to that text so
  ; we may specially deal with it later.
  ;
  ; prepend CTCP_ to the command to distinguish it from other
  ; non-CTCP commands (e.g. PING vs CTCP PING)
  (when (string.find event.msg "\1[A-Z]+%s?([^\1]*)\1")
    (let [ctcptype (string.match event.msg "\1([A-Z]+)%s?")]
      (if
        (= (. event :fields 1) :PRIVMSG)
        (tset event :fields 1 (.. "CTCPQ_" ctcptype))
        (= (. event :fields 1) :NOTICE)
        (tset event :fields 1 (.. "CTCPR_" ctcptype))))
    (tset event :msg (string.gsub event.msg "\1[A-Z]+%s?" ""))
    (tset event :msg (string.gsub event.msg "\1" "")))

  event)

(lambda M.construct [event]
  (var buf "")
  (when (> event.tagn 0)
    (set buf "@")
    (each [tag_k tag_v (pairs event.tags)]
      (if (not= buf "@")
        (set buf (.. buf ";")))
      (if tag_v
        (set buf (format "%s%s=%s" buf tag_k tag_v))
        (set buf (format "%s%s" buf tag_k))))
    (set buf (.. buf " ")))

  (when event.from
    (set buf (.. buf ":" event.from " ")))

  (when
    (string.match (. event.fields 1) "^CTCP[QR]_")
    (let [ctcp (string.gsub (. event.fields 1) "CTCP[QR]_" "")]
      (tset event :fields 1 :PRIVMSG)
      (if (not= event.msg "")
        (tset event :msg (format "\1%s %s\1" ctcp event.msg))
        (tset event :msg (format "\1%s\1" ctcp)))))

  (each [_ field (ipairs event.fields)]
    (set buf (.. buf field " ")))

  (when event.msg
    (set buf (.. buf ":" event.msg)))
  buf)

(lambda M.send [fmt ...]
  (let [(r e) (lurchconn.send (fmt:format ...))]
        (when (not r)
          (util.panic "error: %s\n" e))))

; ---

(fn M._handlers.CAP [e]
  (let [subcmd (string.lower (. e :fields 3))
        msg    (string.match (. e :msg) "(.-)%s*$")] ; remove trailing whitespace
    (if (= subcmd :ls)
      ; the server is listing capabilities they support.
      (-?>> [(msg:gmatch "([^%s]+)%s?")]
            (F.t_map #(tset M :server :caps $1 false)))
      (= subcmd :ack) ; the server supports a capability we requested.
      (tset M :server :caps msg true)
      (= subcmd :nak) ; the server doesn't support a requested capability.
      (tset M :server :caps msg false))))

; ---

(lambda M.handle [event]
  (let [hnd (. M :_handlers (. event :fields 1))]
    (when hnd (hnd event))))

M
