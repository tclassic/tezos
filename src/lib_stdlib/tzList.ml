(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2018.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

let may_cons xs x = match x with None -> xs | Some x -> x :: xs

let filter_map f l =
  List.rev @@ List.fold_left (fun acc x -> may_cons acc (f x)) [] l

let rev_sub l n =
  if n < 0 then
    invalid_arg "Utils.rev_sub: `n` must be non-negative.";
  let rec append_rev_sub acc l = function
    | 0 -> acc
    | n ->
        match l with
        | [] -> acc
        | hd :: tl -> append_rev_sub (hd :: acc) tl (n - 1) in
  append_rev_sub [] l n

let sub l n = rev_sub l n |> List.rev

let hd_opt = function
  | [] -> None
  | h :: _ -> Some h

let rec last_exn = function
  | [] -> raise Not_found
  | [x] -> x
  | _ :: xs -> last_exn xs

let merge_filter2
    ?(finalize = List.rev) ?(compare = compare)
    ?(f = Option.first_some)
    l1 l2 =
  let sort = List.sort compare in
  let rec merge_aux acc = function
    | [], [] -> finalize acc
    | r1, [] -> finalize acc @ (filter_map (fun x1 -> f (Some x1) None) r1)
    | [], r2 -> finalize acc @ (filter_map (fun x2 -> f None (Some x2)) r2)
    | ((h1 :: t1) as r1), ((h2 :: t2) as r2) ->
        if compare h1 h2 > 0 then
          merge_aux (may_cons acc (f None (Some h2))) (r1, t2)
        else if compare h1 h2 < 0 then
          merge_aux (may_cons acc (f (Some h1) None)) (t1, r2)
        else (* m1 = m2 *)
          merge_aux (may_cons acc (f (Some h1) (Some h2))) (t1, t2)
  in
  merge_aux [] (sort l1, sort l2)

let merge2 ?finalize ?compare ?(f = fun x1 _x1 -> x1) l1 l2 =
  merge_filter2 ?finalize ?compare
    ~f:(fun x1 x2 -> match x1, x2 with
        | None, None -> assert false
        | Some x1, None -> Some x1
        | None, Some x2 -> Some x2
        | Some x1, Some x2 -> Some (f x1 x2))
    l1 l2

let rec remove nb = function
  | [] -> []
  | l when nb <= 0 -> l
  | _ :: tl -> remove (nb - 1) tl

let rec repeat n x = if n <= 0 then [] else x :: repeat (pred n) x

let take_n_unsorted n l =
  let rec loop acc n = function
    | [] -> l
    | _ when n <= 0 -> List.rev acc
    | x :: xs -> loop (x :: acc) (pred n) xs in
  loop [] n l

module Bounded(E: Set.OrderedType) : sig

  type t
  val create: int -> t
  val insert: E.t -> t -> unit
  val get: t -> E.t list

end = struct

  (* TODO one day replace the list by an heap array *)

  type t = {
    bound : int ;
    mutable size : int ;
    mutable data : E.t list ;
  }

  let create bound =
    if bound <= 0 then invalid_arg "Utils.Bounded(_).create" ;
    { bound ; size = 0 ; data = [] }

  let rec push x = function
    | [] -> [x]
    | (y :: xs) as ys ->
        if E.compare x y <= 0
        then x :: ys
        else y :: push x xs

  let insert x t =
    if t.size < t.bound then begin
      t.size <- t.size + 1 ;
      t.data <- push x t.data
    end else if E.compare (List.hd t.data) x < 0 then
      t.data <- push x (List.tl t.data)

  let get { data ; _ } = data

end

let take_n_sorted (type a) compare n l =
  let module B = Bounded(struct type t = a let compare = compare end) in
  let t = B.create n in
  List.iter (fun x -> B.insert x t) l ;
  B.get t

let take_n ?compare n l =
  match compare with
  | None -> take_n_unsorted n l
  | Some compare -> take_n_sorted compare n l

let select n l =
  let rec loop n acc = function
    | [] -> invalid_arg "Utils.select"
    | x :: xs when n <= 0 -> x, List.rev_append acc xs
    | x :: xs -> loop (pred n) (x :: acc) xs
  in
  loop n [] l

let shift = function
  | [] -> []
  | hd :: tl -> tl@[hd]

let rec product a b = match a with
  | [] -> []
  | hd :: tl -> (List.map (fun x -> (hd , x)) b) @ product tl b
