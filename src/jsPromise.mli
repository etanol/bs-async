val map : ('a -> 'b [@bs]) -> 'a Js.Promise.t -> 'b Js.Promise.t
val bind : ('a -> 'b Js.Promise.t [@bs]) -> 'a Js.Promise.t -> 'b Js.Promise.t
val recover : (exn -> 'b [@bs]) -> 'a Js.Promise.t -> 'b Js.Promise.t
val catch : (exn -> 'b Js.Promise.t [@bs]) -> 'a Js.Promise.t -> 'b Js.Promise.t
val map_recover : ('a -> 'b [@bs]) -> (exn -> 'b [@bs]) -> 'a Js.Promise.t -> 'b Js.Promise.t
val bind_catch : ('a -> 'b Js.Promise.t [@bs]) -> (exn -> 'b [@bs]) -> 'a Js.Promise.t -> 'b Js.Promise.t
