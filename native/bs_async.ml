(*
 * This PPX only uses the standard OCaml compiler-lib.  There are various
 * reasons for avoiding ppxlib, ocaml-migrate-parsetree, metaquot or ppx_tools.
 * First, this PPX is exclusively intended for use from BuckleScript, which is
 * sort of stuck in OCaml 4.06.  Therefore, the parse tree can be considered
 * stable.  Second, the compilation story for this package requires Esy (for
 * now) so eliminating dependencies should reduce build times and storage
 * consumption.  And third, the mentioned PPX supporting libraries are not
 * comprehensively documented.  Consider this refusal as a symbolic protest.
 *
 * Still, some handy command line utilities from ppx_tools are being used for
 * testing purposes only.
 *)
open Ast_helper
open Ast_mapper
open Parsetree

(* An exception to signal something really unexpected *)
exception Impossible

(*
 * These constructors don't really mean what they are called, they just sound
 * smart.  "Functor" refers to the transformations where the final expressions
 * DOES NOT return a Js.Promise.t and, therefore, need to be wrapped.  "Monad"
 * refers to the transformations where the final expression DOES return a
 * Js.Promise.t.
 *
 * In the end, the major difference is the JS promise bindings that will end up
 * being used.  This PPX does NOT explicitly wrap expressions in Js.Promise.t
 *)
type mode = Functor | Monad

let mode_of_string = function
  | "async" -> Functor
  | "async'" -> Monad
  | _ -> raise Impossible

(*
 * Used to insert an error extension node, so the compiler will report it.
 *)
let make_error loc msg =
  Location.error ~loc msg
  |> extension_of_error
  |> Exp.extension

(*
 * Decorate the given expression with a warning attribute, to enable/disable
 * warnings on generated parse tree fragments only.
 *)
let warning arg expr =
  Exp.attr expr (Location.{ txt = "warning" ; loc = none },
                 PStr [Str.eval @@ Exp.constant @@ Const.string arg])

(*
 * Some short cuts to ease identifier insertion in the parse tree.
 *)
let unit = Longident.parse "()" |> Location.mknoloc
let raise_ = Longident.parse "raise" |> Location.mknoloc
let promise_resolve = Longident.parse "Js.Promise.resolve" |> Location.mknoloc
let promise_reject = Longident.parse "Js.Promise.reject" |> Location.mknoloc
let promise_map = Longident.parse "JsPromise.map" |> Location.mknoloc
let promise_bind = Longident.parse "JsPromise.bind" |> Location.mknoloc
let promise_recover = Longident.parse "JsPromise.recover" |> Location.mknoloc
let promise_catch = Longident.parse "JsPromise.catch" |> Location.mknoloc
let promise_map_recover = Longident.parse "JsPromise.map_recover" |> Location.mknoloc
let promise_bind_catch = Longident.parse "JsPromise.bind_catch" |> Location.mknoloc
let promise_all = Longident.parse "Js.Promise.all" |> Location.mknoloc

(*
 * Create a new "catch all" exception case.  A specific warning silencer will
 * need to be incorporated to the expression where this case is appended to.
 * Otherwise, confusing compiler warnings will start to show up if the cases
 * existing in the code already handle all possible patterns.
 *
 * Is returned as a single element list to make it easy to concatenate against
 * an existing case list.
 *)
let catch_all mode =
  [ Exp.case
      (Pat.var (Location.mknoloc "e")) (* The tiny scope eliminates the need for hygiene *)
      (Exp.apply
         (Exp.ident @@ match mode with Functor -> raise_ | Monad -> promise_reject)
         [ (Asttypes.Nolabel,
            Exp.ident @@ (Longident.parse "e" |> Location.mknoloc))
      ])
  ]

(*
 * Single binding let transformation.
 *
 * From:
 *
 *  let%async name = promise in expression
 *
 * To:
 *
 *  Js.Promise.then_ (fun name -> expression) promise
 *)
