#!/usr/bin/env fennel

(local F (require :rt.fun))
(local floor math.floor)
(local fmt string.format)

(local chars (-?>> (F.t_range 62 32 -1)
                   (F.collect #(utf8.char $1))))

(fn clamp [v max min]
  (if (> v max) max (< v min) min v))
(macro sq [a] `(* ,a ,a))

(let [iters     10 output "ascii"
      width     24 height (- (/ width 2) 2)
      min-re -2.05 max-re 1.05  min-im -1.2
      max-im   1.1]
      ;min-re -0.756401399999999998687
      ;max-re -0.704449500000000000071
      ;min-im  0.193486000000000000000
      ;max-im  0.232525000000000000000
      ;min-re -0.739790393221044284614
      ;max-re -0.739789907192561065608
      ;min-im  0.174121309043763565755
      ;max-im  0.174121674900369065776]

  (local step-x (/ (- max-re min-re)  width))
  (local step-y (/ (- max-im min-im) height))

  (fn iter [n re im Z_re Z_im]
    (let [Z_re2 (sq Z_re) Z_im2 (sq Z_im)]
      (if (or (> (+ Z_re2 Z_im2) 4) (> n iters))
        n
        (iter (+ n 1) re im (- (+ Z_re2 re) Z_im2)
              (+ (* 2 Z_re Z_im) im)))))

  (fn pixel [x im]
    (let [re  (+ min-re (* step-x x))
          val (/ (iter 0 re im re im) iters)
          c (% (floor (* val 0xff)) 0xff)
          c2 (floor (/ c 1.2))]
      (if (= output "color")
        (fmt "\x1b[48;2;%d;%d;%dm \x1b[m" 0x00 c2 c)
        (. chars (clamp (floor (* val 31)) 31 1)))))

  (-?>> (F.t_range 1 height)
        (F.t_map (fn [y]
                   (var im (+ min-im (* step-y y)))
                   (-?>> (F.t_range 1 width)
                         (F.t_map #(pixel $1 im))
                         (F.foldl "" #(.. $1 $3)))))
        (F.t_map #(print $2))))
