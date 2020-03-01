bs-async
========

A BuckleScript syntax extension to resemble Javascript `async`/`await`.

This is another reincarnation of [bs-let][let], this time tailored only for
Javascript promises.  Contrary to [bs-let][let] (and similar initiatives), this
is **not** a generic *monadic* syntax transformation.

Given that the merge of facebook/reason#2487 marks a temporary forking point
between the OCaml and ReasonML syntax equivalence, this PPX becomes more useful
to the OCaml syntax of BuckleScript.

[let]: /reasonml-labs/bs-let

Installation and use
--------------------

To be able to use this PPX in your BuckleScript project execute the following
command:

```
npm install etanol/bs-async
```

This assumes that `bs-platform` (version 7 or higher) is already installed.
Then, `bsconfig.json` needs to be modified to include the following:

``` json
{
  "ppx-flags": ["bs-async/ppx"],
  "bs-dependencies": ["bs-async"]
}
```

And that should be good to go.

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

What's being simulated in Javascript:

``` javascript
let name = await promise;
expression
```

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

What's almost being simulated in Javascript:

``` javascript
let [first, second] = await Promise.all(promise1, promise2);
expression
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
  (function pattern1 -> expression1 | pattern2 -> expression2 | e -> propagate e)
  (Js.Promise.then_
    (fun () -> promise)
    (Js.Promise.resolve ()))
```

Again, `%async` would forbid `expression1` and `expression2` from having a
`Js.Promise.t` type, whereas `%async'` would require it.  Also, in `%async` the
`propagate e` expression becomes `raise e` while in `%async'`is just
`Js.Promise.reject e`.  This *catch all* case is automatically appended with a
warning *silencer* if the existing cases in the code already cover all
possibilities.

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

In Javascript, it would look approximately like this:

``` javascript
try {
    await promise;
} catch (e) {
    handle_exception;
}
```

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
  (function ex -> handler | e -> propagate e)
  promise
```

[ex]: https://www.cs.cornell.edu/courses/cs3110/2018sp/htmlman/extn.html#sec264

Exception pattern matching
--------------------------

For `try` and `match` expressions with exception cases, there is some extra glue
involved.  Because in Javascript plain values can be also thrown, this PPX
automatically wraps Javascript errors and values into an OCaml/ReasonML
exception.  It is an attempt at generalizing [what BuckelScript
recommends][bsex] to deal with exceptions.

Therefore, apart from [the `Js.Exn.Error` constructor][jsex], a new
`JsPromise.JSValue` constructor is defined to contain a [`Js.Types.tagged_t`
value][jst].

With this, it's theoretically possible to handle all the cases from a single,
flat, list of cases:

``` ocaml
try%async
  promise
with
| Not_found -> 0            (* An OCaml/ReasonML exception *)
| Js.Exn.Error x -> 1       (* A JS Error instance, "x" has type Js.Exn.t *)
| JsPromise.JSValue v -> 2  (* A JS value, "v" can be further pattern matched *)
```

[bsex]: https://bucklescript.github.io/docs/en/exceptions
[jsex]: https://bucklescript.github.io/bucklescript/api/Js.Exn.html
[jst]: https://bucklescript.github.io/bucklescript/api/Js.Types.html
