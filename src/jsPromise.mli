type exn += private JSValue of Js.Types.tagged_t

external map : ('a -> 'b [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
external bind : ('a -> 'b Js.Promise.t [@bs.uncurry]) -> 'b Js.Promise.t = "then" [@@bs.send.pipe: 'a Js.Promise.t]
val recover : (exn -> 'a) -> 'a Js.Promise.t -> 'a Js.Promise.t
val catch : (exn -> 'a Js.Promise.t) -> 'a Js.Promise.t -> 'a Js.Promise.t
val map_recover : ('a -> 'b) -> (exn -> 'b) -> 'a Js.Promise.t -> 'b Js.Promise.t
val bind_catch : ('a -> 'b Js.Promise.t) -> (exn -> 'b Js.Promise.t) -> 'a Js.Promise.t -> 'b Js.Promise.t
