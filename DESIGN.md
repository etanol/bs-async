Design Notes
============

The design goal of this PPX is to apply transformations while minimizing the
surprising behavior in some corner cases.  Those corner cases usually involve
exception handling.

What this document describes is the looks and the semantics of the *original*
code, i.e. the one using the `%async`/`%async'` extensions.  Always comparing
with what the `async`/`await` Javascript equivalent would look and behave.

`let` expressions
-----------------

The single binding `let` is the most trivial case.  In Javascript, we would have
the following:

``` javascript
let name = await promise;
expression;  // Does something with name
```

Proposed OCaml equivalent:

``` ocaml
let%async name = promise in
expression  (* Does something with name *)
```

From BuckleScript (BS), `promise` **must** be of type `'a Js.Promise.t` because,
in Javascript (JS), `await` only works over expressions that return a promise.
Then, `expression` can make use of the **resolved** value provided by the
promise.

In JS, the whole thing only works inside an `async` function: a function that
**must** return a promise.  Therefore, in OCaml, `expression` **must** be of
type `'b Js.Promise.t`.

### Multiple binding ###

When awaiting multiple unrelated promises, OCaml has an edge over JS (does
Reason have it too?).  In JS, multiple bindings are evaluated sequentially:

``` javascript
let a = await promise1;
let b = await promise2;
expression  // Do something with a and b
```

In OCaml, this would be translated as:

``` ocaml
let%async a = promise1 in
let%async b = promise2 in
expression  (* a and b are both in scope *)
```

But, if we want to wait for both promises **in parallel**, in OCaml we can do
better:

``` ocaml
let%async a = promise1
and b = promise2 in
expression  (* a and b are "waiting" simultaneously *)
```

### Recursion ###

Recursive let bindings are simply **not supported**.  The way promise objects
work and how `await` behaves doesn't really have clear use of *self* recursion.

### Automatic promise wrapping ###

In JS, the function provided to `Promise.then` and return a promise object or
not.  If the function does not return a promise, the JS run time automatically
wraps the returned value in a resolved promise.

The [default promise bindings][js.prom] in BS only allows explicitly returning
promise objects.  However, this can get repetitive sometimes.  Therefore, it's
interesting to offer two flavors: one where returned values are automatically
wrapped (*functorial style*), and another where returned values should be
promises (*monadic style*).

To differentiate these cases, two different extension nodes will be used:
`%async` and `%async'.

``` ocaml
let%async name = promise in expression
```

Where `expression` must **not** be of `'b Js.Promise.t`, and

``` ocaml
let%async' name = promise in expression
```

Where `expression` **must** be of `'b Js.Promise.t`.

Notice that in any case, the type of `promise` **must** be `'a Js.Promise.t`.

[js.prom]: https://bucklescript.github.io/bucklescript/api/Js.Promise.html

### Exception behavior ###

Here is where it becomes difficult to reconcile both worlds.  In JS, `await`
statements can only be used inside `async` functions.  So the whole function
returns a promise, any exception thrown inside the function is translated to a
rejected promise returned.  In other words, in the following code:

``` javascript
async function sample (flag) {
    if (flag)
        throw "Before";
    let name = await promise;
    if (!flag)
        throw "After";
}
```

It doesn't matter if `flag` is true or false.  The result will be a rejected
promise so the exception doesn't immediately propagate.  Compare with, somehow
equivalent:

``` ocaml
let sample flag : bool -> unit Js.Promise.t =
  if flag then
    raise Before;
  let%async name = promise in
  if not flag then
    raise After
```

Because the `sample` function has no special treatment, the exception may be
raised in two ways.  Immediately:

``` ocaml
let%async () = sample true in Js.log "foo"
```

or be converted to a rejected promise:

``` ocaml
let%async' nothing = Js.Promise.resolve () in
sample true
```

Note that in both cases, the `After` exception is converted to a rejected
promise.

The main issue here is that the *extension node* in OCaml's AST **cannot**
easily transform what's before (or, in AST terms, its parent nodes).  From a
higher perspective, `%async`/`%async'` can serve as frontier between synchronous
and asynchronous code within the same function.  But `await` mandates that the
whole function to be `async`, it's not really an asynchronous *delimiter*.

As a pragmatic compromise, seems like accepting the situations of the `Before`
exception could be even desirable since in JS, once the code enters asynchronous
execution it can never go back to synchronous.  And this fact is identically
modeled in OCaml.

`try` expressions
-----------------

The second interesting control structure is exception handling.  In JS:

``` javascript
try {
    await promise;
} catch (ex) {
    do_something;
}
```

Proposed OCaml:

``` ocaml
try%async
  promise
with
  ex -> do_something
```

In plain OCaml, the `try` body must have **the same** type as each of the
expressions in the exception cases.  This restriction can be lifted, since code
is supposed to be asynchronous; meaning that the `try` body and the error
handling happen as part of **different** promises.

This hypothetical relaxation of the typing discipline is very risky.  Specially
for OCaml developers, since it departs significantly from the typing rules of
the language.  The difference between allowing this loosening of types lies on
how the `Promise.catch()` function is bound in BS.

### Propagation behavior ###

Here, the behavioral licenses taken in the `let` case cannot be used here.  In
both JS and OCaml, any exception raised within the `try`-`with` boundary must be
pattern matched against the declared cases.

``` javascript
try {
    throw "Before";
    await promise;
    throw "After";
} catch (ex) {
    handle;
}
```

Similarly:

``` ocaml
try%async
  raise Before;
  promise;
  raise After
with
  ex -> handle
```

The `Before` exception **cannot** be thrown immediately.  It **must** be
converted to a rejected promise in all cases.

Moreover, if no exception cases match then the exception most continue
propagating, still in the form of a rejected promise.  Just like it happens in
JS.

In the *monadic style*, adding code to re-throw an uncaught exception is as
simple as creating a rejected promise.  But in the *functorial style*, the
exception needs to be thrown for real since the promise wrapping is automatic.

### Typing issues ###

Once again, a hard reconciliation problem appears.  In JS, any value can be
thrown.  In OCaml, only exception types.  Moreover, in BS, JS exceptions are
separated from OCaml exceptions.  The way it is defined has a positive and a
negative side:

- The positive side is that JS exceptions can be represented as OCaml
  exceptions.
- The negative side is that the [documentation examples][ex] don't show how to
  handle JS and OCaml exceptions **in the same** set of `with` clauses.

Ideally, a specific exception type should be defined to contain values that are
**not** instances of JS `Error`.  Extra code, in the form of an auxiliary
function, would be necessary to converge all possible values under the different
OCaml exception types.

[ex]: https://bucklescript.github.io/docs/en/exceptions

`match` expressions
-------------------

Because JS doesn't have any similar structure to OCaml's `match`, in this case
semantics can be modeled more closely to OCaml than JS.

``` ocaml
match%async promise with
| pattern -> expression
```

This can be considered a shortcut to:

``` ocaml
let%async name = promise in
match name
| pattern -> expression
```

So the behavior of exceptions should be the same as in `let` expressions.

### Exception cases ###

A little more interesting is the `match` expression with [exception cases][oex]:

``` ocaml
match%async promise with
| pattern -> expression
| exception ex -> handler
```

Here the exceptions are matched if the evaluation of `promise` throws an
exception, but not if a case expression does.  Which makes this expression a
perfect candidate to use the two argument `Promise.then()` in JS.

[oex]: https://www.cs.cornell.edu/courses/cs3110/2018sp/htmlman/extn.html#sec264
