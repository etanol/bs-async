let single =
  try%async
        promise
  with
    case -> expression

let single' =
  try%async'
        promise
  with
    case -> expression

let multi =
  try%async
        promise
  with
  | case1 -> expression1
  | case2 -> expression2
  | _ -> default

let multi' =
  try%async'
        promise
  with
  | case1 -> expression1
  | case2 -> expression2
  | _ -> default

let tuple_single =
  try%async
        promise
  with
    (first, second) -> expression

let tuple_single' =
  try%async'
        promise
  with
    (first, second) -> expression

let tuple_multi =
  try%async
        promise
  with
  | (first1, second1) -> expression1
  | (first2, second2) -> expression2

let tuple_multi' =
  try%async'
        promise
  with
  | (first1, second1) -> expression1
  | (first2, second2) -> expression2

let constructor_single =
  try%async
        promise
  with
    Not_found case -> expression

let constructor_single' =
  try%async'
        promise
  with
    Not_found case -> expression

let constructor_multi =
  try%async
        promise
  with
  | Not_found case1 -> expression1
  | Error case2 -> expression2

let constructor_multi' =
  try%async'
        promise
  with
  | Not_found case1 -> expression1
  | Error case2 -> expression2

let record_single =
  try%async
        promise
  with
    { a = b ; c ; _ } -> expression

let record_single' =
  try%async'
        promise
  with
    { a = b ; c ; _ } -> expression

let record_multi =
  try%async
        promise
  with
  | { a1 = b1 ; c1 ; _ } -> expression1
  | { a2 = b2 ; c2 ; _ } -> expression2

let record_multi' =
  try%async'
        promise
  with
  | { a1 = b1 ; c1 ; _ } -> expression1
  | { a2 = b2 ; c2 ; _ } -> expression2
