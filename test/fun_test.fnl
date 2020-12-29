; TODO: more comprehensive tests

(local inspect    (require :inspect))
(local F          (require :fun))
(local util       (require :util))
(local lunatest   (. package :loaded :lunatest))
(local assert_eq  (. lunatest :assert_equal))
(local assert_ye  (. lunatest :assert_true))
(local assert_no  (. lunatest :assert_false))

(var M {})

(local _assert_table_eq (lambda [a b]
  (assert_ye (util.table_eq a b))))
(local _assert_table_neq (lambda [a b]
  (assert_no (util.table_eq a b))))

; This tests collect as well as iter
(lambda M.test_iter []
  (let [tbl1 [:H :a :l :p :m :e]
        tbl2 {:L "o" :r "e" :m "I"}]
    (_assert_table_eq
      (-?>> [(F.iter :HelloWorld)] (F.collect #$2))
      [:H :e :l :l :o :W :o :r :l :d])

    (_assert_table_eq
      (-?>> [(F.iter tbl1)] (F.collect #$2)) tbl1)

    (_assert_table_eq
      (-?>> [(F.iter tbl2)]
            (F.foldl {} #(do (tset $1 $2 $3) $1)))
      tbl2)))

(lambda M.test_range []
  (_assert_table_eq
    (-?>> [(F.range 0 7)] (F.collect #$1))
    [0 1 2 3 4 5 6 7])
  (_assert_table_eq
    (-?>> [(F.range 7 0 -1)] (F.collect #$1))
    [7 6 5 4 3 2 1 0])
  (_assert_table_eq
    (-?>> [(F.range -7 0)] (F.collect #$1))
    [-7 -6 -5 -4 -3 -2 -1 0])
  (_assert_table_eq
    (-?>> [(F.range -7 -14 -1)] (F.collect #$1))
    [-7 -8 -9 -10 -11 -12 -13 -14])
  (_assert_table_eq
    (-?>> [(F.range 0 7 3)] (F.collect #$1))
    [0 3 6]))

(lambda M.test_foldl []
  (assert_eq (-?>> [(F.range 0 7)] (F.foldl 0 #(+ $1 $2))) 28)
  (assert_eq (-?>> [(F.range 1 7)] (F.foldl 1 #(* $1 $2))) 5040))

(lambda M.test_map []
  (_assert_table_eq
    (-?>> (F.t_range 0 7) (F.t_map #(+ $1 1)) (F.collect #$))
    [1 2 3 4 5 6 7 8]))
M
