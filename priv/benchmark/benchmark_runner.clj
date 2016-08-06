(ns benchmark.benchmark-runner
  (:refer-clojure :exclude [println]))

(def n 10000)
;;(def println print)

(simple-benchmark [x 1] (identity x) n)

(println ";; symbol construction")
(simple-benchmark [] (symbol 'foo) n)
(println)

(println ";;; instance?")
(simple-benchmark [coll []] (instance? :clojerl.Vector coll) n)
(println ";;; extends?")
(simple-benchmark [coll (list 1 2 3)] (extends? :clojerl.ISeq coll) n)
(simple-benchmark [coll [1 2 3]] (extends? :clojerl.ISeq coll) n)
(println)

(println ";;; string ops")
;;(simple-benchmark [coll (array 1 2 3)] (seq coll) 1000000)
(simple-benchmark [coll "foobar"] (seq coll) n)
;;(simple-benchmark [coll (array 1 2 3)] (first coll) 1000000)
(simple-benchmark [coll "foobar"] (first coll) n)
;;(simple-benchmark [coll (array 1 2 3)] (nth coll 2) 1000000)
(simple-benchmark [coll "foobar"] (nth coll 2) n)
(println)

(println ";;; list ops")
(simple-benchmark [coll (list 1 2 3)] (first coll) n)
(simple-benchmark [coll (list 1 2 3)] (rest coll) n)
(simple-benchmark [] (list) n)
(simple-benchmark [] (list 1 2 3) n)
(println)

(println ";;; vector ops")
(simple-benchmark [] [] n)
(simple-benchmark [[a b c] (take 3 (repeatedly #(rand-int 10)))] (count [a b c]) n)
(simple-benchmark [[a b c] (take 3 (repeatedly #(rand-int 10)))] (count (vec [a b c])) n)
(simple-benchmark [[a b c] (take 3 (repeatedly #(rand-int 10)))] (count (vector a b c)) n)
(simple-benchmark [coll [1 2 3]] (nth coll 0) n)
(simple-benchmark [coll [1 2 3]] (coll 0) n)
(simple-benchmark [coll [1 2 3]] (conj coll 4) n)
(simple-benchmark [coll [1 2 3]] (seq coll) n)
(simple-benchmark [coll (seq [1 2 3])] (first coll) n)
(simple-benchmark [coll (seq [1 2 3])] (rest coll) n)
(simple-benchmark [coll (seq [1 2 3])] (next coll) n)
(println)