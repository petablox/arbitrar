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
  [@@deriving show, yojson {exn= true}]

  let new_symbol () = Symbol (Symbol.new_symbol ())

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
      | Bxor (e1, e2) ->
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
      | Bxor (e1, e2) ->
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
    | Bxor (e1, e2) ->
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
end

module Variable = struct
  type t = Llvm.llvalue

  let to_json cache t = `String (Utils.EnvCache.string_of_exp cache t)
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
    | SymExpr of SymExpr.t
    | Gep of t
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
    | Gep e ->
        `List [`String "Gep"; to_json cache e]
    | Unknown ->
        `List [`String "Unknown"]

  let compare = compare

  let argument i = Argument i

  let variable v = Variable v

  let symexpr s = SymExpr s

  let gep_of l = Gep l

  let unknown = Unknown

  let count = ref (-1)

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
    | Gep l ->
        F.fprintf fmt "Gep(%a)" pp l
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
    | Unknown ->
        `List [`String "Unknown"]

  let new_symbol () = SymExpr (SymExpr.new_symbol ())

  let location l = Location l

  let func v = Function v

  let unknown = Unknown

  let of_symexpr s = SymExpr s

  let to_symexpr = function
    | SymExpr s ->
        s
    | Int i ->
        SymExpr.of_int i
    | _ ->
        SymExpr.new_symbol ()

  let add v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.add i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.add se1 se2)
    | Int i, SymExpr se | SymExpr se, Int i ->
        SymExpr (SymExpr.add se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let sub v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.add i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.sub se1 se2)
    | Int i, SymExpr se ->
        SymExpr (SymExpr.sub (SymExpr.of_int i) se)
    | SymExpr se, Int i ->
        SymExpr (SymExpr.sub se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let mul v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.add i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.mul se1 se2)
    | Int i, SymExpr se | SymExpr se, Int i ->
        SymExpr (SymExpr.mul se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let div v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 when i2 <> Int64.zero ->
        Int (Int64.div i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.div se1 se2)
    | Int i, SymExpr se ->
        SymExpr (SymExpr.div (SymExpr.of_int i) se)
    | SymExpr se, Int i ->
        SymExpr (SymExpr.div se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let rem v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 when i2 <> Int64.zero ->
        Int (Int64.rem i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.rem se1 se2)
    | Int i, SymExpr se ->
        SymExpr (SymExpr.rem (SymExpr.of_int i) se)
    | SymExpr se, Int i ->
        SymExpr (SymExpr.rem se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let shl v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.shift_left i1 (Int64.to_int i2))
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.shl se1 se2)
    | Int i, SymExpr se ->
        SymExpr (SymExpr.shl (SymExpr.of_int i) se)
    | SymExpr se, Int i ->
        SymExpr (SymExpr.shl se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let lshr v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.shift_right_logical i1 (Int64.to_int i2))
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.lshr se1 se2)
    | Int i, SymExpr se ->
        SymExpr (SymExpr.lshr (SymExpr.of_int i) se)
    | SymExpr se, Int i ->
        SymExpr (SymExpr.lshr se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let ashr v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.shift_right i1 (Int64.to_int i2))
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.ashr se1 se2)
    | Int i, SymExpr se ->
        SymExpr (SymExpr.ashr (SymExpr.of_int i) se)
    | SymExpr se, Int i ->
        SymExpr (SymExpr.ashr se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let band v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.logand i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.band se1 se2)
    | Int i, SymExpr se | SymExpr se, Int i ->
        SymExpr (SymExpr.band se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let bor v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.logor i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.bor se1 se2)
    | Int i, SymExpr se | SymExpr se, Int i ->
        SymExpr (SymExpr.bor se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let bxor v1 v2 =
    match (v1, v2) with
    | Int i1, Int i2 ->
        Int (Int64.logxor i1 i2)
    | SymExpr se1, SymExpr se2 ->
        SymExpr (SymExpr.bxor se1 se2)
    | Int i, SymExpr se | SymExpr se, Int i ->
        SymExpr (SymExpr.bxor se (SymExpr.of_int i))
    | _, _ ->
        unknown

  let binary_op op v1 v2 =
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

  let to_json cache g =
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
      ; ("target", `Int target_id) ]
end

module InstrMap = Map.Make (struct
  type t = Llvm.llvalue

  let compare = compare
end)

module NodeMap = Map.Make (Node)

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
    ; prev_blk: Llvm.llbasicblock option }

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
    ; prev_blk= None }

  let instr_count = ref (-1)

  let new_instr_count () =
    instr_count := !instr_count + 1 ;
    !instr_count

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
              DUGraph.add_edge dugraph src dst
          | exception Not_found ->
              dugraph)
        s.dugraph lv_list
    in
    {s with dugraph}

  let set_target_instr t s = {s with target_instr= Some t}
end
