open Ast_helper
open Ast_mapper
open Parsetree

exception Impossible

(* These constructors don't really mean what they are called, they just sound smart *)
type mode = Functor | Monad

let mode_of_string = function
  | "async" -> Functor
  | "async'" -> Monad
  | _ -> raise Impossible

let make_error loc msg =
  Location.error ~loc msg
  |> extension_of_error
  |> Exp.extension

let warning arg expr =
  Exp.attr expr (Location.{ txt = "warning" ; loc = none },
                 PStr [Str.eval @@ Exp.constant @@ Const.string arg])

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

let catch_all mode =
  [ Exp.case
      (Pat.var (Location.mknoloc "e"))
      (Exp.apply
         (Exp.ident @@ match mode with Functor -> raise_ | Monad -> promise_reject)
         [ (Asttypes.Nolabel,
            Exp.ident @@ (Longident.parse "e" |> Location.mknoloc))
      ])
    |> warning "-11"
  ]

let expanded_let_single mapper mode loc attrs { pvb_pat ; pvb_expr ; pvb_attributes ; pvb_loc } expr =
  Exp.apply ~loc ~attrs
    (Exp.ident (match mode with Functor -> promise_map | Monad -> promise_bind))
    [ (Asttypes.Nolabel, Exp.fun_ ~loc:pvb_loc Asttypes.Nolabel None
                           (mapper.pat mapper pvb_pat) (mapper.expr mapper expr))
    ; (Asttypes.Nolabel, mapper.expr mapper pvb_expr)
    ]

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

let expanded_try mapper mode loc attrs cases expr =
  Exp.apply ~loc ~attrs
    (Exp.ident ~loc (match mode with Functor -> promise_recover | Monad -> promise_catch))
    [ (Asttypes.Nolabel,
       Exp.function_ @@ mapper.cases mapper cases @ catch_all mode)
    ; (Asttypes.Nolabel,
       Exp.apply
         (Exp.ident promise_bind)
         [ (Asttypes.Nolabel,
            Exp.fun_ Asttypes.Nolabel None (Pat.construct unit None) (mapper.expr mapper expr))
         ; (Asttypes.Nolabel,
            Exp.apply (Exp.ident promise_resolve) [(Asttypes.Nolabel, Exp.construct unit None)])
      ])
    ]

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
          Exp.function_ @@ (List.map unwrap exceptions |> mapper.cases mapper) @ catch_all mode)
       ; (Asttypes.Nolabel,
          mapper.expr mapper expr)
       ]

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
          make_error loc "Async does not accpet multiple structures"
       | _ ->
          make_error loc "Async is not supported like this"
     end
  | other ->
     default_mapper.expr mapper other

(* I wonder if just using Ast_mapper.run_main makes any difference *)
let () =
  register "async" (fun _ -> { default_mapper with expr = async_transform })
