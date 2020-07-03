module F = Format

module Stmt = struct
  type t = {instr: Llvm.llvalue; location: string}

  let compare x y = compare x.instr y.instr

  let hash x = Hashtbl.hash x.instr

  let equal x y = x.instr == y.instr

  let make cache llctx instr =
    let location = Utils.string_of_location cache llctx instr in
    {instr; location}

  let opcode stmt = Llvm.instr_opcode stmt.instr

  let is_control_flow stmt = opcode stmt |> Utils.is_control_flow

  let to_json cache s =
    let common = [("location", `String s.location)] in
    let common =
      if !Options.include_instr then
        ("instr", `String (Utils.EnvCache.string_of_exp cache s.instr))
        :: common
      else common
    in
    match Utils.json_of_instr cache s.instr with
    | `Assoc l ->
        `Assoc (common @ l)
    | _ ->
        failwith "Stmt.to_json"

  let to_string s = Utils.SliceCache.string_of_exp s.instr

  let pp fmt s = F.fprintf fmt "%s" (Utils.SliceCache.string_of_exp s)
end

module Stack = struct
  type t = Llvm.llvalue list

  let empty = []

  let push x s = x :: s

  let pop = function x :: s -> Some (x, s) | [] -> None

  let is_empty s = s = []

  let length = List.length
end

module Symbol = struct
  type t = string [@@deriving yojson]

  let compare = compare

  let count = ref 0

  let new_symbol () =
    let sym = "$" ^ string_of_int !count in
    count := !count + 1 ;
    sym

  let to_string x = x

  let pp fmt x = F.fprintf fmt "%s" x

  let arg_symbol arg_id = "$A-" ^ string_of_int arg_id
end

module SymbolSet = Set.Make (Symbol)
module RetIdSet = Set.Make (Int)

module SymExpr = struct
  type t =
    | Symbol of Symbol.t
    | Int of Int64.t
    | Ret of int * string * t list
    | Add of t * t
    | Sub of t * t
    | Mul of t * t
    | Div of t * t
    | Rem of t * t
    | Shl of t * t
    | Lshr of t * t
    | Ashr of t * t
    | Band of t * t
    | Bor of t * t
    | Bxor of t * t
    | Peq of t * t
    | Pne of t * t
    | Pgt of t * t
    | Pge of t * t
    | Plt of t * t
    | Ple of t * t
  [@@deriving show, yojson {exn= true}]

  let new_symbol () = Symbol (Symbol.new_symbol ())

  let arg_symbol id = Symbol (Symbol.arg_symbol id)

  let of_int i = Int i

  let call_id = ref 0

  let new_ret f l =
    let ret = Ret (!call_id, f, l) in
    call_id := !call_id + 1 ;
    ret

  let get_used_symbols e =
    let rec helper res e =
      match e with
      | Symbol s ->
          SymbolSet.add s res
      | Ret (_, _, el) ->
          List.fold_left helper res el
      | Add (e1, e2)
      | Sub (e1, e2)
      | Mul (e1, e2)
      | Div (e1, e2)
      | Rem (e1, e2)
      | Shl (e1, e2)
      | Lshr (e1, e2)
      | Ashr (e1, e2)
      | Band (e1, e2)
      | Bor (e1, e2)
      | Bxor (e1, e2)
      | Peq (e1, e2)
      | Pne (e1, e2)
      | Pgt (e1, e2)
      | Pge (e1, e2)
      | Plt (e1, e2) ->
          helper (helper res e1) e2
      | _ ->
          res
    in
    helper SymbolSet.empty e

  let get_used_ret_ids e =
    let rec helper res e =
      match e with
      | Ret (id, _, el) ->
          List.fold_left helper (RetIdSet.add id res) el
      | Add (e1, e2)
      | Sub (e1, e2)
      | Mul (e1, e2)
      | Div (e1, e2)
      | Rem (e1, e2)
      | Shl (e1, e2)
      | Lshr (e1, e2)
      | Ashr (e1, e2)
      | Band (e1, e2)
      | Bor (e1, e2)
      | Bxor (e1, e2)
      | Peq (e1, e2)
      | Pne (e1, e2)
      | Pgt (e1, e2)
      | Pge (e1, e2)
      | Plt (e1, e2)
      | Ple (e1, e2) ->
          helper (helper res e1) e2
      | _ ->
          res
    in
    helper RetIdSet.empty e

  let rec num_of_symbol = function
    | Symbol _ ->
        1
    | Int _ ->
        0
    | Ret (_, _, el) ->
        List.fold_left (fun sum e -> num_of_symbol e + sum) 0 el
    | Add (e1, e2)
    | Sub (e1, e2)
    | Mul (e1, e2)
    | Div (e1, e2)
    | Rem (e1, e2)
    | Shl (e1, e2)
    | Lshr (e1, e2)
    | Ashr (e1, e2)
    | Band (e1, e2)
    | Bor (e1, e2)
    | Bxor (e1, e2)
    | Peq (e1, e2)
    | Pne (e1, e2)
    | Pgt (e1, e2)
    | Pge (e1, e2)
    | Plt (e1, e2)
    | Ple (e1, e2) ->
        num_of_symbol e1 + num_of_symbol e2

  let add se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Add (se1, se2)

  let sub se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Sub (se1, se2)

  let mul se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Mul (se1, se2)

  let div se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Div (se1, se2)

  let rem se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Rem (se1, se2)

  let shl se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Shl (se1, se2)

  let lshr se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Lshr (se1, se2)

  let ashr se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Ashr (se1, se2)

  let band se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Band (se1, se2)

  let bor se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Bor (se1, se2)

  let bxor se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Bxor (se1, se2)

  let peq se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Peq (se1, se2)

  let pne se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Pne (se1, se2)

  let pgt se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Pgt (se1, se2)

  let pge se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Pge (se1, se2)

  let plt se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Plt (se1, se2)

  let ple se1 se2 =
    if num_of_symbol se1 + num_of_symbol se2 > !Options.max_symbols then
      new_symbol ()
    else Ple (se1, se2)

  let icmp pred se1 se2 =
    match pred with
    | Llvm.Icmp.Eq ->
        peq se1 se2
    | Ne ->
        pne se1 se2
    | Ugt ->
        pgt se1 se2
    | Uge ->
        pge se1 se2
    | Ult ->
        plt se1 se2
    | Ule ->
        ple se1 se2
    | Sgt ->
        pgt se1 se2
    | Sge ->
        pge se1 se2
    | Slt ->
        plt se1 se2
    | Sle ->
        ple se1 se2
end

module Variable = struct
  type t = Llvm.llvalue

  let to_json cache t = `String (Utils.EnvCache.string_of_exp cache t)

  let compare = compare
end

module Address = struct
  type t = int

  let to_yojson t = `String ("&" ^ string_of_int t)
end

module Location = struct
  type t =
    | Address of Address.t
    | Argument of int
    | Variable of Variable.t
    | Global of Llvm.llvalue
    | SymExpr of SymExpr.t
    | Gep of t * int option list
    | Unknown

  let rec to_json cache l =
    match l with
    | Address a ->
        `List [`String "Address"; Address.to_yojson a]
    | Argument i ->
        `List [`String "Argument"; `Int i]
    | Variable v ->
        `List [`String "Variable"; Variable.to_json cache v]
    | SymExpr e ->
        `List [`String "SymExpr"; SymExpr.to_yojson e]
    | Gep (e, is) ->
        `List
          [ `String "Gep"
          ; to_json cache e
          ; `List (List.map (function Some i -> `Int i | None -> `Null) is) ]
    | Global g ->
        `List [`String "Global"; `String (Llvm.value_name g)]
    | Unknown ->
        `List [`String "Unknown"]

  let compare = compare

  let argument i = Argument i

  let variable v = Variable v

  let symexpr s = SymExpr s

  let gep_of is l = Gep (l, is)

  let global s = Global s

  let unknown = Unknown

  let count = ref (-1)

  let rec global_variable_of v =
    match v with
    | Global s ->
        Some s
    | Gep (l, _) ->
        global_variable_of l
    | _ ->
        None

  let new_address () =
    count := !count + 1 ;
    Address !count

  let new_symbol () = SymExpr (SymExpr.new_symbol ())

  let rec pp fmt = function
    | Address a ->
        F.fprintf fmt "&%d" a
    | Argument i ->
        F.fprintf fmt "Arg%d" i
    | Variable v ->
        let name = Llvm.value_name v in
        if name = "" then F.fprintf fmt "%s" (Utils.SliceCache.string_of_exp v)
        else F.fprintf fmt "%s" name
    | SymExpr s ->
        SymExpr.pp fmt s
    | Gep (l, is) ->
        F.fprintf fmt "Gep(%a, [%s])" pp l
          (String.concat "," (List.filter_map (Option.map string_of_int) is))
    | Global g ->
        F.fprintf fmt "Global%s" (Llvm.value_name g)
    | Unknown ->
        F.fprintf fmt "Unknown"

  let to_string x = pp F.str_formatter x ; F.flush_str_formatter ()
end

module Function = struct
  type t = Llvm.llvalue

  let to_yojson f = `String (Llvm.value_name f)
end

module Value = struct
  type t =
    | Function of Function.t
    | SymExpr of SymExpr.t
    | Int of Int64.t
    | Location of Location.t
    | Argument of int
    | Global of Llvm.llvalue
    | Unknown

  let to_json cache v =
    match v with
    | Function f ->
        `List [`String "Function"; Function.to_yojson f]
    | SymExpr e ->
        `List [`String "SymExpr"; SymExpr.to_yojson e]
    | Int i ->
        `List [`String "Int"; `Int (Int64.to_int i)]
    | Location l ->
        `List [`String "Location"; Location.to_json cache l]
    | Argument i ->
        `List [`String "Argument"; `Int i]
    | Global g ->
        `List [`String "Global"; `String (Llvm.value_name g)]
    | Unknown ->
        `List [`String "Unknown"]

  let new_symbol () = SymExpr (SymExpr.new_symbol ())

  let location l = Location l

  let func v = Function v

  let global s = Global s

  let unknown = Unknown

  let of_symexpr s = SymExpr s

  let to_symexpr = function
    | SymExpr s ->
        s
    | Int i ->
        SymExpr.of_int i
    | Argument id ->
        SymExpr.arg_symbol id
    | _ ->
        SymExpr.new_symbol ()

  (* Anthony: As we upgrade symbolic engine, I will use this function
   * to either encode a Value as a SymExpr that we support, or return
   * None. The following function, bind, will either unwrap the optional
   * SymExpr (think Maybe monad) or return Value.unknown. Until we fully
   * encode all Value into SymExpr, this option/bind hack will at least
   * make the cases for add, sub, etc cleaner *)
  let to_symexpr_opt = function
    | SymExpr s ->
        Some s
    | Int i ->
        Some (SymExpr.of_int i)
    | Argument id ->
        Some (SymExpr.arg_symbol id)
    | _ ->
        None

  let bind x f = match x with Some s -> f s | None -> unknown

  let ( >>= ) = bind

  let add v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.add i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.add se1 se2)

  let sub v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.sub i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.sub se1 se2)

  let mul v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.mul i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.mul se1 se2)

  let div v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 when i2 <> Int64.zero ->
        Int (Int64.div i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.div se1 se2)

  let rem v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 when i2 <> Int64.zero ->
        Int (Int64.rem i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.rem se1 se2)

  let shl v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.shift_left i1 (Int64.to_int i2))
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.shl se1 se2)

  let lshr v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.shift_right_logical i1 (Int64.to_int i2))
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.lshr se1 se2)

  let ashr v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.shift_right i1 (Int64.to_int i2))
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.ashr se1 se2)

  let band v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.logand i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.band se1 se2)

  let bor v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.logor i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.bor se1 se2)

  let bxor v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.logxor i1 i2)
    | _, _ ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.bxor se1 se2)

  let icmp instr v1 v2 =
    let pred = Llvm.icmp_predicate instr in
    match pred with
    | Some p ->
        to_symexpr_opt v1
        >>= fun se1 ->
        to_symexpr_opt v2 >>= fun se2 -> SymExpr (SymExpr.icmp p se1 se2)
    | None ->
        unknown

  let binary_op instr v1 v2 =
    let op = Llvm.instr_opcode instr in
    match op with
    | Llvm.Opcode.Add ->
        add v1 v2
    | Sub ->
        sub v1 v2
    | Mul ->
        mul v1 v2
    | UDiv ->
        div v1 v2
    | SDiv ->
        div v1 v2
    | URem ->
        rem v1 v2
    | SRem ->
        rem v1 v2
    | Shl ->
        shl v1 v2
    | LShr ->
        lshr v1 v2
    | AShr ->
        ashr v1 v2
    | And ->
        band v1 v2
    | Or ->
        bor v1 v2
    | Xor ->
        bxor v1 v2
    | ICmp ->
        icmp instr v1 v2
    | _ ->
        unknown

  let pp fmt = function
    | Function l ->
        F.fprintf fmt "Fun(%s)" (Llvm.value_name l)
    | SymExpr s ->
        SymExpr.pp fmt s
    | Int i ->
        F.fprintf fmt "%s" (Int64.to_string i)
    | Location l ->
        Location.pp fmt l
    | Argument i ->
        F.fprintf fmt "Arg%d" i
    | Global g ->
        F.fprintf fmt "Global %s" (Llvm.value_name g)
    | Unknown ->
        F.fprintf fmt "Unknown"
end

module Memory = struct
  module M = Map.Make (struct
    type t = Location.t

    let compare = Location.compare
  end)

  include M

  type t = Value.t M.t

  let add k v m = if k = Location.unknown then m else add k v m

  let find k v = match find_opt k v with Some w -> w | None -> Value.unknown

  let pp fmt m =
    F.fprintf fmt "===== Memory =====\n" ;
    iter (fun k v -> F.fprintf fmt "%a -> %a\n" Location.pp k Value.pp v) m ;
    F.fprintf fmt "==================\n"
end

module BlockSet = Set.Make (struct
  type t = Llvm.llbasicblock

  let compare = compare
end)

module FuncSet = Set.Make (struct
  type t = Llvm.llvalue

  let compare = compare
end)

module ReachingDef = struct
  include Map.Make (struct
    type t = Location.t

    let compare = Location.compare
  end)

  let add k v m = match k with Location.Unknown -> m | _ -> add k v m

  let pp fmt m =
    F.fprintf fmt "===== ReachingDef =====\n" ;
    iter (fun k v -> F.fprintf fmt "%a -> %a\n" Location.pp k Stmt.pp v) m ;
    F.fprintf fmt "=======================\n"
end

module Node = struct
  type t =
    {stmt: Stmt.t; id: int; mutable is_target: bool; semantic_sig: Yojson.Safe.t}

  let compare n1 n2 = compare n1.id n2.id

  let hash x = Hashtbl.hash x.id

  let equal = ( = )

  let make cache llctx instr id is_target semantic_sig =
    let stmt = Stmt.make cache llctx instr in
    {stmt; id; is_target; semantic_sig}

  let to_string v = string_of_int v.id

  let label v = "[" ^ v.stmt.location ^ "]\n" ^ Stmt.to_string v.stmt

  let to_json cache v =
    match (Stmt.to_json cache v.stmt, v.semantic_sig) with
    | `Assoc j, `Assoc k ->
        `Assoc ([("id", `Int v.id)] @ j @ k)
    | _ ->
        failwith "Node.to_json"
end

module Trace = struct
  type t = Node.t list

  let empty = []

  let is_empty t = t = []

  let append x t = x :: t

  let last = List.hd

  let length = List.length

  let to_json cache t =
    let l = List.fold_left (fun l x -> Node.to_json cache x :: l) [] t in
    `List l
end

module NodeSet = Set.Make (Node)

module FinishState = struct
  type t =
    | ProperlyReturned
    | BranchExplored
    | ExceedingMaxTraceLength
    | ExceedingMaxInstructionExplored
    | UnreachableStatement
  [@@deriving show, yojson {exn= true}]
end

module DUGraph = struct
  module Edge = struct
    type t = Data | Control

    let compare = compare

    let default = Data

    let is_data e = e = Data
  end

  include Graph.Persistent.Digraph.ConcreteBidirectionalLabeled (Node) (Edge)

  let pred_control g v =
    let preds = pred_e g v in
    List.filter (fun e -> E.label e = Edge.Control) preds |> List.map E.src

  let succ_control g v =
    let succs = succ_e g v in
    List.filter (fun e -> E.label e = Edge.Control) succs |> List.map E.dst

  let du_project g =
    fold_edges_e
      (fun e newg ->
        match E.label e with
        | Edge.Data ->
            newg
        | Edge.Control ->
            remove_edge_e newg e)
      g g

  let cf_project g =
    fold_edges_e
      (fun e newg ->
        match E.label e with
        | Edge.Control ->
            newg
        | Edge.Data ->
            remove_edge_e newg e)
      g g

  let graph_attributes g = []

  let edge_attributes e =
    match E.label e with Data -> [`Style `Dashed] | Control -> [`Style `Solid]

  let default_edge_attributes g = []

  let get_subgraph v = None

  let vertex_name v = "\"" ^ Node.to_string v ^ "\""

  let vertex_attributes v =
    let common = `Label (Node.label v) in
    if v.Node.is_target then
      [common; `Color 0x0000FF; `Style `Bold; `Style `Filled; `Fontcolor max_int]
    else [common]

  let default_vertex_attributes g = [`Shape `Box]

  let to_json cache (g, fstate) =
    let vertices, target_id =
      fold_vertex
        (fun v (l, t) ->
          let t = if v.Node.is_target then v.Node.id else t in
          let vertex = Node.to_json cache v in
          (vertex :: l, t))
        g ([], -1)
    in
    let du_edges, cf_edges =
      fold_edges_e
        (fun (src, e, dst) (du_edges, cf_edges) ->
          let edge = `List [`Int src.Node.id; `Int dst.Node.id] in
          match e with
          | Edge.Data ->
              (edge :: du_edges, cf_edges)
          | Control ->
              (du_edges, edge :: cf_edges))
        g ([], [])
    in
    `Assoc
      [ ("vertex", `List vertices)
      ; ("du_edge", `List du_edges)
      ; ("cf_edge", `List cf_edges)
      ; ("target", `Int target_id)
      ; ("finish_state", FinishState.to_yojson fstate) ]
end

module InstrMap = Map.Make (struct
  type t = Llvm.llvalue

  let compare = compare
end)

module NodeMap = Map.Make (Node)

module PathConstraints = struct
  type t = (Value.t * bool * int) list

  let append cond b bid t = (cond, b, bid) :: t

  let remove_append cond b bid t =
    if List.exists (fun (_, _, id) -> id = bid) t then
      List.filter (fun (_, _, id) -> id = bid) t
    else append cond b bid t

  let empty = []

  let pp fmt pc =
    F.fprintf fmt "===== Path =====\n" ;
    List.iter
      (fun (v, b, bid) -> F.fprintf fmt "%d :: %b = %a\n" bid b Value.pp v)
      pc ;
    F.fprintf fmt "================\n"

  let mk_solver ctx pc =
    let rec to_z3 cond =
      match cond with
      | SymExpr.Symbol s ->
          let sym = Z3.Symbol.mk_string ctx s in
          Z3.Arithmetic.Integer.mk_const ctx sym
      | Ret (id, _, _) ->
          let sym = Z3.Symbol.mk_int ctx id in
          Z3.Arithmetic.Integer.mk_const ctx sym
      | Int i ->
          Z3.Arithmetic.Integer.mk_numeral_i ctx (Int64.to_int i)
      | Add (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_add ctx [e1'; e2']
      | Sub (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_sub ctx [e1'; e2']
      | Mul (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_mul ctx [e1'; e2']
      | Div (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_div ctx e1' e2'
      | Rem (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.Integer.mk_mod ctx e1' e2'
      | Peq (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Boolean.mk_eq ctx e1' e2'
      | Pne (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          let ze = Z3.Boolean.mk_eq ctx e1' e2' in
          Z3.Boolean.mk_not ctx ze
      | Pgt (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_gt ctx e1' e2'
      | Pge (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_ge ctx e1' e2'
      | Plt (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_lt ctx e1' e2'
      | Ple (e1, e2) ->
          let e1' = to_z3 e1 in
          let e2' = to_z3 e2 in
          Z3.Arithmetic.mk_le ctx e1' e2'
      (* This will likely created a malformed expression *)
      | _ ->
          Z3.Boolean.mk_true ctx
    in
    let solver = Z3.Solver.mk_solver ctx None in
    List.iter
      (fun (v, b, _) ->
        let sv = Value.to_symexpr v in
        let ze = to_z3 sv in
        let cons = if b then ze else Z3.Boolean.mk_not ctx ze in
        Z3.Solver.add solver [cons])
      pc ;
    solver
end

module GlobalValueMap = Map.Make (struct
  type t = Llvm.llvalue

  let compare = compare
end)

module State = struct
  type t =
    { stack: Stack.t
    ; memory: Memory.t
    ; trace: Trace.t
    ; visited_blocks: BlockSet.t
    ; visited_funcs: FuncSet.t
    ; reachingdef: Llvm.llvalue ReachingDef.t
    ; dugraph: DUGraph.t
    ; instrmap: Node.t InstrMap.t
    ; target_instr: Llvm.llvalue option
    ; target_node: Node.t option
    ; prev_blk: Llvm.llbasicblock option
    ; path_cons: PathConstraints.t
    ; branchmap: int InstrMap.t
    ; global_use: Llvm.llvalue GlobalValueMap.t }

  let empty =
    { stack= Stack.empty
    ; memory= Memory.empty
    ; trace= Trace.empty
    ; visited_blocks= BlockSet.empty
    ; visited_funcs= FuncSet.empty
    ; reachingdef= ReachingDef.empty
    ; dugraph= DUGraph.empty
    ; instrmap= InstrMap.empty
    ; target_instr= None
    ; target_node= None
    ; prev_blk= None
    ; path_cons= PathConstraints.empty
    ; branchmap= InstrMap.empty
    ; global_use= GlobalValueMap.empty }

  let instr_count = ref (-1)

  let new_instr_count () =
    instr_count := !instr_count + 1 ;
    !instr_count

  let branch_count = ref (-1)

  let new_branch_count () =
    branch_count := !branch_count + 1 ;
    !branch_count

  let push_stack x s = {s with stack= Stack.push x s.stack}

  let pop_stack s =
    match Stack.pop s.stack with
    | Some (x, stk) ->
        Some (x, {s with stack= stk})
    | None ->
        None

  let is_target_instr instr s =
    match s.target_instr with Some t -> t = instr | None -> false

  let add_trace cache llctx instr semantic_sig s =
    let new_id = new_instr_count () in
    let is_tgt = is_target_instr instr s in
    let node = Node.make cache llctx instr new_id is_tgt semantic_sig in
    let instrmap = InstrMap.add instr node s.instrmap in
    let dugraph =
      if !Options.no_control_flow || Trace.is_empty s.trace then s.dugraph
      else
        let src = Trace.last s.trace in
        DUGraph.add_edge_e s.dugraph (src, DUGraph.Edge.Control, node)
    in
    let target_node = if is_tgt then Some node else s.target_node in
    {s with trace= Trace.append node s.trace; target_node; instrmap; dugraph}

  let add_memory x v s = {s with memory= Memory.add x v s.memory}

  let visit_block block s =
    {s with visited_blocks= BlockSet.add block s.visited_blocks}

  let visited_block block s = BlockSet.mem block s.visited_blocks

  let visit_func func s =
    {s with visited_funcs= FuncSet.add func s.visited_funcs}

  let add_reaching_def loc instr s =
    {s with reachingdef= ReachingDef.add loc instr s.reachingdef}

  let add_memory_def x v instr s =
    { s with
      memory= Memory.add x v s.memory
    ; reachingdef= ReachingDef.add x instr s.reachingdef }

  let add_du_edge src dst s =
    let src = InstrMap.find src s.instrmap in
    let dst = InstrMap.find dst s.instrmap in
    {s with dugraph= DUGraph.add_edge s.dugraph src dst}

  let add_semantic_du_edges lv_list instr s =
    let dugraph =
      List.fold_left
        (fun dugraph lv ->
          match ReachingDef.find lv s.reachingdef with
          | v ->
              let src = InstrMap.find v s.instrmap in
              let dst = InstrMap.find instr s.instrmap in
              if src != dst then DUGraph.add_edge dugraph src dst else dugraph
          | exception Not_found ->
              dugraph)
        s.dugraph lv_list
    in
    {s with dugraph}

  let set_target_instr t s = {s with target_instr= Some t}

  (* Anthony : We are hacking here. If there is a path condition already in the
   * path constraints for this branch id, we remove it (permit the path). This is
   * done to address loops which are troublesome at the moment because we concretize
   * values but do not execute all iterations of the loop.
   *
   * Ziyang and Anthony have discussed that if we continue down this path of symbolic
   * execution, we need rewrite the backend to better use symbolic expressions. As it stands,
   * its currently a mix of LLVM Location encodings and symbolic expressions. *)
  let add_path_cons cons b bid s =
    {s with path_cons= PathConstraints.remove_append cons b bid s.path_cons}

  (*
  let add_path_cons cons b bid s =
    {s with path_cons= PathConstraints.append cons b bid s.path_cons} *)

  let add_global_du_edges lv_list instr state =
    let dugraph =
      List.fold_left
        (fun dugraph lv ->
          match Location.global_variable_of lv with
          | Some v -> (
            match GlobalValueMap.find_opt v state.global_use with
            | Some used_instr -> (
                let src = InstrMap.find_opt used_instr state.instrmap in
                let dst = InstrMap.find_opt instr state.instrmap in
                match (src, dst) with
                | Some src, Some dst ->
                    DUGraph.add_edge dugraph src dst
                | _ ->
                    dugraph )
            | None ->
                dugraph )
          | _ ->
              dugraph)
        state.dugraph lv_list
    in
    {state with dugraph}

  let use_global global_var expr s =
    { s with
      global_use=
        GlobalValueMap.update global_var (fun _ -> Some expr) s.global_use }

  let add_global_use (expr : Llvm.llvalue) (s : t) =
    List.fold_left
      (fun s global_var -> use_global global_var expr s)
      s (Utils.used_globals expr)

  let add_branch instr s =
    match InstrMap.find_opt instr s.branchmap with
    | None ->
        let bid = new_branch_count () in
        {s with branchmap= InstrMap.add instr bid s.branchmap}
    | _ ->
        s

  let get_branch_id instr s = InstrMap.find instr s.branchmap
end