let expanded_let_single mapper mode loc attrs { pvb_pat ; pvb_expr ; pvb_attributes ; pvb_loc } expr =
  Exp.apply ~loc ~attrs
    (Exp.ident (match mode with Functor -> promise_map | Monad -> promise_bind))
    [ (Asttypes.Nolabel, Exp.fun_ ~loc:pvb_loc Asttypes.Nolabel None
                           (mapper.pat mapper pvb_pat) (mapper.expr mapper expr))
    ; (Asttypes.Nolabel, mapper.expr mapper pvb_expr)
    ]

(*
 * Multiple binding let transformation.
 *
 * From:
 *
 *  let%async name1 = promise1 and name2 = promise2 in expression
 *
 * To:
 *
 *  Js.Promise.then_
 *    (fun [| name1 ; name2 |] -> expression)
 *    (Js.Promise.all [| promise1 ; promise2 |])
 *)
let expanded_let_multi mapper mode loc attrs bindings expr =
  let patterns = List.map (fun { pvb_pat ; _ } -> mapper.pat mapper pvb_pat) bindings
                 |> Pat.array
  and values = List.map (fun { pvb_expr ; _ } -> mapper.expr mapper pvb_expr) bindings
               |> Exp.array
  in
  Exp.apply ~loc ~attrs
    (Exp.ident (match mode with Functor -> promise_map | Monad -> promise_bind) )
    [ (Asttypes.Nolabel, Exp.fun_ Asttypes.Nolabel None patterns (mapper.expr mapper expr)
                         |> warning "-8")
    ; (Asttypes.Nolabel, Exp.apply
                           (Exp.ident promise_all)
                           [ (Asttypes.Nolabel, values) ])
    ]

(*
 * Try/with transformation.  This transformation is more convoluted than "let"
 * because, while the body expression has to be of type Js.Promise.t, an OCaml
 * (or JS) exception may be raised before the final expression.  Therefore, the
 * whole body needs to be wrapped inside a promise.
 *
 * Also, to preserve exception propagation semantics, the "with" cases may not
 * be handling all the possible thrown values.  So a "catch all", sort of case
 * must be appended to propagate the potentially unprocessed exception value (in
 * the form of a rejected promise).
 *
 * From:
 *
 *  try%async promise with case1 -> handler1 | case2 -> handler2
 *
 * To:
 *
 *  Js.Promise.catch
 *    (function case1 -> handler1 | case2 -> handler2 | x -> propagate x)
 *    (Js.Promise.then_ (fun () -> promise) (Js.Promise.resolve ()))
 *)
let expanded_try mapper mode loc attrs cases expr =
  Exp.apply ~loc ~attrs
    (Exp.ident ~loc (match mode with Functor -> promise_recover | Monad -> promise_catch))
    [ (Asttypes.Nolabel,
       Exp.function_ @@ mapper.cases mapper cases @ catch_all mode
       |> warning "-11")
    ; (Asttypes.Nolabel,
       Exp.apply
         (Exp.ident promise_bind)
         [ (Asttypes.Nolabel,
            Exp.fun_ Asttypes.Nolabel None (Pat.construct unit None) (mapper.expr mapper expr))
         ; (Asttypes.Nolabel,
            Exp.apply (Exp.ident promise_resolve) [(Asttypes.Nolabel, Exp.construct unit None)])
      ])
    ]

(*
 * Match/with transformation.  The added beauty of this transformation is the
 * possibility of defining regular pattern matching as well as exception
 * handling in the same expression, which aligns perfectly with the two
 * parameter Promise.then() in JS.  This is the main motivation for supporting
 * "match" expression.  Otherwise, a combination of let + try would achieve the
 * same result; but more code nesting would be necessary.
 *
 * Because exceptions handling could happen, the same kind of transformation as
 * in "expanded_try" needs to be applied.  That is, adding a hidden case that
 * propagates the exception.
 *
 * From:
 *
 *  match%async promise with case1 -> expression1 | case2 -> expression2
 *
 *  match%async promise with case -> expression | exception ex -> handler
 *
 * To (respectively):
 *
 *  Js.Promise.then_ (function case1 -> expression1 | case2 -> expression2) promise
 *
 *  Js.Promise.then_catch
 *    (function case -> expression)
 *    (function ex -> handler | e -> propagate e)
 *    promise
 *)
