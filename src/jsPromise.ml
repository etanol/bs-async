external map : ('a -> 'b [@bs]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external bind : ('a -> 'b Js.Promise.t [@bs]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external recover' : (Js.Promise.error -> 'b [@bs]) -> 'b Js.Promise.t = "catch" [@@bs.send.pipe: 'a Js.Promise.t]
external catch' : (Js.Promise.error -> 'b Js.Promise.t [@bs]) -> 'b Js.Promise.t = "catch" [@@bs.send.pipe: 'a Js.Promise.t]
external map_recover' : ('a -> 'b [@bs]) (exn -> 'b [@bs]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external bind_catch : ('a -> 'b Js.Promise.t [@bs]) (exn -> 'b Js.Promise.t [@bs]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe. 'a Js.Promise.t

let is_caml_exception = Js.Exn.isCamlExceptionorOpenVariant

let error_to_exn : Js.Promise.error -> exn = [%raw {|
  function (value) {
    if (is_caml_exception(value)) {
      return value;
    } else if (value instanceof Error) {
      return [Js_exn.$$Error, value];
    } else if (typeof(value) === 'object') {
      return [Js_exn.$$Error, new Error(JSON.stringify(value))];
    } else {
      return [Js_exn.$$Error, new Error(value.toString())];
    }
  }                                                 
|}]                          
                                                                                    
let recover handler promise =
  recover' (fun[@bs] e -> error_to_exn e |> handler) promise

let catch handler promise =
  catch' (fun[@bs] e -> error_to_exn e |> handler) promise

let map_recover next handler promise =
  map_recover' next (fun[@bs] e -> error_to_exn e |> handler) promise

let bind_catch next handler promise =
  bind_catch' next (fun[@bs] e -> error_to_exn e |> handler) promise
