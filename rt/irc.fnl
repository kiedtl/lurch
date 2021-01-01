(local F (require :fun))
(local util (require :util))

(var M {})
(tset M :_handlers {})

; Bookkeeping
(tset M :server {})
(tset M :server :connected (os.time))  ; last time we tried to connect
(tset M :server :caps {:all {}         ; IRCv3 caps the server ack'd/nak'd
                       :requested {}}) ; IRCv3 caps we'd requested

(lambda M.connect [host port tls nick user name ?pass ?caps ?no_ident?]
  (tset M :server :connected (os.time))
  (var (success err) (lurch.conn_init host port tls))

  (when success
    ; list and request IRCv3 capabilities. The responses are ignored
    ; for now; they will be processed later on.
    (when ?caps
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
; example IRC message:
; @time=2020-09-07T01:14:11Z :onisamot!~onisamot@reghog.pink PRIVMSG #meat :ahah
; ^------------------------- ^------------------------------ ^------ ^---- ^----
; IRCv3 tags                 sender                          command arg   msg
;
(lambda M.parse [rawmsg]
  (var rawmsg rawmsg)
  (var event {})

  ; Remove the trailing \r\n from the raw message.
  (set rawmsg (rawmsg:gsub "\r\n$" ""))
  (if (not rawmsg) (return nil))

  (tset event :tags {})
  (when (= (rawmsg:match :.) "@")
    ; grab everything until the next space
    (local tags (rawmsg:match "@(.-)%s"))
    (assert tags)

    (-?>> [(tags:gmatch "([^;]+);?")]
          (F.map (lambda [tag]
            ; the tag may or may not have a value...
            (let [key (tag:match "([^=]+)=?")
                  val (or (tag:match "[^=]+=([^;]+);?") "")]
              (tset event :tags key val)))))

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
  (var (data msg _) (rawmsg:match "([^:]+):?(.*)([%s]*)"))
  (tset event :msg (or msg ""))

  (tset event :fields
    (-?>> [(data:gmatch "([^%s]+)%s?")] (F.collect #$)))

  ; if the message contains no whitespace, add it to the fields.
  (when (not (msg:find :%s))
    (tset event :fields (+ (length event.fields) 1) msg))

  (tset event :dest (. event.fields 2))

  ; If the field after the typical dest is a channel, use it in
  ; place of the regular field. This correctly catches MOTD, JOIN,
  ; and NAMES messages.
  (when (and (. event.fields 3) (not (event.dest:find "^#")))
    (if (string.find (. event.fields 3) "^[*#]")
      (tset event :dest (. event.fields 3))
      (string.find (. event.fields 3) "^[@=]")
      (tset event :dest (. event.fields 4))))

  ; If the message itself contains text with surrounding '\x01',
  ; we're dealing with CTCP. Simply set the type to that text so
  ; we may specially deal with it later.
  ;
  ; prepend CTCP_ to the command to distinguish it from other
  ; non-CTCP commands (e.g. PING vs CTCP PING)
  (when (string.find event.msg "\1[A-Z]+%s?([^\1]*)\1")
    (tset event :fields 1 (string.match event.msg "\1([A-Z]+)%s?"))
    (tset event :fields 1 (.. "CTCP_" (. event.fields 1)))
    (tset event :msg (string.gsub event.msg "\1[A-Z]+%s?" ""))
    (tset event :msg (string.gsub event.msg "\1" "")))

  event)

(lambda M.send [fmt ...]
  (let [(r e) (lurch.conn_send (fmt:format ...))]
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
