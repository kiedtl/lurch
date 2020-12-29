#!/usr/bin/env fennel

(local F (require :rt.fun))

(fn clamp [v max min]
  (if (> v max) max (< v min) min v))
(macro sq [a] `(* ,a ,a))

(let [width     72  height (/ width 2.20952)
      min-re -2.05  max-re 1.05  min-im -1.1
      max-im  1.10  iters  128]

  (local step-x (/ (- max-re min-re)  width))
  (local step-y (/ (- max-im min-im) height))

  (fn col [imag x y]
    (var real (+ min-re (* step-x x)))

    (fn iter [n Z_re Z_im]
      (let [Z_re2 (sq Z_re) Z_im2 (sq Z_im)]
        (if (or (> (+ Z_re2 Z_im2) 4) (> n iters))
          n
          (iter (+ n 1) (- (+ Z_re2 real) Z_im2)
                (+ (* 2 Z_re Z_im) imag)))))

    (clamp (- 62 (iter 0 real imag)) 62 32))

  (fn pixel [imag x y] (utf8.char (col imag x y)))

  (-?>> (F.t_range 0 height)
        (F.t_map (fn [y]
                   (var R_im (+ min-im (* step-y y)))
                   (-?>> (F.t_range 0 width)
                         (F.t_map #(pixel R_im $1 y))
                         (F.foldl "" #(.. $1 $3)))))
        (F.t_map #(print $2))))
