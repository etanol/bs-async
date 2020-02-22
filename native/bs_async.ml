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

let bs_attribute expr =
  Exp.attr expr (Location.{ txt = "bs" ; loc = none }, PStr [])

let promise_map = Location.{ txt = Longident.parse "JsPromise.map" ; loc = none }
let promise_bind = Location.{ txt = Longident.parse "JsPromise.bind" ; loc = none }
let promise_recover = Location.{ txt = Longident.parse "JsPromise.recover" ; loc = none }
let promise_catch = Location.{ txt = Longident.parse "JsPromise.catch" ; loc = none }
let promise_map_recover = Location.{ txt = Longident.parse "JsPromise.map_recover" ; loc = none }
let promise_bind_catch = Location.{ txt = Longident.parse "JsPromise.bind_catch" ; loc = none }
let promise_all = Location.{ txt = Longident.parse "Js.Promise.all" ; loc = none }

let expanded_let_single mapper mode loc attrs { pvb_pat ; pvb_expr ; pvb_attributes ; pvb_loc } expr =
  Exp.apply ~loc ~attrs
    (Exp.ident (match mode with Functor -> promise_map | Monad -> promise_bind))
    [ (Asttypes.Nolabel, Exp.fun_ Asttypes.Nolabel None (mapper.pat mapper pvb_pat) (mapper.expr mapper expr)
                         |> bs_attribute)
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
                         |> bs_attribute)
    ; (Asttypes.Nolabel, Exp.apply
                           (Exp.ident promise_all)
                           [ (Asttypes.Nolabel, values) ])
    ]

let expanded_try mapper mode loc attrs cases expr =
  Exp.apply ~loc ~attrs
    (Exp.ident (match mode with Functor -> promise_recover | Monad -> promise_catch))
    [ (Asttypes.Nolabel, Exp.function_ (mapper.cases mapper cases) |> bs_attribute)
    ; (Asttypes.Nolabel, mapper.expr mapper expr)
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
       [ (Asttypes.Nolabel, Exp.function_ (mapper.cases mapper cases) |> bs_attribute)
       ; (Asttypes.Nolabel, mapper.expr mapper expr)
       ]
  | exceptions ->
     let not_exceptions = List.filter (fun x -> not @@ is_exception x) cases in
     Exp.apply ~loc ~attrs
       (Exp.ident (match mode with Functor -> promise_map_recover | Monad -> promise_bind_catch))
       [ (Asttypes.Nolabel, Exp.function_ (mapper.cases mapper not_exceptions) |> bs_attribute)
       ; (Asttypes.Nolabel, Exp.function_ (List.map unwrap exceptions |> mapper.cases mapper)
                            |> bs_attribute)
       ; (Asttypes.Nolabel, mapper.expr mapper expr)
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
