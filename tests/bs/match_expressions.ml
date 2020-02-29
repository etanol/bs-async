exception Kanelo of string

let message e =
  Js.Exn.message e |> Js.Option.getWithDefault "(empty)"

let match_ x =
  match%async x with
  | 1 -> "one"
  | 2 -> "two"

let match_' x =
  match%async' x with
  | 1 -> "one" |> Js.Promise.resolve
  | 2 -> "two" |> Js.Promise.resolve

let match_with_exn x =
  match%async x with
  | 1 -> "one"
  | 2 -> "two"
  | exception Js.Exn.Error e -> message e
  | exception Kanelo e -> e
  | exception JsPromise.JSValue Js.Types.JSFalse -> "false"

let match_with_exn' x =
  match%async' x with
  | 1 -> "one" |> Js.Promise.resolve
  | 2 -> "two" |> Js.Promise.resolve
  | exception Js.Exn.Error e -> message e |> Js.Promise.resolve
  | exception Kanelo e -> e |> Js.Promise.resolve
  | exception JsPromise.JSValue Js.Types.JSFalse -> "false" |> Js.Promise.resolve
