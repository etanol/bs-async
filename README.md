bs-async
========

A BuckleScript syntax extension to resemble Javascript `async`/`await`.

**IMPORTANT:** This is an experimental package.  The semantics of code
transformations are not stabilized yet.  The package is public in order to
gather some feedback.

Overview
--------

This package implements a PPX to transform OCaml/Reason code that almost *looks*
like Javascript's `async`/`await` into code that chains promises.

The available extensions are `%async` and `%async'`.  The difference between the
two is that the former automatically wraps some parts of the expression into a
`Js.Promise.t` and the latter **expects** all parts of the expression to be of
`Js.Promise.t`.

### `let` expressions ###

Original:

``` ocaml
let%async name = promise in expression
```

Result (approximate):

``` ocaml
Js.Promise.then_ (fun name -> expression) promise
```

Using `%async` **forbids** `expression` from being of `Js.Promise.t` type,
whereas `%async'` **requires** it.

It also works with multiple bindings.  Original:

``` ocaml
let%async first = promise1
and second = promise2
in
expression
```

Result (approximate):

``` ocaml
Js.Promise.then_
  (fun [| first ; second |] -> expression)
  (Js.Promise.all [| promise1 ; promise2 |])
```

### `try` expressions ###

Original:

``` ocaml
try%async
  promise
with
| pattern1 -> expression1
| pattern2 -> expression2
```

Result (approximate):

``` ocaml
Js.Promise.catch
  (function pattern1 -> expression1 | pattern2 -> expression2)
  (Js.Promise.then_
    (fun () -> promise)
    (Js.Promise.resolve ()))
```

The extra convolution of the generated code attempts to catch any exception
thrown within the `try` body asynchronously.  If, instead, this PPX generated
code like the following:

``` ocaml
(* Bogus hipothetically generated code *)
Js.Promise.catch
  (function pattern1 -> expression1 | pattern2 -> expression2)
  promise
```

What would happen is that it would break expectations in some cases (both kind
of expectations, JS and OCaml).  Like, for example:

``` ocaml
exception My_salsa of string

let fail x : string -> string=
  try%async
    raise (My_salsa x) |> Js.Promise.resolve
  with
  | My_salsa e -> Js.log e
```

The `fail` function should return a rejected promise.  However, depending on how
it's used, it could raise an OCaml exception immediately.

### `match` expressions ###

Original:

``` ocaml
match%async promise with
| pattern -> expression
```

Note that this, in practice, could simply desugar to:

``` ocaml
let%async name = promise in
match name with
| pattern -> expression
```

However, it directly generates something like the following:

``` ocaml
Js.Promise.then_
  (function pattern -> expression)
  promise
```

More interesting, though, is when [exception cases][ex] are used:

``` ocaml
match%async promise with
| pattern -> expression
| exception ex -> handler
```

Which translates (approximately) to:

``` ocaml
Js.Promise.then_catch  (* Mapping for two arguments Promise.then() *)
  (function pattern -> expression)
  (function ex -> handler)
  promise
```

[ex]: https://www.cs.cornell.edu/courses/cs3110/2018sp/htmlman/extn.html#sec264

In depth discussion
-------------------

For now, see the [design notes][d] separately available.

[d]: DESIGN.md
