module F = Format

module Stmt = struct
  type t = {instr: Llvm.llvalue; location: string}

  let compare x y = compare x.instr y.instr

  let hash x = Hashtbl.hash x.instr

  let equal x y = x.instr == y.instr

  let make llctx instr =
    let location = Utils.string_of_location llctx instr in
    {instr; location}

  let to_json s =
    let common = [("location", `String s.location)] in
    let common =
      if !Options.include_instr then
        ("instr", `String (Utils.string_of_instr s.instr)) :: common
      else common
    in
    match Utils.json_of_instr s.instr with
    | `Assoc l ->
        `Assoc (common @ l)
    | _ ->
        failwith "Stmt.to_json"

  let to_string s = Utils.string_of_instr s.instr

  let pp fmt s = F.fprintf fmt "%s" (Utils.string_of_instr s)
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
  type t = string

  let count = ref 0

  let new_symbol () =
    let sym = "$" ^ string_of_int !count in
    count := !count + 1 ;
    sym

  let to_string x = x

  let pp fmt x = F.fprintf fmt "%s" x
end

module Location = struct
  type t =
    | Address of int
    | Variable of Llvm.llvalue
    | Symbol of Symbol.t
    | Unknown

  let compare = compare

  let variable v = Variable v

  let unknown = Unknown

  let count = ref (-1)

  let new_address () =
    count := !count + 1 ;
    Address !count

  let to_json = function
    | Address a ->
        `String ("&" ^ string_of_int a)
    | Variable l ->
        `String (Utils.string_of_exp l)
    | Symbol s ->
        `String (Symbol.to_string s)
    | Unknown ->
        `String "$unknown"

  let pp fmt = function
    | Address a ->
        F.fprintf fmt "&%d" a
    | Variable v ->
        let name = Llvm.value_name v in
        if name = "" then F.fprintf fmt "%s" (Utils.string_of_exp v)
        else F.fprintf fmt "%s" name
    | Symbol s ->
        Symbol.pp fmt s
    | Unknown ->
        F.fprintf fmt "Unknown"
end

module Value = struct
  type t =
    | Function of Llvm.llvalue
    | Symbol of Symbol.t
    | Int of Int64.t
    | Location of Location.t
    | Unknown

  let new_symbol () = Symbol (Symbol.new_symbol ())

  let location l = Location l

  let func v = Function v

  let unknown = Unknown

  let to_json = function
    | Function f ->
        `String (Llvm.value_name f)
    | Symbol s ->
        `String (Symbol.to_string s)
    | Int i ->
        `String (Int64.to_string i)
    | Location l ->
        Location.to_json l
    | Unknown ->
        `String "$unknown"

  let pp fmt = function
    | Function l ->
        F.fprintf fmt "Fun(%s)" (Llvm.value_name l)
    | Symbol s ->
        Symbol.pp fmt s
    | Int i ->
        F.fprintf fmt "%s" (Int64.to_string i)
    | Location l ->
        Location.pp fmt l
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
    { stmt: Stmt.t
    ; id: int
    ; mutable is_target: bool
    ; semantic_sig: Yojson.Safe.t }

  let compare n1 n2 = compare n1.id n2.id

  let hash x = Hashtbl.hash x.id

  let equal = ( = )

  let make llctx instr id is_target semantic_sig =
    let stmt = Stmt.make llctx instr in
    {stmt; id; is_target; semantic_sig}

  let to_string v = string_of_int v.id

  let label v = "[" ^ v.stmt.location ^ "]\n" ^ Stmt.to_string v.stmt

  let to_json v =
    match (Stmt.to_json v.stmt, v.semantic_sig) with
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

  let to_json t =
    let l = List.fold_left (fun l x -> Node.to_json x :: l) [] t in
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

  let graph_attributes g = []

  let edge_attributes e =
    match E.label e with Data -> [`Style `Dashed] | Control -> [`Style `Solid]

  let default_edge_attributes g = []

  let get_subgraph v = None

  let vertex_name v = "\"" ^ Node.to_string v ^ "\""

  let vertex_attributes v =
    let common = `Label (Node.label v) in
    if v.Node.is_target then
      [ common
      ; `Color 0x0000FF
      ; `Style `Bold
      ; `Style `Filled
      ; `Fontcolor max_int ]
    else [common]

  let default_vertex_attributes g = [`Shape `Box]

  let to_json g =
    let vertices, target_id =
      fold_vertex
        (fun v (l, t) ->
          let t = if v.Node.is_target then v.Node.id else t in
          let vertex = Node.to_json v in
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
    ; target: Llvm.llvalue option
    ; target_visited: bool }

  let empty =
    { stack= Stack.empty
    ; memory= Memory.empty
    ; trace= Trace.empty
    ; visited_blocks= BlockSet.empty
    ; visited_funcs= FuncSet.empty
    ; reachingdef= ReachingDef.empty
    ; dugraph= DUGraph.empty
    ; instrmap= InstrMap.empty
    ; target= None
    ; target_visited= false }

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

  let is_target node s =
    match s.target with Some t -> t = node | None -> false

  let add_trace llctx instr semantic_sig s =
    let new_id = new_instr_count () in
    let node = Node.make llctx instr new_id (is_target instr s) semantic_sig in
    let instrmap = InstrMap.add instr node s.instrmap in
    let dugraph =
      if !Options.no_control_flow || Trace.is_empty s.trace then s.dugraph
      else
        let src = Trace.last s.trace in
        DUGraph.add_edge_e s.dugraph (src, DUGraph.Edge.Control, node)
    in
    {s with trace= Trace.append node s.trace; instrmap; dugraph}

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

  let set_target t s = {s with target= Some t}

  let visit_target s = {s with target_visited= true}
end
