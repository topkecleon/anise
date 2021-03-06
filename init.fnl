;; anise/init.fnl
;; Utility functions for Fennel.

;; Copyright 2018 bb010g <bb010g@gmail.com>
;; This code is licensed under either of the MIT (/LICENSE-MIT) or Apache v2.0
;; (/LICENSE-APACHE) licenses, at your option.

(require-macros :anise.macros)
(require* anise.core)

(local anise {})
(core.merge_into anise core)

;; arrays

; (core.push arr ...)

; differs from table.pack by dropping nils
; (core.pack ...)

; drops nils in the tables being concatenated
; (core.pushcat arr ...)

; drops nils in the tables being concatenated
; (core.concat ...)

;; dictionary tables

; (core.clone t)

(define (anise.keys t)
  (each/array [k _ (pairs t)] k))

(define (anise.values t)
  (each/array [_ v (pairs t)] v))

(define (anise.dict_to_arr t)
  (each/array [k v (pairs t)] [k v]))

(define (anise.arr_to_dict assocs)
  (each/table [_ a (ipairs assocs)] [(. a 1) (. a 2)]))

(define (anise.dict_len t)
  (each/sum [_ _ (pairs t)] 1))

; (core.merge_into t ...)

; (core.merge ...)

;; iterators

(define (anise.collect_keys iter)
  (each/array [k _ iter] k))

(define (anise.collect_assocs iter)
  (each/array [k v iter] [k v]))

(define (anise.collect_table iter)
  (each/table [k v iter] [k v]))

(define (anise.collect_vals iter)
  (each/array [_ v iter] v))

;; math

(define (anise.clamp x min max)
  (math.max min (math.min x max)))

(define (anise.divmod x y)
  (local q (math.floor (/ x y)))
  (values q (- x (* y q))))

;; modules

; implementation based on lume.hotswap, licensed under MIT
; https://github.com/rxi/lume
(define (anise.hotswap modname)
  (local oldglobal (anise.clone _G))
  (local updated {})
  (define (update old new)
    (if (. updated old)
      (values)
      (let [oldmt (getmetatable old)
            newmt (getmetatable new)]
        (tset updated old true)
        (when (and oldmt newmt)
          (update oldmt newmt))
        (each [k v (pairs new)]
          (if (= (type v) :table)
            (update (. old k) v)
            (tset old k v))))))
  (var err nil)
  (define (onerror e)
    (each [k (pairs _G)]
      (tset _G k (. oldglobal k)))
    (set err (anise.trim e)))
  (var (ok oldmod) (pcall require modname))
  (set oldmod (and-or ok oldmod nil))
  (xpcall
    (fn []
      (tset package.loaded modname nil)
      (local newmod (require modname))
      (when (= (type oldmod) :table)
        (update oldmod newmod))
      (each [k v (pairs oldglobal)]
        (when (and (~= v (. _G k)) (= (type v) :table))
          (update v (. _G k))
          (tset _G k v))))
    onerror)
  (tset package.loaded modname oldmod)
  (if err (values nil err) oldmod))

;; strings

(define (anise.gfind str pattern init plain)
  (define (iter s i)
    (local (start end) (string.find s pattern i plain))
    (values end start))
  (values iter str 1))

(define (anise.pretty_float x)
  (if (= (% x 1) 0)
    (tostring (math.floor x))
    (tostring x)))

(define (anise.split_str s pat plain)
  (local pat (or pat (and-or plain "%s+" " ")))
  (var last_end 1)
  (local (arr i)
    (each/array [end start (anise.gfind s pat plain)]
      (set last_end end)
      (string.sub s last_end start)))
  (tset arr (+ 1 i) (string.sub last_end -1))
  arr)

(define (anise.trim s pat)
  (local pat (or pat "%s*"))
  (string.match s (f-str "^{pat}(.-){pat}$")))

(define (anise.trim_left s pat)
  (local pat (or pat "%s+"))
  (string.match s (f-str "^{pat}(.*)$")))

;; custom data structures

; data table

(let [dtm {}]
  (define (dtm.__index self key)
    (local data (rawget self :_data))
    (local val (. data key))
    (if data._parent
      (and val (setmetatable { :_data val :_key (rawget self :_key) } (getmetatable self)))
      (and val (. val (rawget self :_key)))))

  (define (dtm.__newindex self key value)
    (local data (rawget self :_data))
    (if data._parent
      (error (f-str "Can't set non-terminal key {} in a data_table" (tostring key)))
      (do
        (var t (. data key))
        (when (= t nil)
          (set t {})
          (tset data key t))
        (tset t (rawget self :_key) value)
        (values))))

  (define (dtm.__pairs self)
    (local data (rawget self :_data))
    (local iter
      (if data._parent
        (let [selfmeta (getmetatable self)]
          (fn [table index]
            (local (new_index val) (next table index))
            (if new_index
              (values new_index (setmetatable { :_data val :_key (rawget self :_key) } selfmeta))
              nil)))
        (fn [table index]
          (local (new_index val) (next table index))
          (if new_index
            (values new_index (. val (rawget self :_key)))
            nil))))
    (values iter data nil))

  (define (dtm.__ipairs self)
    (local data (rawget self :_data))
    (local iter
      (if data._parent
        (let [selfmeta (getmetatable self)]
          (fn [table i]
            (local i (+ 1 i))
            (local val (. table i))
            (if val
              (values i (setmetatable { :_data val :_key (rawget self :_key) } selfmeta))
              nil)))
        (fn [table i]
          (local i (+ 1 i))
          (local val (. table i))
          (if val
            (values i (. val (rawget self :_key)))
            nil))))
    (values iter data 0))

  (set anise.data_table_meta dtm))
(define (anise.data_table data key)
  (setmetatable { :_data data :_key key } anise.data_table_meta))

; sets

(let [sm {}]
  (define (sm.ref self k)
    (. (rawget self :data) k))

  (define (sm.add self k)
    (local data (rawget self :data))
    (when (not (. data k))
      (rawset self :count (+ (rawget self :count) 1))
      (tset data k true)))

  (define (sm.remove self k)
    (local data (rawget self :data))
    (when (. data k)
      (rawset self :count (- (rawget self :count) 1))
      (tset data k nil)))

  (define (sm.empty self)
    (= (rawget self :count) 0))

  (define (sm.__len self)
    (rawget self :count))

  (define (sm.__pairs self)
    (local data (rawget self :data))
    (local metamethod data.__pairs)
    (if metamethod
      (metamethod data)
      (values next data nil)))

  (set sm.__index sm)
  (set anise.set_meta sm))
(define (anise.set data)
  (setmetatable {
    :data (or data {})
    :count (and-or data (anise.dict_len data) 0)
  } anise.set_meta))

;; standard table library functions with return values

(define (anise.sort t f) (table.sort t f) t)
(define (anise.insert t a b) (table.insert t a b) t)
(define (anise.remove t i) (table.remove t i) t)

;; end

anise
