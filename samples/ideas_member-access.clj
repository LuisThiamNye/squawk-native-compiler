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
(set *p:y (new int)) ;; (*Point)->(**int)
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








;; if member x is int
point/a/b/c/x ;; int
;; to get a pointer to the x member in its parent struct:
point/a/b/c/'x ;; *int
;; Q: what if point is a non-pointer local?

;; but what if x is changed from int to *int?
;; the consumer code only wants the int but we
;; do not want to change the code.
;; Constraint: assume names are coupled to a specific type;
;; a change of type warrants a change of name.
;; (Considering that because '/' is auto-dereffing, whether struct
;; members higher up in the access hierarchy can be changed between
;; value and pointer, so it is a strange exception to have the last
;; member be different to this)

;; a patch to continue support for 'x'
(struct Point
  (*x *int)
  (x :deref *x))

point/a/b/c/x ;; int
point/a/b/c/'x ;; *int

;; refactoring tools could then be used to take further steps


(struct Thing (name String) (ptr *Thing))
;; Alternative access syntax & semantics:
;; ideally you don't want the set-target expression to be much
;; different to the accessor
(let r (new Thing))
(set r/name "")
(f r/name)
;; the / could be taking some sort of reference to the member
;; relative to the parent, and that reference gets automatically
;; dereferenced everywhere but 'set', and is not affected by the
;; underlying data types.
;; but what if referring the members into scope?
(let r (new Thing))
(use r)
(set name "")
(f name)
;; this can't work, as 'name' is not a reference, but is the value.
;; perhaps this:
(set /name "")
;; why not just make symbols references by default?
(set name "")
(let y Thing.)
(set y other-thing) ;; sets the local #'y
(f y) ;; gets the value at y (Thing)
(let z (new Thing))
(set z other-thing-ptr)
(set @z other-thing)
;; the above illustrates the problem with making symbols references.
;; as using @ would create a context where z gets dereferenced
;; automatically, so @ causes #'z to get dereferenced twice.
;; perhaps:
(set z/ other-thing)
;; But that starts to get confusing.

;; Maybe we can do this better:
(let y Thing.)
(set y other-thing) ;; invalid
(set #'y other-thing) ;; sets the local #'y

(let z (new Thing))
(set #'z other-thing-ptr)
(set z other-thing)

(let r (new Thing))
(set r/name "")
(f r/name)
;; The symbol only becomes a reference when using 'use'
;; 'name' is basically replaced with 'r/name'
(use r)
(set name "")
(f name)
;; but what setting the value at the pointer 'ptr'
(set r/ptr other-thing) ;; invalid: **Thing, Thing
(set @r/ptr other-thing) ;; invalid: Thing, Thing (same problem shown by 'z')
(set r/ptr/ other-thing) ;; valid: *Thing, Thing
(set ptr/ other-thing)
;; now we are inconsistent with setting local pointers, so
;; references in this way seem like a bad idea.
;; If 'set' did auto-reference wrapping like Odin,
;; that would be a better solution

;; If we go back to the beginning, instead of
point/a/b/c/'x ;; *int
;; it might have been better to do
#'point/a/b/c/x ;; *int
;; which maintains more correspondance with the usage:
point/a/b/c/x ;; int
(use point/a/b/c)
c ;; int
#'c ;; *int



;; Aliases: might be useful
(let x 2)
(alias y #'x) ;; y is like a local that shares storage with x
(set y 0)
x ;; => 0

;; What is 'let' worked differently, closer to how top-level
;; constant declarations work?
(let z 2)
z ;; => 2
(set z 0) ;; invalid
(let x (mut 2))
(let y x)
(set y 0)
@x ;; => 0
;; (Imagine 'let' replaced with 'def')
;; Note this is still compatible with before, if you really want
;; mutable local definitions
(set #'x ...)
(set #'y/name "")
(let aliased-x #'x)
;; Now consider:
(let r (new Thing)) ;; just replace 'new' with 'mut' for stack allocation
(set r/name "")
(f @r/name)
;; but having to to @ is annoying. For 'owned' pointers, we
;; might be able to do some auto-dereffing in some places.
;; Auto-dereffing would work best without pointer arithmetic.
;; Maybe a more subtle syntax for auto-dereferencing:
(f r/name/) ;; works whether r is pointer or value
;; Now:
(let y Thing.)
(f y/name) ;; note: no @ needed
;; Now: auto-dereffing
(let *r (new Thing))
(set *r/name "")
(let-deref r *r) ;; or this? (let r (auto-deref *r))
(f r/name)

;; Perhaps '/' only does
;; auto dereferencing for members, not the root struct:
(let a (new Thing))
a/name ;; => *String
a/ptr/name ;; => *String
(let a Thing.)
a/ptr/name ;; => String
;; That seems weird, what about:
(let a (new Thing))
a/name ;; => *String
a/ptr/name ;; => *String
(let a Thing.)
a/name ;; => String
a/ptr/name ;; => *String
;; The latter seems better as long as implicit dereferencing
;; works well