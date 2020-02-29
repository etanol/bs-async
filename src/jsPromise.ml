external map : ('a -> 'b [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external recover' : (Js.Promise.error -> 'a [@bs.uncurry]) -> 'a Js.Promise.t = "catch" [@@bs.send.pipe: 'a Js.Promise.t]
external map_recover' : ('a -> 'b [@bs.uncurry]) -> (Js.Promise.error -> 'b [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external then_catch' : ('a -> 'b Js.Promise.t [@bs.uncurry]) -> (Js.Promise.error -> 'b Js.Promise.t [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]

exception JSValue of Js.Types.tagged_t

let is_exception : 'a -> bool = [%raw {|
  function (value) {
    return value instanceof Error;
  }
|}]

let error_to_exn any =
  if Caml_exceptions.caml_is_extension any then
    (Obj.magic any : exn)
  else if is_exception any then
    Caml_js_exceptions.Error (Obj.magic any : Caml_js_exceptions.t)
  else
    JSValue (Js.Types.classify any)

let recover handler promise =
  recover' (fun e -> error_to_exn e |> handler) promise

let catch handler promise =
  Js.Promise.catch (fun e -> error_to_exn e |> handler) promise

let map_recover next handler promise =
  map_recover' next (fun e -> error_to_exn e |> handler) promise

let then_catch next handler promise =
  then_catch' next (fun e -> error_to_exn e |> handler) promise
