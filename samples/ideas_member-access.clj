;; ideas

(do
  ; (let p String.)
  ; (set #'p/count 1)
  ; (set #'p:count 1)
  ; (use p)
  ; (set #'count 1)
  ; (let x p:count)
  #_(setm #p
      :count 1
      _ (do
          (let xy (blah count))
          (let abc (calc xy)))
      :data (get-ptr abc))
  #_(setm #p
      [:count 1]
      (let xy (blah &:count))
      (let abc (calc xy))
      [:data (get-ptr abc)])
  (let x (cast *u8 (allocate 16)))
  ; (set x 0)
  ; (set (+ x 1) 0)
  x)



;; seems too rigid having this nested if
;; initialising multiple things together
(let colour Colour
  ..init
  (set &*red 0)
  (do blah with &:red)
  (set &*green 0))


(do (use-refs colour)
  (set *red 0))


;; what if 'let' implicitly defines the mutable reference?
(let colour Colour.)
*colour ;; mutable view of colour
;; if the ref's members match the underlying type:
(set *colour:red 0)
;; perhaps have separate accessor instead
;; so you can talk about the members of the ref itself
(set *colour/red 0)
*colour:refmember
;; but remember pointers don't have members, accesses reach
;; through the pointer. But pointers are a type of ref.
;; so maybe instead the above, use functions to access
;; data specific to the ref:
(.refmember *colour)

;; ..but accessing a pointer member corresponds to dereferencing
;; the pointer and accessing the member of the dereferenced
;; data. What we want is a cursor to the member of the underlying
;; data, so a separate accessor does have a place.
(= *colour:red colour:red)
(set *colour/red-val 0) (use-refs *colour)
(set *colour:red-ptr red) (use *colour)
;; the slash indicates you are not actually accessing the
;; data, just getting a reference to the path
;; alternative syntax:
*colour:red ;; ref
*colour.red ;; value
;; namespaced keyword access
*colour:myns/red
*colour.myns/red
;; but / seems stronger than '.', so what about:
*colour/myns.red
*colour:myns.red
;; or
*colour/myns~red
*colour:myns~red
*colour/myns'red
*colour:myns'red

;; or maybe it would be hard to switch between the two modes,
;; so maybe just have the reference syntax and dereference it?
@*colour/red or *colour/red@

;; perhaps a reference to a local is its own struct thing
(:type #'colour) #'colour:type

;; convenient indexing
colours:2 (:2 colours)



;; integer
(let x 5)
;; use integer
x
;; set integer local
(set *x 0)

;; integer pointer
(let x (new int))
;; use integer pointer
x ;; *int
;; deref integer pointer
@x ;; int
;; set integer pointer
(set *x (new int)) ;; **int *int
;; set integer at pointer
(set x 0) ;; *int int

;; struct
(let p Point.)
;; use struct
p ;; Point
;; use struct member
p:x ;; Point->int
*p:x ;; (*Point)-@>int
;; set struct local
(set *p p2) ;; *Point Point
;; set struct local member
(set *p/x 0) ;; (*Point)->*int, int

;; struct pointer
(let p (new Point))
;; use struct
@p ;; Point
;; use struct member
p:x ;; (*Point)-@>int
;; set struct at pointer
(set p p2) ;; *Point Point
;; set struct member
(set p/x 0) ;; (*Point)->*int, int

;; VERSION 2

;; struct
(let p Point.)
;; use struct
p ;; Point
;; use struct member
@*p:x ;; (*Point)->*int-@>int
;; set struct local
(set *p p2) ;; *Point Point
;; set struct local member
(set *p:x 0) ;; (*Point)->*int, int

;; struct pointer
(let p (new Point))
;; use struct
@p ;; Point
;; use struct member
@p:x ;; (*Point)->*int-@>int
;; set struct at pointer
(set p p2) ;; *Point Point
;; set struct member
(set p:x 0) ;; (*Point)->*int, int

;; VERSION 3 - name to indicate data, implicit deref

;; struct
(let p Point.)
;; use struct
p ;; Point
;; use struct member
p:x ;; Point->int
; *p:x ;; (*Point)-@>int
;; set struct local
(set *p p2) ;; *Point Point
;; set struct local member
(set *p:x 0) ;; (*Point)->*int, int

;; struct pointer
(let *p (new Point))
;; use struct
p ;; Point
;; use struct member
p:x ;; (*Point)-@>int
;; set struct at pointer
(set *p p2) ;; *Point Point
;; set struct member
(set *p:x 0) ;; (*Point)->*int, int
;; set struct pointer
(set **p (new Point))

;; struct member which is a pointer (y: *int)
;; use pointer
p:*y ;; Point->*int
;; set pointer
(set *p:y (new int))
;; use value
p:y ;; Point->*int-@>int
;; set value
(set p:*y 0) ;; Point->*int

;; pointer arithmetic
(set (+ *p 1) p2)

;; VERSION 4 - clojure edition

;; struct
(let p Point.)
;; use struct
p ;; Point
;; use struct member
p:x ;; Point->int
;; set struct local
(set #'p p2) ;; *Point Point
;; set struct local member
(setf #'p :x 0)
(set #'p:x 0)

;; struct pointer
(let *p (new Point))
;; use struct
@*p ;; Point
;; use struct member
*p@:x
(:x @*p)
@*p:x
;; set struct at pointer
(set *p p2) ;; *Point Point
;; set struct member
(setf *p :x 0)
(set *p:x 0)
;; set struct pointer
(set #'*p (new Point))

;; struct member which is a pointer (y: *int)
;; use pointer
p:*y ;; Point->*int
(:*y @*p) ;; *Point->*int
;; set pointer
(set p:*y (new int))
(set (:*y @*p) (new int))
;; use value
@p:*y ;; Point->*int-@>int
@(:*y @*p) ;; *Point->*int-@>int
;; set value
(set p:*y 0) ;; Point->*int
(set (:*y @*p) 0) ;; Point->*int

;; pointer arithmetic
(set (+ *p 1) p2)

;; pointer struct member which is a pointer to a struct
;; *Shape{pos: *Point{x: int}}
(let s (new Shape))
;; get x value
(:x @(:pos @s))
@s:pos:x
@(:x (:pos s))
;; note that this will involve an implicit deref/read
;; of the s pointer
(set s:pos:x 0)

;; maybe if pointer is declared stable, implicit derefs
;; that may be optimised by the compiler.
;; so it can be treated like data.
(let si (as-immutable s))
s:pos:x ;; int

;; each dereference was explicit, but in clojure
;; there are certain implicit dereferences (for vars)
;; as var root bindings are assumed to be stable
;; and are rebound on *per-thread* basis.

;; maybe we want to assume most code will be operating
;; on thread-owned data and then we could have special
;; facilities for accessing and setting data that is
;; declared for use by multiple threads.


;; the generalisation of reaching through pointers
;; is simply auto-dereffing to match the destination type.
;; function parameters can be treated as 'by-value'
;; where if any pointer is provided at the call site, 
;; it can be implicitly dereffed, assuming the pointer
;; is thread-owned. If the struct type is large enough,
;; this pointer is given to the function and since parameters
;; are immutable, the original data is guaranteed to be
;; unchanged, yet it can still be directly accessed
;; by the function in a 'by value' way.



