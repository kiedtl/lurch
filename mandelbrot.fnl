#!/usr/bin/env fennel

(local F (require :rt.fun))
(local floor math.floor)

(local chars (-?>> (F.t_range 62 32 -1)
                   (F.collect #(utf8.char $1))))

(fn clamp [v max min]
  (if (> v max) max (< v min) min v))
(macro sq [a] `(* ,a ,a))

(let [width      24 height (- (/ width 2) 2)
      ;min-re -2.05 max-re 1.05  min-im -1.2
      ;max-im   1.1 iters  64]
      ;min-re -0.756401399999999998687
      ;max-re -0.704449500000000000071
      ;min-im  0.193486000000000000000
      ;max-im  0.232525000000000000000
      min-re -0.739790393221044284614
      max-re -0.739789907192561065608
      min-im  0.174121309043763565755
      max-im  0.174121674900369065776
      iters   1024]

  (local step-x (/ (- max-re min-re)  width))
  (local step-y (/ (- max-im min-im) height))

  (fn mandel [imag x y]
    (local real (+ min-re (* step-x x)))
    (fn iter [n Z_re Z_im]
      (let [Z_re2 (sq Z_re) Z_im2 (sq Z_im)]
        (if (or (> (+ Z_re2 Z_im2) 4) (> n iters))
          n
          (iter (+ n 1) (- (+ Z_re2 real) Z_im2)
                (+ (* 2 Z_re Z_im) imag)))))
    (iter 0 real imag))

  (fn trmcolor [imag x y]
    (let [c (% (floor (* (/ (mandel imag x y) iters) 0xff)) 0xff)
          c2 (floor (/ c 1.2))]
      (string.format "\x1b[48;2;%d;%d;%dm \x1b[m" 0x00 c2 c)))

  (fn ascii [imag x y]
    (let [val (* (/ (mandel imag x y) iters) 31)]
      (. chars (clamp (floor val) 31 1))))

  (-?>> (F.t_range 1 height)
        (F.t_map (fn [y]
                   (var R_im (+ min-im (* step-y y)))
                   (-?>> (F.t_range 1 width)
                         (F.t_map #(ascii R_im $1 y))
                         (F.foldl "" #(.. $1 $3)))))
        (F.t_map #(print $2))))
