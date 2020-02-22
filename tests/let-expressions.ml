let single =
  let%async binding = promise
  in
  expression

let single' =
  let%async' binding = promise
  in
  expression

let multi =
  let%async binding1 = promise1
  and binding2 = promise2
  in
  expression

let multi' =
  let%async' binding1 = promise1
  and binding2 = promise2
  in
  expression

let tuple_single =
  let%async (first, second) = promise
  in
  expression

let tuple_single' =
  let%async' (first, second) = promise
  in
  expression

let tuple_multi =
  let%async (first1, second1) = promise1
  and (first2, second2) = promise2
  in
  expression
  
let tuple_multi' =
  let%async' (first1, second1) = promise1
  and (first2, second2) = promise2
  in
  expression

let constructor_single =
  let%async Some value = promise
  in
  expression

let constructor_single' =
  let%async' Some value = promise
  in
  expression

let constructor_multi =
  let%async Some value1 = promise1
  and Some value2 = promise2
  in
  expression
    
let constructor_multi' =
  let%async' Some value1 = promise1
  and Some value2 = promise2
  in
  expression

let record_single =
  let%async { a = b ; c ; _ } = promise
  in
  expression

let record_single' =
  let%async' { a = b ; c ; _ } = promise
  in
  expression

let record_multi =
  let%async { a1 = b1 ; c1 ; _ } = promise1
  and { a2 = b2 ; c2 ; _ } = promise 2
  in
  expression
    
let record_multi' =
  let%async' { a1 = b1 ; c1 ; _ } = promise1
  and { a2 = b2 ; c2 ; _ } = promise 2
  in
  expression