let expanded_match mapper mode loc attrs cases expr =
  let is_exception { pc_lhs = { ppat_desc ; _ } ; _ } =
    match ppat_desc with
    | Ppat_exception _ -> true
    | _ -> false
  and unwrap = function
    | { pc_lhs = { ppat_desc = Ppat_exception p ; _ } ; _ } as case ->
       { case with pc_lhs = p }
    | _ ->
       raise Impossible
  in
  match List.filter is_exception cases with
  | [] -> (* No exception cases, then expand to the simple version *)
     Exp.apply ~loc ~attrs
       (Exp.ident (match mode with Functor -> promise_map | Monad -> promise_bind))
       [ (Asttypes.Nolabel,
          Exp.function_ ~loc (mapper.cases mapper cases))
       ; (Asttypes.Nolabel,
          mapper.expr mapper expr)
       ]
  | exceptions ->
     let not_exceptions = List.filter (fun x -> not @@ is_exception x) cases in
     Exp.apply ~loc ~attrs
       (Exp.ident (match mode with Functor -> promise_map_recover | Monad -> promise_bind_catch))
       [ (Asttypes.Nolabel,
          Exp.function_ ~loc (mapper.cases mapper not_exceptions))
       ; (Asttypes.Nolabel,
          Exp.function_ @@ (List.map unwrap exceptions |> mapper.cases mapper) @ catch_all mode
          |> warning "-11")
       ; (Asttypes.Nolabel,
          mapper.expr mapper expr)
       ]

(*
 * Expression transformation dispatcher.  This function delegates into the
 * specific transformation case, depending on the type of expression received.
 *)
let expanded_expression mapper mode { pexp_desc ; pexp_loc ; pexp_attributes } =
  match pexp_desc with
  | Pexp_let (Asttypes.Nonrecursive, [], _) -> (* Unlikely *)
     make_error pexp_loc "No bindings defined in let expression"
  | Pexp_let (Asttypes.Nonrecursive, [binding], expr) ->
     expanded_let_single mapper mode pexp_loc pexp_attributes binding expr
  | Pexp_let (Asttypes.Nonrecursive, bindings, expr) ->
     expanded_let_multi mapper mode pexp_loc pexp_attributes bindings expr
  | Pexp_let (Asttypes.Recursive, _, _) ->
     make_error pexp_loc "Async cannot transform recursive bindings"
  | Pexp_try (_, []) -> (* Unlikely *)
     make_error pexp_loc "No cases defined for try expression"
  | Pexp_try (expr, cases) ->
     expanded_try mapper mode pexp_loc pexp_attributes cases expr
  | Pexp_match (_, []) -> (* Unlikely *)
     make_error pexp_loc "No cases defined for match expression"
  | Pexp_match (expr, cases) ->
     expanded_match mapper mode pexp_loc pexp_attributes cases expr
  | _ ->
     make_error pexp_loc "Async does not work here"

(*
 * A custom mapper that replaces all the supported async extension nodes and
 * replaces them with transformed code.
 *)
let async_transform mapper = function
  | { pexp_desc = Pexp_extension ({ txt = ("async" | "async'") as mode ; loc }, payload) ; _ } ->
     begin
       match payload with
       | PStr [] -> (* Unlikely *)
          make_error loc "Async received an empty structure"
       | PStr [{ pstr_desc = Pstr_eval (exp, []) ; _ }] ->
          expanded_expression mapper (mode_of_string mode) exp
       | PStr [{ pstr_desc = Pstr_eval (_, _); _ }] ->
          make_error loc "Async does not allow attributes"
       | PStr [_] ->
          make_error loc "Async only works with expressions"
       | PStr _ -> (* Unlikely? *)
          make_error loc "Async does not accept multiple structures"
       | _ ->
          make_error loc "Async is not supported like this"
     end
  | other ->
     default_mapper.expr mapper other

(* Perhaps Ast_mapper.run_main makes a different in run time speed? *)
let () =
  register "async" (fun _ -> { default_mapper with expr = async_transform })
