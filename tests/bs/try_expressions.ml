exception My_salsa of string

let message e =
  Js.Exn.message e |> Js.Option.getWithDefault "(empty)"

let fail_js x =
  try%async
    Js.Exn.raiseError x |> Js.Promise.resolve
  with
    Js.Exn.Error e -> message e

let fail_js' x =
  try%async'
    Js.Exn.raiseError x |> Js.Promise.resolve
  with
    Js.Exn.Error e -> message e |> Js.Promise.resolve

let fail_bs x =
  try%async
    raise (My_salsa x) |> Js.Promise.resolve
  with
    My_salsa e -> e

let fail_bs' x =
  try%async'
    raise (My_salsa x) |> Js.Promise.resolve
  with
    My_salsa e -> e |> Js.Promise.resolve

let fail_promise x =
  try%async
    Js.Promise.reject x
  with
    Js.Exn.Error e -> message e

let fail_promise' x =
  try%async'
    Js.Promise.reject x
  with
    Js.Exn.Error e -> message e |> Js.Promise.resolve
