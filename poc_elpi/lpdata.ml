(* elpi: embedded lambda prolog interpreter                                  *)
(* copyright: 2014 - Enrico Tassi <enrico.tassi@inria.fr>                    *)
(* license: GNU Lesser General Public License Version 2.1                    *)
(* ------------------------------------------------------------------------- *)

module F = Format

module L : sig (* {{{ Lists *)


  type 'a t
  val empty : 'a t
  val singl : 'a -> 'a t
  val init : int -> (int -> 'a) -> 'a t
  val get : int -> 'a t -> 'a
  val len : 'a t -> int
  val sub : int -> int -> 'a t -> 'a t
  val tl : 'a t -> 'a t
  val hd : 'a t -> 'a
  val map : ('a -> 'b) -> 'a t -> 'b t
  val mapi : (int -> 'a -> 'b) -> 'a t -> 'b t
  val fold_map : ('a -> 'b -> 'c * 'b) -> 'a t -> 'b -> 'c t * 'b
  val fold : ('a -> 'b -> 'b) -> 'a t -> 'b -> 'b
  val fold2 : ('a -> 'b -> 'c -> 'c) -> 'a t -> 'b t -> 'c -> 'c
  val for_all : ('a -> bool) -> 'a t -> bool
  val for_alli : (int -> 'a -> bool) -> 'a t -> bool
  val for_all2 : ('a -> 'b -> bool) -> 'a t -> 'b t -> bool
  val exists : ('a -> bool) -> 'a t -> bool
  val of_list : 'a list-> 'a t
  val to_list : 'a t -> 'a list
  val filter : ('a -> bool) -> 'a t -> 'a t
  val filter_acc : ('a -> 'b -> bool * 'b) -> 'a t -> 'b -> 'a t * 'b
  val append : 'a t -> 'a t -> 'a t
  val cons : 'a -> 'a t -> 'a t
  val uniq : ('a -> 'a -> bool) -> 'a t -> bool
  val rev : 'a t -> 'a t

  (* }}} *)
end  = struct (* {{{ *)
  
  type 'a t = 'a list
  let empty = []
  let singl a = [a]
  let init i f =
    let rec aux j = if i = j then [] else f j :: aux (j+1) in aux 0
  let get i l = List.nth l i
  let len l = List.length l
  let sub i j l =
    let rec aux n l = if n = j + i then [] else
    match l with
    | [] -> assert false
    | x :: xs when n < i -> aux (n+1) xs
    | x :: xs -> x :: aux (n+1) xs
    in aux 0 l
  let tl l = List.tl l
  let hd l = List.hd l
  let map f l = List.map f l
  let mapi f l =
    let rec aux n = function
      | [] -> []
      | x::xs -> f n x :: aux (n+1) xs
    in aux 0 l
  let rec fold_map f l a =
    match l with
    | [] -> [], a
    | x::xs -> let x, a = f x a in let xs, a = fold_map f xs a in x::xs, a
  let rec fold f l a =
    match l with
    | [] -> a
    | x::xs -> fold f xs (f x a)
  let rec fold2 f l1 l2 a =
    match l1, l2 with
    | [], [] -> a
    | x::xs,y::ys -> fold2 f xs ys (f x y a)
    | _ -> assert false
  let for_all f l = List.for_all f l
  let exists f l = List.exists f l
  let for_alli f l =
    let rec aux n = function
      | [] -> true
      | x::xs -> f n x && aux (n+1) xs
    in aux 0 l
  let rec for_all2 f l1 l2 =
    match l1, l2 with
    | [], [] -> true
    | x::xs, y::ys -> f x y && for_all2 f xs ys
    | _ -> false
  let of_list l = l
  let to_list l = l
  let filter f l = List.filter f l
  let filter_acc f l acc =
    let rec aux a = function
      | [] -> [], a
      | x::xs ->
          let b, a = f x a in
          if b then let xs, a = aux a xs in x :: xs, a
          else aux a xs
    in aux acc l
  let append l1 l2 = l1 @ l2
  let cons x l = x :: l
  let rec uniq equal = function
    | [] -> true
    | x::xs -> List.for_all (fun y -> not(equal x y)) xs && uniq equal xs
  let rev = List.rev

end (* }}} *)

module Opt = struct
 
  let pred2 f o1 o2 = match o1, o2 with
    | Some x, Some y -> f x y
    | None, None -> true
    | _ -> false

  let map f o =
    match o with
    | None -> None
    | Some x -> let y = f x in if x == y then o else Some y

  let iter f o = match o with None -> () | Some x -> f x
  
  let fold f a o = match o with None -> a | Some x -> f x a
  let fold_map f a o = match o with
    | None -> None, a
    | Some x -> let x, a = f x a in Some x, a
  
  let fold2 f a o1 o2 =
    match o1,o2 with
    | None, _ | _, None -> a
    | Some x, Some y -> f x y a

end

module C : sig (* {{{ External, user defined, datatypes *)

  type t
  type ty
  type data = {
    t : t;
    ty : ty;
  }

  val declare : ('a -> string) -> ('a -> 'a -> bool) -> ('a -> data) * (data -> bool) * (data -> 'a)
  
  val print : data -> string
  val equal : data -> data -> bool

(* }}} *)
end = struct (* {{{ *)

type t = Obj.t
type ty = int

type data = {
  t : Obj.t;
  ty : int
}

module M = Int.Map
let m : ((data -> string) * (data -> data -> bool)) M.t ref = ref M.empty

let cget x = Obj.obj x.t
let print x = fst (M.find x.ty !m) x
let equal x y = x.ty = y.ty && snd (M.find x.ty !m) x y

let fresh_tid =
  let tid = ref 0 in
  fun () -> incr tid; !tid

let declare print cmp =
  let tid = fresh_tid () in
  m := M.add tid ((fun x -> print (cget x)),
                  (fun x y -> cmp (cget x) (cget y))) !m;
  (fun v -> { t = Obj.repr v; ty = tid }),
  (fun c -> c.ty = tid),
  (fun c -> assert(c.ty = tid); cget c)

end (* }}} *)

let mkString, isString, getString = C.declare (fun x -> "\""^x^"\"") (=)

module PPLIB = struct (* {{{ auxiliary lib for PP *)

let on_buffer f x =
  let b = Buffer.create 1024 in
  let fmt = F.formatter_of_buffer b in
  f fmt x;
  F.pp_print_flush fmt ();
  Buffer.contents b
let iter_sep spc pp fmt l =
  let rec aux n = function
    | [] -> ()
    | [x] -> pp fmt x
    | _ when n = 0 ->
         F.fprintf fmt "%s" (F.pp_get_ellipsis_text fmt ())
    | x::tl -> pp fmt x; spc fmt (); aux (n-1) tl in
  aux (F.pp_get_max_boxes fmt ()) l


end (* }}} *)
open PPLIB

module Name : sig
  type t
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val make : string -> t
  val to_string : t -> string
end = struct
  type t = int * string
  let id = ref 0
  let tbl = Hashtbl.create 97
  let make x =
    try Hashtbl.find tbl x
    with Not_found -> incr id; let v = !id,x in Hashtbl.add tbl x v; v
  let compare (id1,_) (id2,_) = compare id1 id2
  let equal = (==)
  let to_string (_,x) = x
end
  
module NameMap = Map.Make(Name)

let digit_sup = function
  | 0 -> "⁰" | 1 -> "¹" | 2 -> "²" | 3 -> "³" | 4 -> "⁴" | 5 -> "⁵"
  | 6 -> "⁶" | 7 -> "⁷" | 8 -> "⁸" | 9 -> "⁹" | _ -> assert false
let digit_sub = function
  | 0 -> "₀" | 1 -> "₁" | 2 -> "₂" | 3 -> "₃" | 4 -> "₄" | 5 -> "₅"
  | 6 -> "₆" | 7 -> "₇" | 8 -> "₈" | 9 -> "₉" | _ -> assert false
let rec digits_of n = n mod 10 :: if n >= 10 then digits_of (n / 10) else []
let subscript n =
  String.concat "" (List.map digit_sub (List.rev (digits_of n)))
let superscript n =
  String.concat "" (List.map digit_sup (List.rev (digits_of n)))

module LP = struct

(* Based on "A Simplified Suspension Calculus and its Relationship to Other
   Explicit Substitution Calculi", Andrew Gacek and Gopalan Nadathur.
   Research Report 2007/39, Digital Technology Center, University of Minnesota.
*)

type var = int
type level = int
type name = Name.t

type olam = int
type nlam = int

type appkind = [ `Regular | `Rev | `Flex | `Frozen ]

module DATA : sig

  type data

  type kind_of_data = private
    | Uv of var * level
    | Con of name * level (* level < 0 has to be considered as 0 *)
    | DB of int
    | Bin of int * data
    | App of data L.t
    | Seq of data L.t * data
    | Nil
    | Ext of C.data
    | VApp of appkind * data * data * data option
              (* VApp(hd,args,info) : args is a list *)

  val look : data -> kind_of_data
  val kool : kind_of_data -> data
  
  val mkUv : var -> level -> data
  val mkCon : string -> level -> data
  val mkConN : name -> level -> data
  val mkDB : int -> data
  val mkBin : int -> data -> data
  val mkApp : data L.t -> data
  val mkVApp : appkind -> data -> data -> data option -> data
  val mkExt : C.data -> data
  val mkSeq : data L.t -> data -> data
  val mkNil : data

  val mkAppv : data -> data L.t -> int -> int -> data
  val fixApp : data L.t -> data

  val equal : data -> data -> bool
  val compare : data -> data -> int
  
  val isDB : int -> data -> bool
  val isBin : data -> bool

  val collect_Uv : data -> data list
  val collect_hv : data -> data list

  val prf_data : string list -> Format.formatter -> data -> unit
  val prf_data_low : 
    ?pars:bool -> string list -> F.formatter ->
    ?reccal:(?pars:bool -> string list -> data -> unit) ->
    data -> unit
  val fresh_names : string -> int -> int -> string list
  val string_of_data : ?ctx:string list -> data -> string
  val pr_var : int -> int -> string
  val prf_data_only : string list -> Format.formatter -> data -> unit

  val map : (data -> data) -> data -> data
  val mapi : (int -> data -> data) -> int -> data -> data

  val grab : data -> int -> data -> data

  val lift : ?from:int -> int -> data -> data
  val beta : data -> int -> int -> data L.t -> data

end = struct

type kind_of_data =
  | Uv of var * level
  | Con of name * level (* lvl < 0 means frozen meta and -lvl=var *)
  | DB of int
  | Bin of int * data
  | App of data L.t
  | Seq of data L.t * data
  | Nil
  | Ext of C.data
  | VApp of appkind * data * data * data option
and data =
  | XUv of var * level
  | XCon of name * level
  | XDB of int
  | XBin of int * data
  | XApp of data L.t
  | XSeq of data L.t * data
  | XNil
  | XExt of C.data
  | XVApp of appkind * data * data * data option
  | XSusp of suspended_job ref
and suspended_job = Done of data | Todo of data * olam * nlam * env
and env =
  | XEmpty
  | XArgs of data L.t * int * env
  | XMerge of env * nlam * olam * env
  | XSkip of int * nlam * env

module PP = struct (* {{{ pretty printer for data *)

let string_of_level lvl =
  if !Trace.dverbose then "^" ^ string_of_int lvl
  else if lvl = 0 then ""
  else superscript lvl

let pr_cst x lvl =
  Name.to_string x ^ if !Trace.dverbose then string_of_level lvl else ""
let pr_var x lvl =
  "X" ^ string_of_int x ^ if !Trace.dverbose then string_of_level lvl else ""

let rec fresh_names w k = function
  | 0 -> []
  | n -> (w ^ string_of_int k) :: fresh_names w (k+1) (n-1)

let rec self fmt ?pars ctx t = prf_data_low ?pars ctx fmt t
and prf_data_low ?(pars=false) ctx fmt ?(reccal=self fmt) = function
    | XBin (n,x) ->
       F.pp_open_hovbox fmt 2;
       let names = fresh_names "w" (List.length ctx) n in
       if pars then F.pp_print_string fmt "(";
       F.pp_print_string fmt (String.concat "\\ " names ^ "\\");
       F.pp_print_space fmt ();
       reccal (List.rev names @ ctx) x;
       if pars then F.pp_print_string fmt ")";
       F.pp_close_box fmt ()
    | XDB x -> F.pp_print_string fmt 
        (try (if !Trace.dverbose then "'" else "") ^List.nth ctx (x-1)
        with Failure _ | Invalid_argument _ ->
          "_" ^ string_of_int (x-List.length ctx))
    | XCon (x,lvl) -> F.pp_print_string fmt (pr_cst x lvl)
    | XUv (x,lvl) -> F.pp_print_string fmt (pr_var x lvl)
    | XApp xs ->
        F.pp_open_hovbox fmt 2;
        if pars then F.pp_print_string fmt "(";
        iter_sep F.pp_print_space (fun _ -> reccal ~pars:true ctx)
          fmt (L.to_list xs);
        if pars then F.pp_print_string fmt ")";
        F.pp_close_box fmt ()
    | XSeq (xs, XNil) ->
        F.fprintf fmt "@[<hov 2>[";
        iter_sep (fun fmt () -> F.fprintf fmt ",@ ") (fun _ -> reccal ctx)
          fmt (L.to_list xs);
        F.fprintf fmt "]@]";
    | XSeq (xs, t) ->
        F.fprintf fmt "@[<hov 2>[";
        iter_sep (fun fmt () -> F.fprintf fmt ",@ ") (fun _ -> reccal ctx)
          fmt (L.to_list xs);
        F.fprintf fmt "|@ ";
        reccal ctx t;
        F.fprintf fmt "]@]";
    | XNil -> F.fprintf fmt "[]";
    | XExt x ->
        F.pp_open_hbox fmt ();
        F.pp_print_string fmt (C.print x);
        F.pp_close_box fmt ()
    | XVApp(b,t1,t2,o) ->
        let t1, t2 = if b == `Rev then t2, t1 else t1, t2 in
        F.fprintf fmt "@[<hov 2>";
        if pars then F.pp_print_string fmt "(";
        if b <> `Rev then F.fprintf fmt "@@";
        reccal ctx ~pars:true t1;
        F.fprintf fmt "@ ";
        reccal ctx ~pars:true t2;
        Opt.iter (fun t ->
          F.fprintf fmt "@ "; reccal ctx ~pars:true t) o;
        if b == `Rev then F.fprintf fmt "@@";
        if pars then F.pp_print_string fmt ")";
        F.fprintf fmt "@]"
    | XSusp ptr ->
        match !ptr with
        | Done t -> F.fprintf fmt ".(@["; reccal ctx t; F.fprintf fmt ")@]"
        | Todo(t,ol,nl,e) ->
            F.fprintf fmt "@[<hov 2>⟦";
            reccal ctx t;
            F.fprintf fmt ",@ %d, %d,@ " ol nl;
            prf_env ctx fmt e;
            F.fprintf fmt "⟧@]";

and prf_env ctx fmt e =
  let rec print_env = function
    | XEmpty -> F.pp_print_string fmt "nil"
    | XArgs(a,n,e) ->
        F.fprintf fmt "(@[<hov 2>";
        iter_sep (fun fmt () -> F.fprintf fmt ",@ ")
          (fun fmt t -> prf_data_low ctx fmt t) fmt (L.to_list a);
        F.fprintf fmt "@]|%d)@ :: " n;
        print_env e
    | XMerge(e1,nl1,ol2,e2) ->
        F.fprintf fmt "@[<hov 2>⦃";
        print_env e1;
        F.fprintf fmt ",@ %d, %d,@ " nl1 ol2;
        print_env e2;
        F.fprintf fmt "⦄@]";
    | XSkip(n,m,e) ->
        F.fprintf fmt "@@(%d,%d)@ :: " n m;
        print_env e;
  in
    F.pp_open_hovbox fmt 2;
    print_env e;
    F.pp_close_box fmt ()

let prf_data ctx fmt p = prf_data_low ctx fmt p
let prf_data_only = prf_data

let string_of_data ?(ctx=[]) t = on_buffer (prf_data ctx) t
let string_of_env ?(ctx=[]) e = on_buffer (prf_env ctx) e

end (* }}} *)
include PP

let (--) x y = max 0 (x - y)
let mkXSusp t n o e = XSusp(ref(Todo(t,n,o,e)))

let mkSkip n l e = if n <= 0 then e else XSkip(n,l,e)

let rule s = SPY "rule" F.pp_print_string s

let rec epush e = TRACE "epush" (fun fmt -> prf_env [] fmt e)
  match e with
  | (XEmpty | XArgs _ | XSkip _) as x -> x
  | XMerge(e1,nl1,ol2,e2) -> let e1 = epush e1 in let e2 = epush e2 in
  match e1, e2 with
  | e1, XEmpty when ol2 = 0 -> (*m2*) e1
  | XEmpty, e2 when nl1 = 0 -> (*m3*) e2
  | XEmpty, XArgs(a,l,e2) -> rule"m4";
      let nargs = L.len a in
      if nl1 = nargs then e2 (* repeat m4, end m3 *)
      else if nl1 > nargs then epush (XMerge(XEmpty,nl1 -nargs, ol2 -nargs, e2))
      else XArgs(L.sub nl1 (nargs-nl1) a,l,e2) (* repeat m4 + m3 *)
  | XEmpty, XSkip(a,l,e2) -> rule"m4";
      if nl1 = a then e2 (* repeat m4, end m3 *)
      else if nl1 > a then epush (XMerge(XEmpty,nl1 - a, ol2 - a, e2))
      else XSkip(a-nl1,l-nl1,e2) (* repeast m4 + m3 *)
  | (XArgs(_,n,_) | XSkip(_,n,_)) as e1, XArgs(b,l,e2) when nl1 > n -> rule"m5";
      let drop = min (L.len b) (nl1 - n) in
      if drop = L.len b then
        epush (XMerge(e1,nl1 - drop, ol2 - drop, e2))
      else   
        epush (XMerge(e1,nl1 - drop, ol2 - drop,
          XArgs(L.sub 0 (L.len b - drop) b,l,e2)))
  | (XArgs(_,n,_) | XSkip(_,n,_)) as e1, XSkip(b,l,e2) when nl1 > n -> rule"m5";
      let drop = min b (nl1 - n) in
      epush (XMerge(e1,nl1 - drop, ol2 - drop, mkSkip (b - drop) (l-drop) e2))
  | XArgs(a,n,e1), ((XArgs(_,l,_) | XSkip(_,l,_)) as e2) -> rule"m6";
      assert(nl1 = n);
      let m = l + (n -- ol2) in
      XArgs(L.map (fun t -> mkXSusp t ol2 l e2) a, m, e2)
  | XSkip(a,n,e1), ((XArgs(_,l,_) | XSkip(_,l,_)) as e2) -> rule"m6";
      assert(nl1 = n);
      let m = l + (n -- ol2) in
      let e1 = mkSkip (a-1) (n-1) e1 in
      XArgs(L.singl (mkXSusp (XDB 1) 0 l e2), m, XMerge(e1,n,ol2,e2))
  | XArgs _, XEmpty -> assert false
  | XEmpty, XEmpty -> assert false
  | XSkip _, XEmpty -> assert false
  | ((XMerge _, _) | (_, XMerge _)) -> assert false

let mkBin n t =
  if n = 0 then t
  else match t with
    | XBin(n',t) -> XBin(n+n',t)
    | _ -> XBin(n,t)

let store ptr v = ptr := Done v; v
let rec psusp ptr t ol nl e =
  TRACE "psusp ptr"
    (fun fmt -> prf_data [] fmt (XSusp { contents = Todo(t,ol,nl,e) }))
  match t with
  | XSusp { contents = Done t } -> psusp ptr t ol nl e
  | XSusp { contents = Todo (t,ol1,nl1,e1) } -> rule"m1";
      psusp ptr t (ol1 + (ol -- nl1)) (nl + (nl1 -- ol)) (XMerge(e1,nl1,ol,e))
  | (XCon _ | XExt _ | XNil) as x -> rule"r1"; x
  | XUv _ as x -> store ptr x
  | XBin(n,t) -> rule"r6";
      assert(n > 0);
      store ptr (mkBin n (mkXSusp t (ol+n) (nl+n) (XSkip(n,nl+n,e))))
  | XApp a -> rule"r5";
      store ptr (XApp(L.map (fun t -> mkXSusp t ol nl e) a))
  | XVApp(b,t1,t2,o) -> rule"r5bis";
      store ptr (XVApp(b,mkXSusp t1 ol nl e,mkXSusp t2 ol nl e,
                       Opt.map (fun t -> mkXSusp t ol nl e) o))
  | XSeq(a,tl) ->
      store ptr (XSeq(L.map (fun t -> mkXSusp t ol nl e) a, mkXSusp tl ol nl e))
  | XDB i -> (* r2, r3, r4 *)
      let e = epush e in
      SPY "epushed" (prf_env []) e;
      match e with
      | XMerge _ -> assert false
      | XEmpty -> rule"r2"; assert(ol = 0); store ptr (XDB(i+nl))
      | XArgs(a,l,e) ->
          let nargs = L.len a in
          if i <= nargs
          then (rule"r3"; psusp ptr (L.get (nargs - i) a) 0 (nl - l) XEmpty)
          else (rule"r4"; psusp ptr (XDB(i - nargs)) (ol - nargs) nl e)
      | XSkip(n,l,e) -> 
          if (i <= n)
          then (rule"r3"; store ptr (XDB(i + nl - l)))
          else (rule"r4"; psusp ptr (XDB(i - n)) (ol - n) nl e)
let push t =
  match t with
  | (XUv _ | XCon _ | XDB _ | XBin _ | XApp _
    | XExt _ | XSeq _ | XNil | XVApp _) -> t
  | XSusp { contents = Done t } -> t
  | XSusp ({ contents = Todo (t,ol,nl,e) } as ptr) -> psusp ptr t ol nl e

let look x =
  let x = push x in
  SPY "pushed" (prf_data []) x;
  Obj.magic x
(*
  match x with
  | XUv (v,l) -> Uv(v,l)
  | XCon (n,l) -> Con(n,l)
  | XDB i -> DB i
  | XBin (n,t) -> Bin(n,t)
  | XApp a -> App a
  | XSeq (a,tl) -> Seq (a,tl)
  | XNil -> Nil
  | XExt e -> Ext e
  | XSusp _ -> assert false
*)
let mkUv v l = XUv(v,l)
let mkCon n l = XCon(Name.make n,l)
let mkConN n l = XCon(n,l)
let mkDB i = XDB i
let mkExt x = XExt x
let rec mkSeq xs tl =
 if L.len xs = 0 then tl else
  match tl with
  | XSeq (ys,tl) -> mkSeq (L.append xs ys) tl
  | _ -> XSeq(xs,tl)
let mkNil = XNil
let kool = Obj.magic (*function
  | Uv (v,l) -> XUv(v,l)
  | Con (n,l) -> XCon(n,l)
  | DB i -> XDB i
  | Bin (n,t) -> XBin(n,t)
  | App a -> XApp a
  | Seq (a,tl) -> XSeq (a,tl)
  | Nil -> XNil
  | Ext e -> XExt e*)

let mkBin n t =
  if n = 0 then t
  else match t with
    | XBin(n',t) -> XBin(n+n',t)
    | _ -> XBin(n,t)

let mkApp xs = if L.len xs = 1 then L.hd xs else XApp xs
let mkAppv t v start stop =
  if start = stop then t else
  match t with
  | XApp xs -> XApp(L.append xs (L.sub start (stop-start) v))
  | _ -> XApp(L.cons t (L.sub start (stop-start) v))

let fixApp xs =
  match push (L.hd xs) with
  | XApp ys -> XApp (L.append ys (L.tl xs))
  | _ -> XApp xs

let isDB i = function XDB j when j = i -> true | _ -> false

let mkVApp b t1 t2 o = XVApp(b,t1,t2,o)

let rec equal a b = match push a, push b with
 | XUv (x,_), XUv (y,_) -> x = y
 | XCon (x,_), XCon (y,_) -> Name.equal x y
 | XDB x, XDB y -> x = y
 | XBin (n1,x), XBin (n2,y) -> n1 = n2 && equal x y
 | XApp xs, XApp ys -> L.for_all2 equal xs ys
 | XExt x, XExt y -> C.equal x y
 | XSeq(xs,s), XSeq(ys,t) -> L.for_all2 equal xs ys && equal s t
 | XNil, XNil -> true
 | XVApp (b1,t1,t2,o1), XVApp (b2,s1,s2,o2) ->
      b1 == b2 && equal t1 s2 && equal t2 s2 && Opt.pred2 equal o1 o2
 | XVApp (_,t1,t2,None), _ when equal t2 mkNil -> equal t1 b
 | _, XVApp (_,t1,t2,None) when equal t2 mkNil -> equal a t1
 | (XVApp (_,t1,t2,None), XApp _) ->
     (match look t2 with
     | XSeq (ys,tl) when equal tl mkNil -> equal (mkApp (L.cons t1 ys)) b
     | XSeq (ys,tl) -> false
     | _ -> false)
 | (XApp _, XVApp (_,t1,t2,None)) ->
     (match look t2 with
     | XSeq (ys,tl) when equal tl mkNil -> equal a (mkApp (L.cons t1 ys))
     | XSeq (ys,tl) -> false
     | _ -> false)
 | ((XBin(n,x), y) | (y, XBin(n,x))) -> begin (* eta *)
     match push x with
     | XApp xs ->
        let nxs = L.len xs in
        let eargs = nxs - n in
           eargs > 0
        && L.for_alli (fun i t -> isDB (n-i) t) (L.sub eargs n xs)
        && equal (mkApp (L.sub 0 eargs xs)) (mkXSusp y 0 n XEmpty)
     | _ -> false
   end
 | _ -> false

let compare t1 t2 =
  if equal t1 t2 then 0
  else match push t1, push t2 with
  | XCon(x,_), XCon(y,_) -> Name.compare x y
  (* TODO : complete *)
  | a, b -> compare a b

let isBin x = match push x with XBin _ -> true | _ -> false

let rec map f x = match push x with
  | (XDB _ | XCon _ | XUv _ | XExt _ | XNil) as x -> f x
  | XBin (ns,x) -> XBin(ns, map f x)
  | XApp xs -> XApp(L.map (map f) xs)
  | XSeq (xs, tl) -> let xs = L.map (map f) xs in XSeq(xs, map f tl)
  | XVApp(b,t1,t2,o) ->
      let t1 = map f t1 in
      let t2 = map f t2 in
      let o = Opt.map (map f) o in
      XVApp(b,t1,t2,o)
  | XSusp _ -> assert false

let rec mapi f i x = match push x with
  | (XDB _ | XCon _ | XUv _ | XExt _ | XNil) as x -> f i x
  | XBin (ns,x) -> XBin(ns, mapi f (i+ns) x)
  | XApp xs -> XApp(L.map (mapi f i) xs)
  | XSeq (xs, tl) -> let xs = L.map (mapi f i) xs in XSeq(xs, mapi f i tl)
  | XVApp(b,t1,t2,o) ->
      let t1 = mapi f i t1 in
      let t2 = mapi f i t2 in
      let o = Opt.map (mapi f i) o in
      XVApp(b,t1,t2,o)
  | XSusp _ -> assert false
 

let collect_Uv t =
  let uvs = ref [] in
  let _ =
    map (function XUv(n,_) as x -> uvs := (n,x) :: !uvs; x | x -> x) t in
  let rec uniq seen = function
    | [] -> seen
    | (x,_) as y :: tl ->
       if List.exists (fun (w,_) -> w == x) seen then uniq seen tl
       else uniq (y :: seen) tl
  in
  List.map snd (uniq [] !uvs)

let collect_hv t =
  let hvs = ref [] in
  let _ =
    map (function XCon(n,l) as x when l > 0 -> hvs := (n,x) :: !hvs; x | x -> x) t in
  let rec uniq seen = function
    | [] -> seen
    | (x,_) as y :: tl ->
       if List.exists (fun (w,_) -> Name.equal x w) seen then uniq seen tl
       else uniq (y :: seen) tl
  in
  List.map snd (uniq [] !hvs)

let rec grab c n = function
  | (XCon _ | XUv _) as x when equal x c -> mkDB n
  | XVApp(b,t1,t2,o) ->
      XVApp(b,grab c n t1, grab c n t2,Opt.map (grab c n) o)
  | (XCon _ | XUv _ | XExt _ | XDB _ | XNil) as x -> x
  | XBin(w,t) -> XBin(w,grab c (n+w) t)
  | XApp xs -> XApp (L.map (grab c n) xs)
  | XSeq (xs,tl) -> XSeq(L.map (grab c n) xs, grab c n tl)
  | XSusp _ -> assert false

let lift ?(from=0) k t =
  if k = 0 then t
  else if from = 0 then mkXSusp t 0 k XEmpty
  else mkXSusp t from (from+k) (XSkip(k,from,XEmpty))

let beta t start len v = rule"Bs";
  let rdx = mkXSusp t len 0 (XArgs(L.sub start len v, 0, XEmpty)) in
  SPY "rdx" (prf_data []) rdx;
  rdx

end

include DATA

let sentinel = mkExt (mkString "T8fNhK/8Wk6Ds")

(* PROGRAM *)

type key = Key of data | Flex

module CN : sig
  type t
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val make : ?float:[ `Here | `Begin | `End ] -> ?existing:bool -> string -> t
  val fresh : unit -> t
  val pp : F.formatter -> t -> unit
  val to_string : t -> string
end = struct
  type t = Name.t * [ `Here | `Begin | `End ]
  let equal (a,_) (b,_) = Name.equal a b
  let compare (_,oa as a) (_,ob as b) =
    if equal a b then 0
    else if oa == ob then 0
    else if oa == `Begin || ob == `End then ~-1
    else 1
  let to_string (x,_) = Name.to_string x
  module S = Set.Make(String)
  let all = ref S.empty
  let fresh = ref 0
  let rec make ?(float=`Here) ?(existing=false) s =
    if existing then (assert(S.mem s !all); Name.make s, float) else
    if S.mem s !all then make ~float (incr fresh; s ^ string_of_int !fresh)
    else (all := S.add s !all; Name.make s, float)
  let fresh () = incr fresh; make ("hyp" ^ string_of_int !fresh)
  let pp fmt (t,_) = F.fprintf fmt "%s" (Name.to_string t)
end

type program = annot_clause list
and annot_clause = data option list * key * clause * CN.t (* level, key, clause, id *)
and clause = premise
and premise = data
and goal = premise

let eq_clause (_,_,_,n1) (_,_,_,n2) = CN.equal n1 n2
let cmp_clause (_,_,_,n1) (_,_,_,n2) = CN.compare n1 n2

let mkCApp name args = mkApp L.(of_list (mkConN name 0 :: args))
let mkAtom x = x
let unif_name = Name.make "*unif*"
let mkAtomBiUnif x y = mkCApp unif_name [x; y]
let context_name = Name.make "*context*"
let mkAtomBiContext x = mkCApp context_name [x]
let custom_name = Name.make "*custom*"
let mkAtomBiCustom name x = mkCApp custom_name [mkExt (mkString name); x]
let cut_name = Name.make "*cut*"
let mkAtomBiCut = mkConN cut_name 0
let conj_name = Name.make "*conj*"
let mkConj l = mkCApp conj_name (L.to_list l)
let impl_name = Name.make "*impl*"
let mkImpl x y = mkCApp impl_name [x; y]
let pi_name = Name.make "*pi*"
let mkPi1 annot p = match annot with
  | None -> mkCApp pi_name [mkBin 1 p]
  | Some t -> mkCApp pi_name [t;mkBin 1 p]
let sigma_name = Name.make "*sigma*"
let mkSigma1 p = mkCApp sigma_name [mkBin 1 p]
let delay_name = Name.make "*delay*"
let no_name = Name.make "*nothing*"
let nothing = mkConN no_name 0
let mkDelay k p vars info =
  match vars, info with
  | None, None -> mkCApp delay_name [k; p; nothing; nothing]
  | None, Some i -> mkCApp delay_name [k; p; nothing; i]
  | Some v, None -> mkCApp delay_name [k; p; v; nothing]
  | Some v, Some i -> mkCApp delay_name [k; p; v; i]
let resume_name = Name.make "*resume*"
let mkResume k p = mkCApp resume_name [k;p]

type builtin =
  | BIUnif of data * data
  | BICustom of string * data
  | BICut
  | BIContext of data
type kind_of_premise =
  | Atom of data
  | AtomBI of builtin
  | Conj of premise L.t
  | Impl of clause * premise
  | Pi of data option * premise
  | Sigma of premise
  | Delay of data * premise * data option * data option
  | Resume of data * premise

let collect_Uv_premise = collect_Uv
let collect_hv_premise = collect_hv

let rec destBin x =
  match look x with
  | Bin(n,t) when isBin t -> let m, t = destBin t in n+m, t
  | Bin(n,t) -> n, t
  | _ -> F.eprintf "%a\n%!" (prf_data []) x; assert false
let destBin1 t = let n, t = destBin t in assert(n = 1); t
let destExt x = match look x with Ext t -> t | _ -> assert false
let look_premise p =
  match look p with
  | App xs as a ->
      (match look (L.hd xs) with
      | Con(name,0) when Name.equal name unif_name ->
          AtomBI(BIUnif(L.get 1 xs,L.get 2 xs))
      | Con(name,0) when Name.equal name context_name ->
          AtomBI(BIContext (L.get 1 xs))
      | Con(name,0) when Name.equal name custom_name ->
          AtomBI(BICustom(getString (destExt (L.get 1 xs)),L.get 2 xs))
      | Con(name,0) when Name.equal name conj_name ->
          Conj(L.tl xs)
      | Con(name,0) when Name.equal name impl_name ->
          Impl(L.get 1 xs, L.get 2 xs)
      | Con(name,0) when Name.equal name pi_name ->
          if L.len xs = 2 then Pi(None, destBin1 (L.get 1 xs))
          else Pi(Some (L.get 1 xs), destBin1 (L.get 2 xs))
      | Con(name,0) when Name.equal name sigma_name ->
          Sigma (destBin1 (L.get 1 xs))
      | Con(name,0) when Name.equal name delay_name ->
          let v, i = L.get 3 xs, L.get 4 xs in
          let v = if equal v nothing then None else Some v in
          let i = if equal i nothing then None else Some i in
          Delay(L.get 1 xs, L.get 2 xs, v, i)
      | Con(name,0) when Name.equal name resume_name ->
          Resume(L.get 1 xs, L.get 2 xs)
      | _ -> Atom (kool a))
  | Con(name,0) when Name.equal name cut_name -> AtomBI BICut
  | Con(name,0) when Name.equal name conj_name -> Conj L.empty
  | a -> Atom (kool a)

let isConj p =
  match look_premise p with Conj _ -> true | _ -> false
let destConj p =
  match look_premise p with Conj l -> L.to_list l | _ -> assert false
let isAtom p =
  match look_premise p with Atom _ -> true | _ -> false
let destAtom p =
  match look_premise p with Atom t -> t | _ -> assert false

let mkConj l =
  let rec aux acc = function
    | [] -> mkConj (L.of_list (List.flatten (List.rev acc)))
    | p::rest when isConj p -> aux (destConj p :: acc) rest
    | p::rest -> aux ([p] :: acc) rest
  in
    aux [] (L.to_list l)

let map_premise = map
let mapi_premise = mapi

module PPP = struct (* {{{ pretty printer for programs *)

open F

let prf_builtin ctx fmt = function
  | BIUnif (a,b) -> 
      fprintf fmt "@[<hv 2>%a@ = %a@]" (prf_data ctx) a (prf_data ctx) b
  | BICustom(name,t) -> fprintf fmt "@[<hov 2>%s %a@]" name (prf_data ctx) t
  | BICut -> fprintf fmt "!"
  | BIContext t -> fprintf fmt "@[<hov 2>context@ %a@]" (prf_data ctx) t

let rec prf_premise ?(pars=false) ?(positive=false) ctx fmt p =
  match look_premise p with
  | Atom p ->
      prf_data_low ~pars
        ~reccal:(fun ?pars ctx -> prf_premise ?pars ctx fmt) ctx fmt p
  | AtomBI bi -> prf_builtin ctx fmt bi
  | Conj l when L.len l = 0 -> fprintf fmt ""
  | Conj l when L.len l = 1 -> prf_premise ~positive ~pars ctx fmt (L.hd l)
  | Conj l ->
       pp_open_hovbox fmt 0; (* if compact *)
       if pars then pp_print_string fmt "(";
       iter_sep (fun fmt () ->
         pp_print_string fmt ","; pp_print_space fmt ())
         (prf_premise ~positive ctx) fmt (L.to_list l);
       if pars then pp_print_string fmt ")";
       pp_close_box fmt ()
  | Pi (annot,p) ->
       let names = fresh_names "y" (List.length ctx) 1 in
       pp_open_hvbox fmt 2;
       pp_print_string fmt "pi ";
       begin match annot with
       | Some t ->
           prf_premise ~positive ~pars:true ctx fmt t;
           pp_print_space fmt ();
       | None -> () end;
       pp_print_string fmt (String.concat "\\ " names ^ "\\");
       pp_print_space fmt ();
       prf_premise ~positive ~pars (List.rev names @ ctx) fmt p;
       pp_close_box fmt ()
  | Sigma p ->
       let names = fresh_names "X" (List.length ctx) 1 in
       pp_open_hvbox fmt 2;
       pp_print_string fmt ("sigma "^String.concat "\\ " names ^ "\\");
       pp_print_space fmt ();
       prf_premise ~positive ~pars (List.rev names @ ctx) fmt p;
       pp_close_box fmt ()
  | Impl (x,p) ->
       let l, r, sep, neg_pars =
         if positive then x, p, "=> ",true else p, x, ":- ", false in
       pp_open_hvbox fmt 2;
       if pars then pp_print_string fmt "(";
       prf_premise ~pars:neg_pars ~positive:(not positive) ctx fmt l;
       if not (equal r (mkConj L.empty)) then begin
         if not (equal l (mkConj L.empty)) then begin
           pp_print_space fmt ();
           pp_open_hovbox fmt 0;
           pp_print_string fmt sep;
         end;
         prf_premise ~pars:false ~positive:true ctx fmt r;
         if not (equal l (mkConj L.empty)) then pp_close_box fmt ();
       end;
       if pars then pp_print_string fmt ")";
       pp_close_box fmt ()
  | Delay(t,p,v,i) ->
       fprintf fmt "delay @[";
       prf_data ctx fmt t;
       fprintf fmt "@ (";
       prf_premise ~pars:false ~positive ctx fmt p;
       fprintf fmt ")";
       Opt.iter (fun x -> fprintf fmt "@ in@ "; prf_data ctx fmt x) v;
       Opt.iter (fun x -> fprintf fmt "@ with@ "; prf_data ctx fmt x) v;
       fprintf fmt "@]"
  | Resume(t,p) ->
       fprintf fmt "resume @[";
       prf_data ctx fmt t;
       fprintf fmt "@ (";
       prf_premise ~pars:false ~positive ctx fmt p;
       fprintf fmt ")@]"

let prf_clause ?(dot=true) ?positive ctx fmt c =
  let c, ctx = match look_premise c with
    | Sigma c -> c, fresh_names "X" 0 1 @ ctx
    | _ -> c, ctx in
  pp_open_hbox fmt ();
  prf_premise ?positive ctx fmt c;
  if dot then pp_print_string fmt ".";
  pp_close_box fmt ()

let prf_data ctx fmt p = prf_premise ctx fmt p
let prf_premise ctx fmt = prf_premise ctx fmt
let string_of_premise p = on_buffer (prf_premise []) p
let string_of_goal = string_of_premise
let prf_goal ctx = prf_clause ~dot:false ~positive:true ctx
let prf_clause ctx fmt c = prf_clause ctx fmt c

let string_of_head = string_of_data

let string_of_clause c = on_buffer (prf_clause []) c

let prf_program ?(compact=false) fmt p =
  let p = List.map (fun _, _, p, _ -> p) p in
  if compact then pp_open_hovbox fmt 0
  else pp_open_vbox fmt 0;
  iter_sep (pp_print_space) (prf_clause []) fmt p;
  pp_close_box fmt ()
let string_of_program p = on_buffer prf_program p

let rec key_of p = match look_premise p with
  | AtomBI _ -> Flex
  | Conj _ -> assert false
  | Impl(_,p) | Pi(_,p) | Sigma p -> key_of p
  | Delay _ -> Flex
  | Resume _ -> Flex
  | Atom t ->
      match look t with
      | Con _ -> Key t
      | App xs -> Key(L.hd xs)
      | _ -> Flex

end (* }}} *)
include PPP

module Parser : sig (* {{{ parser for LP programs *)

  val parse_program : ?ontop:program -> string -> program
  val parse_goal : string -> goal
  val parse_data : string -> data

  val mkFreshCon : string -> int -> data

(* }}} *)
end = struct (* {{{ *)

let rec number = lexer [ '0'-'9' number ]
let rec ident =
  lexer [ [ 'a'-'z' | 'A'-'Z' | '\'' | '_' | '-' | '0'-'9' ] ident
        | '^' '0'-'9' number | ]

let rec string = lexer [ '"' | _ string ]

let lvl_name_of s =
  match Str.split (Str.regexp_string "^") s with
  | [ x ] -> Name.make x, 0
  | [ x;l ] -> Name.make x, int_of_string l
  | _ -> raise (Token.Error ("<name> ^ <number> expected.  Got: " ^ s))

let tok = lexer
  [ 'A'-'Z' ident -> "UVAR", $buf 
  | 'a'-'z' ident -> "CONSTANT", $buf
  | '_' '0'-'9' number -> "REL", $buf
  | '_' -> "FRESHUV", "_"
  |  ":-"  -> "ENTAILS",$buf
  |  ":"  -> "COLON",$buf
  |  "::"  -> "CONS",$buf
  | ',' -> "COMMA",","
  | '.' -> "FULLSTOP","."
  | '\\' -> "BIND","\\"
  | '/' -> "BIND","/"
  | '(' -> "LPAREN","("
  | ')' -> "RPAREN",")"
  | '[' -> "LBRACKET","["
  | ']' -> "RBRACKET","]"
  | '|' -> "PIPE","|"
  | "=>" -> "IMPL", $buf
  | '=' -> "EQUAL","="
  | '<' -> "LT","<"
  | '>' -> "GT",">"
  | '$' 'a'-'z' ident -> "BUILTIN",$buf
  | '!' -> "BANG", $buf
  | '@' -> "AT", $buf
  | '#' -> "SHARP", $buf
  | '?' -> "QMARK", $buf
  | '"' string -> "LITERAL", let b = $buf in String.sub b 1 (String.length b-2)
]

let option_eq x y = match x, y with Some x, Some y -> x == y | _ -> x == y

let rec lex c = parser bp
  | [< '( ' ' | '\n' | '\t' ); s >] -> lex c s
  | [< '( '%' ); s >] -> comment c s
  | [< '( '/' ); s >] ep ->
       if option_eq (Stream.peek s) (Some '*') then comment2 c s
       else ("BIND", "/"), (bp,ep)
  | [< s >] ep ->
       if option_eq (Stream.peek s) None then ("EOF",""), (bp, ep)
       else
       (match tok c s with
       | "CONSTANT","pi" -> "PI", "pi"
       | "CONSTANT","sigma" -> "SIGMA", "sigma"
       | "CONSTANT","nil" -> "NIL", "nil"
       | "CONSTANT","delay" -> "DELAY","delay"
       | "CONSTANT","in" -> "IN","in"
       | "CONSTANT","with" -> "WITH","with"
       | "CONSTANT","resume" -> "RESUME","resume"
       | "CONSTANT","context" -> "CONTEXT","context"
       | x -> x), (bp, ep)
and comment c = parser
  | [< '( '\n' ); s >] -> lex c s
  | [< '_ ; s >] -> comment c s
and comment2 c = parser
  | [< '( '*' ); s >] ->
       if option_eq (Stream.peek s) (Some '/') then (Stream.junk s; lex c s)
       else comment2 c s
  | [< '_ ; s >] -> comment2 c s


open Plexing

let lex_fun s =
  let tab = Hashtbl.create 207 in
  let last = ref Ploc.dummy in
  (Stream.from (fun id ->
     let tok, loc = lex Lexbuf.empty s in
     last := Ploc.make_unlined loc;
     Hashtbl.add tab id !last;
     Some tok)),
  (fun id -> try Hashtbl.find tab id with Not_found -> !last)

let tok_match (s1,_) = (); function
  | (s2,v) when Pervasives.compare s1 s2 == 0 -> v
  | (s2,v) -> raise Stream.Failure

let lex = {
  tok_func = lex_fun;
  tok_using = (fun _ -> ());
  tok_removing = (fun _ -> ());
  tok_match = tok_match;
  tok_text = (function (s,_) -> s);
  tok_comm = None;
}

let g = Grammar.gcreate lex
let lp = Grammar.Entry.create g "lp"
let premise = Grammar.Entry.create g "premise"
let atom = Grammar.Entry.create g "atom"
let goal = Grammar.Entry.create g "goal"

let uvmap = ref []
let conmap = ref []
let reset () = uvmap := []; conmap := []
let uvlist () = List.map snd !uvmap

let get_uv u =
  if List.mem_assoc u !uvmap then List.assoc u !uvmap
  else
    let n = List.length !uvmap in
    uvmap := (u,n) :: !uvmap;
    n
let fresh_lvl_name () = lvl_name_of (Printf.sprintf "_%d" (List.length !uvmap))

let check_con n l =
  try
    let l' = List.assoc n !conmap in
    if l <> l' then
      raise
        (Token.Error("Constant "^Name.to_string n^" used at different levels"))
  with Not_found -> conmap := (n,l) :: !conmap
let mkFreshCon name lvl =
  let name = Name.make name in
  let t = mkConN name lvl in
  assert(not(List.mem_assoc name !conmap));
  conmap := (name,lvl) :: !conmap;
  t

let sigma_abstract t =
  let uvl = collect_Uv t in
  List.fold_left (fun p uv -> mkSigma1 (grab uv 1 p)) t uvl

(* TODO : test that it is of the form of a clause *)
let check_clause x = ()
let check_goal x = ()

let atom_levels =
  ["pi";"conjunction";"implication";"equality";"term";"app";"simple";"list"]

let () =
  Grammar.extend [ Grammar.Entry.obj atom, None,
    List.map (fun x -> Some x, Some Gramext.NonA, []) atom_levels ]

EXTEND
  GLOBAL: lp premise atom goal;
  lp: [ [ cl = LIST0 clause; EOF -> cl ] ];
  name : [ [ c = CONSTANT -> c | u = UVAR -> u | FRESHUV -> "_" ] ];
  label : [ [ COLON;
              n = name;
              p = OPT [ LT; n = name -> `Before n | GT; n = name -> `After n ];
              COLON -> n,p ] ];
  clause :
    [[ name = OPT label;
       hd = concl; hyp = OPT [ ENTAILS; hyp = premise -> hyp ]; FULLSTOP ->
         let name, insertion = match name with
         | None -> CN.fresh (), `Here
         | Some (s,pos) -> match pos with
             | None -> CN.make s, `Here
             | Some (`Before "_") -> CN.make ~float:`Begin s, `Begin
             | Some (`After "_") -> CN.make ~float:`End s, `End
             | Some (`Before n) -> CN.make s, `Before(CN.make ~existing:true n)
             | Some (`After n) -> CN.make s, `After(CN.make ~existing:true n) in
         let hyp = match hyp with None -> mkConj L.empty | Some h -> h in
         let clause = sigma_abstract (mkImpl hyp (mkAtom hd)) in
         check_clause clause;
         reset (); 
         ([], key_of clause, clause, name), insertion ]];
  goal:
    [[ p = premise ->
         let g = sigma_abstract p in
         check_goal g;
         reset ();
         g ]];
  premise : [[ a = atom -> a ]];
  concl : [[ a = atom LEVEL "term" -> a ]];
  atom : LEVEL "pi"
     [[ PI; x = bound; BIND; p = atom LEVEL "conjunction" ->
         let (x, is_uv), annot = x, None in
         let bind = if is_uv then mkSigma1 else mkPi1 annot in
         bind (grab x 1 p)
      | PI; annot = bound; x = bound; BIND; p = atom LEVEL "conjunction" ->
         let (x, is_uv), annot = x, Some (fst annot) in
         let bind = if is_uv then mkSigma1 else mkPi1 annot in
         bind (grab x 1 p)
      | PI; LPAREN; annot = atom LEVEL "conjunction"; RPAREN;
        x = bound; BIND; p = atom LEVEL "conjunction" ->
         let (x, is_uv), annot = x, Some annot in
         let bind = if is_uv then mkSigma1 else mkPi1 annot in
         bind (grab x 1 p)
      | PI; annot = atom LEVEL "list";
        x = bound; BIND; p = atom LEVEL "conjunction" ->
         let (x, is_uv), annot = x, Some annot in
         let bind = if is_uv then mkSigma1 else mkPi1 annot in
         bind (grab x 1 p)
      | SIGMA; x = bound; BIND; p = atom LEVEL "conjunction" ->
         mkSigma1 (grab (fst x) 1 p) ]];
  atom : LEVEL "conjunction"
     [[ l = LIST1 atom LEVEL "implication" SEP COMMA ->
          if List.length l = 1 then List.hd l
          else mkConj (L.of_list l) ]];
  atom : LEVEL "implication"
     [[ a = atom; IMPL; p = atom LEVEL "implication" ->
          mkImpl (mkAtom a) (mkAtom p)
      | a = atom; ENTAILS; p = premise ->
          mkImpl (mkAtom p) (mkAtom a) ]];
  atom : LEVEL "equality"
     [[ a = atom; EQUAL; b = atom LEVEL "term" ->
          mkAtomBiUnif a b ]];
  atom : LEVEL "term"
     [[ l = LIST1 atom LEVEL "app" SEP CONS ->
          if List.length l = 1 then List.hd l
          else
            let l = List.rev l in
            let last = List.hd l in
            let rest = List.rev (List.tl l) in
            mkSeq (L.of_list rest) last ]];
  atom : LEVEL "app"
     [[ hd = atom; args = LIST1 atom LEVEL "simple" ->
          match args with
          | [tl;x] when equal x sentinel -> mkVApp `Rev tl hd None
          | _ -> mkApp (L.of_list (hd :: args)) ]];
  atom : LEVEL "simple" 
     [[ c = CONSTANT; b = OPT [ BIND; a = atom LEVEL "term" -> a ] ->
          let c, lvl = lvl_name_of c in 
          let x = mkConN c lvl in
          (match b with
          | None -> check_con c lvl; x
          | Some b ->  mkBin 1 (grab x 1 b))
      | u = UVAR -> let u, lvl = lvl_name_of u in mkUv (get_uv u) lvl
      | u = FRESHUV -> let u, lvl = fresh_lvl_name () in mkUv (get_uv u) lvl
      | i = REL -> mkDB (int_of_string (String.sub i 1 (String.length i - 1)))
      | NIL -> mkNil
      | s = LITERAL -> mkExt (mkString s)
      | AT; hd = atom LEVEL "simple"; args = atom LEVEL "simple" ->
          mkVApp `Regular hd args None
      | AT -> sentinel
      | CONTEXT; hd = atom LEVEL "simple" -> mkAtomBiContext hd
      | QMARK; hd = atom LEVEL "simple"; args = atom LEVEL "simple" ->
          mkVApp `Flex hd args None
      | SHARP; hd = atom LEVEL "simple"; args = atom LEVEL "simple";
        info = OPT atom LEVEL "simple" ->
          mkVApp `Frozen hd args info
      | bt = BUILTIN; a = atom LEVEL "simple" -> mkAtomBiCustom bt a
      | BANG -> mkAtomBiCut
      | DELAY; t = atom LEVEL "simple"; p = atom LEVEL "simple";
        vars = OPT [ IN; x = atom LEVEL "simple" -> x ];
        info = OPT [ WITH; x = atom LEVEL "simple" -> x ] ->
          mkDelay t p vars info
      | RESUME; t = atom LEVEL "simple"; p = atom LEVEL "simple" -> mkResume t p
      | LPAREN; a = atom; RPAREN -> a ]];
  atom : LEVEL "list" 
     [[ LBRACKET; xs = LIST0 atom LEVEL "implication" SEP COMMA;
          tl = OPT [ PIPE; x = atom LEVEL "term" -> x ]; RBRACKET ->
          let tl = match tl with None -> mkNil | Some x -> x in
          if List.length xs = 0 && tl <> mkNil then 
            raise (Token.Error ("List with not elements cannot have a tail"));
          if List.length xs = 0 then mkNil
          else mkSeq (L.of_list xs) tl ]];
  bound : 
    [ [ c = CONSTANT -> let c, lvl = lvl_name_of c in mkConN c lvl, false
      | u = UVAR -> let u, lvl = lvl_name_of u in mkUv (get_uv u) lvl, true ]
    ];
END

let parse e s =
  reset ();
  try Grammar.Entry.parse e (Stream.of_string s)
  with Ploc.Exc(l,(Token.Error msg | Stream.Error msg)) ->
    let last = Ploc.last_pos l in
    let ctx_len = 70 in
    let ctx =
      let start = max 0 (last - ctx_len) in
      let len = min 100 (min (String.length s - start) last) in
      "…" ^ String.sub s start len ^ "…" in
    raise (Stream.Error(Printf.sprintf "%s\nnear: %s" msg ctx))
  | Ploc.Exc(_,e) -> raise e

let parse_program ?(ontop=[]) s : program =
  let insertions = parse lp s in
  let insert prog = function
    | item, (`Here | `End) -> prog @ [item]
    | item, `Begin -> item :: prog
    | (_,_,_,name as item), `Before n ->
        let newprog = List.fold_left (fun acc (_,_,_,cn as c) ->
          if CN.equal n cn then acc @ [item;c]
          else acc @ [c]) [] prog in
        if List.length prog = List.length newprog then
          raise (Stream.Error ("unable to insert clause "^CN.to_string name));
        newprog
    | (_,_,_,name as item), `After n ->
        let newprog = List.fold_left (fun acc (_,_,_,cn as c) ->
          if CN.equal n cn then acc @ [c;item]
          else acc @ [c]) [] prog in
        if List.length prog = List.length newprog then
          raise (Stream.Error ("unable to insert clause "^CN.to_string name));
        newprog in
  List.fold_left insert ontop insertions

let parse_goal s : goal = parse goal s
let parse_data s : data = parse atom s

end (* }}} *)
include Parser

end

module Subst = struct (* {{{ LP.Uv |-> data mapping *)
open LP

module M = Int.Map

(* Positive indexes to assignements, negative to extra infos for frozen *)
type subst = { assign : data M.t; top_uv : int }
let empty n = { assign = M.empty; top_uv = max 1 n }

let last_sub_lookup = ref (mkDB 0)
let in_sub i { assign = assign } =
  try last_sub_lookup := M.find i assign; true
  with Not_found -> false
let in_sub_con lvl s = if lvl >= 0 then false else in_sub (-lvl) s
let set_sub i t s =
  SPY "sub" (fun fmt t -> F.fprintf fmt "%d <- %a" i (prf_data []) t) t;
  { s with assign = M.add i t s.assign }
let set_sub_con i t s = assert(i < 0);
  let m = if M.mem i s.assign then M.remove i s.assign else s.assign in
  { s with assign = M.add (-i) t m }
let rec set_info_con c t s = match look c with
  | Con(_,i) -> assert(i < 0); { s with assign = M.add i t s.assign }
  | App xs -> set_info_con (L.hd xs) t s
  | _ -> assert false
let rec get_info_con c s = match look c with
  | Con(_,i) ->
      (assert(i < 0);
      try Some (M.find i s.assign)
      with Not_found -> None)
  | App xs -> get_info_con (L.hd xs) s
  | _ -> assert false

let prf_subst fmt s =
  F.pp_open_hovbox fmt 2;
  F.pp_print_string fmt "{ ";
  iter_sep 
    (fun fmt () -> F.pp_print_string fmt ";";F.pp_print_space fmt ())
    (fun fmt (i,t) ->
       F.pp_open_hvbox fmt 0;
       F.pp_print_string fmt (pr_var i 0);
       F.pp_print_space fmt ();
       F.pp_print_string fmt ":= ";
       prf_data [] fmt (map (fun x -> kool (look x)) t);
       F.pp_close_box fmt ()) fmt
    (List.rev (M.bindings s.assign));
  F.pp_print_string fmt " }";
  F.pp_close_box fmt ()
let string_of_subst s = on_buffer prf_subst s

let apply_subst s t =
  let rec subst x = match look x with
    | Uv(i,_) when in_sub i s -> map subst !last_sub_lookup
    | Con(_,lvl) when in_sub_con lvl s -> map subst !last_sub_lookup
    | _ -> x in
  map subst t
let apply_subst_goal s = map_premise (apply_subst s)

let top s = s.top_uv
let raise_top i s = { s with top_uv = s.top_uv + i + 1 }

let fresh_uv lvl s = mkUv s.top_uv lvl, { s with top_uv = s.top_uv + 1 }
let frozen = ref 0
let freeze_uv i s =
  incr frozen;
  let ice = mkCon ("𝓕" ^ subscript !frozen) (-s.top_uv) in
  SPY "freeze"
    (fun fmt t -> F.fprintf fmt "%d <- %a" i (prf_data []) t) ice;
  ice, set_sub i ice { s with top_uv = s.top_uv + 1 }
let rec is_frozen t = match look t with
  | Con(_,lvl) when lvl < 0 -> true
  | App xs -> is_frozen (L.hd xs)
  | _ -> false

let prune id s = {s with assign = M.remove id s.assign }

end (* }}} *)

module Red = struct (* {{{ beta reduction, whd, and nf (for tests) *) 

open LP
open Subst

let lift = lift
let beta = beta

let rec splay xs tl s =
  let tl, s = whd tl s in
  match look tl with
  | Uv _ | Nil -> xs, tl, s
  | Seq(ys,t) -> splay (L.append xs ys) t s
  | _ -> xs, tl, s

and whd t s =
  TRACE "whd" (fun fmt -> prf_data [] fmt t)
  match look t with
  | (Ext _  | DB _ | Bin _ | Nil) as x -> kool x, s
  | Con(_,lvl) when in_sub_con lvl s ->
      let t = !last_sub_lookup in
      let t', s = whd t s in
      t', if t == t' then s else set_sub_con lvl t' s
  | Uv (i,_) when in_sub i s ->
      let t = !last_sub_lookup in
      let t', s = whd t s in
      t', if t == t' then s else set_sub i t' s
  | Con _ as x -> kool x, s
  | Uv _ -> t, s
  | VApp (b,hd,tl,_) ->
      let xs, tl, s = splay L.empty tl s in
      if equal tl mkNil then
        if b <> `Rev then whd (mkApp (L.cons hd xs)) s
        else whd (mkApp (L.cons hd (L.rev xs))) s
      else (*mkVApp b hd (mkSeq xs tl), s*) t,s
  | Seq(xs,tl) as x -> kool x, s
  | App v as x ->
      let hd = L.hd v in
      let hd', s = whd hd s in
      match look hd' with
      | Bin (n_lam,b) ->
        let n_args = L.len v - 1 in
        if n_lam = n_args then
          whd (beta b 1 n_args v) s
        else if n_lam < n_args then
          whd (mkAppv (beta b 1 n_lam v) v (n_lam+1) (n_args+1)) s
        else
          let diff = n_lam - n_args in
          (beta (mkBin diff b) 1 n_args v), s
      | _ ->
          if hd == hd' then kool x, s
          else mkAppv hd' (L.tl v) 0 (L.len v-1), s
          
let rec nf x s = match look x with
  | (Ext _ | DB _ | Nil) as x -> kool x, s
  | Con(_,lvl) as xf when lvl < 0 ->
      let x', s = whd x s in 
      (match look x' with
      | App xs -> nf_app xs s
      | _ -> if x == x' then kool xf, s else nf x' s)
  | Con _ as x -> kool x, s
  | Bin(n,t) -> let t, s = nf t s in mkBin n t, s
  | Seq(xs,t) ->
      let xs, s = L.fold_map nf xs s in
      let t, s = nf t s in
      mkSeq xs t, s
  | VApp(b,t1,t2,o) as xf -> 
      let x', s = whd x s in 
      (match look x' with
      | App xs -> nf_app xs s
      | VApp(b,t1,t2,o) ->
          let t1, s = nf t1 s in let t2, s = nf t2 s in mkVApp b t1 t2 o, s
      | _ -> if x == x' then kool xf, s else nf x' s)
  | (App _ | Uv _) as xf ->
      let x', s = whd x s in 
      (match look x' with
      | App xs -> nf_app xs s
      | _ -> if x == x' then kool xf, s else nf x' s)

and nf_app xs s = let xs, s = L.fold_map nf xs s in mkApp xs, s

end (* }}} *)

(* vim:set foldmethod=marker: *)