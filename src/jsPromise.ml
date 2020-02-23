external map : ('a -> 'b [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external bind : ('a -> 'b Js.Promise.t [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external recover' : (Js.Promise.error -> 'b [@bs.uncurry]) -> 'b Js.Promise.t = "catch" [@@bs.send.pipe: 'a Js.Promise.t]
external catch' : (Js.Promise.error -> 'b Js.Promise.t [@bs.uncurry]) -> 'b Js.Promise.t = "catch" [@@bs.send.pipe: 'a Js.Promise.t]
external map_recover' : ('a -> 'b [@bs.uncurry]) -> (Js.Promise.error -> 'b [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external bind_catch' : ('a -> 'b Js.Promise.t [@bs.uncurry]) -> (Js.Promise.error -> 'b Js.Promise.t [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]

(* let is_caml_exception = Js.Exn.isCamlExceptionOrOpenVariant
 * let error_exn = Js.Exn.Error *)

let wrap_in_error : 'a -> Caml_js_exceptions.t = [%raw {|
  function (value) {
    if (value instanceof Error) {
      return value;
    } else if (typeof(value) === 'object') {
      return new Error(JSON.stringify(value));
    } else {
      return new Error(value.toString());
    }
  }
|}]

let error_to_exn any =
  if Caml_exceptions.caml_is_extension any then
    (Obj.magic any : exn)
  else
    Caml_js_exceptions.Error (wrap_in_error any)

let recover handler promise =
  recover' (fun e -> error_to_exn e |> handler) promise

let catch handler promise =
  catch' (fun e -> error_to_exn e |> handler) promise

let map_recover next handler promise =
  map_recover' next (fun e -> error_to_exn e |> handler) promise

let bind_catch next handler promise =
  bind_catch' next (fun e -> error_to_exn e |> handler) promise
