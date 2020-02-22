let single =
  match%async promise with
  | case -> expression

let single' =
  match%async' promise with
  | case -> expression

let single_exc =
  match%async promise with
  | case -> expression
  | exception case -> handling

let single_exc =
  match%async' promise with
  | case -> expression
  | exception case -> handling

let multi =
  match%async promise with
  | case1 -> expression1
  | case2 -> expression2

let multi' =
  match%async' promise with
  | case1 -> expression1
  | case2 -> expression2

let multi_exc =
  match%async promise with
  | case1 -> expression1
  | exception ex1 -> handling1
  | case2 -> expression2
  | exception ex2 -> handling2

let multi_exc' =
  match%async' promise with
  | case1 -> expression1
  | exception ex1 -> handling1
  | case2 -> expression2
  | exception ex2 -> handling2
