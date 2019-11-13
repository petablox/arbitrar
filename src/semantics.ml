module F = Format

module Stmt = struct
  type t = {instr: Llvm.llvalue; location: string}

  let compare = compare

  let hash = Hashtbl.hash

  let equal = ( = )

  let string_of_location debug s =
    let func = Llvm.instr_parent s |> Llvm.block_parent |> Llvm.value_name in
    match debug with
    | Some s ->
        let str = Llvm.string_of_llvalue s in
        let r =
          Str.regexp "!DILocation(line: \\([0-9]+\\), column: \\([0-9]+\\)"
        in
        let _ = Str.search_forward r str 0 in
        let line = Str.matched_group 1 str in
        let column = Str.matched_group 2 str in
        func ^ ":" ^ line ^ ":" ^ column
    | None ->
        func ^ ":0:0"

  let make llctx instr =
    let dbg = Llvm.metadata instr (Llvm.mdkind_id llctx "dbg") in
    let location = string_of_location dbg instr in
    {instr; location}

  let to_json s =
    let common =
      [ ("Location", `String s.location)
      ; ("Instr", `String (Utils.string_of_instr s.instr)) ]
    in
    match Utils.json_of_instr s.instr with
    | `Assoc l ->
        `Assoc (common @ l)
    | _ ->
        failwith "Stmt.to_json"

  let to_string s = Utils.string_of_instr s.instr

  let pp fmt s = F.fprintf fmt "%s" (Utils.string_of_instr s)
end

module Trace = struct
  type t = Stmt.t list

  let empty = []

  let append x t = t @ [x]

  let to_json t =
    let l = List.map Stmt.to_json t in
    `List l
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
  type t = Address of int | Variable of Llvm.llvalue | Unknown

  let compare = compare

  let variable v = Variable v

  let unknown = Unknown

  let count = ref (-1)

  let new_address () =
    count := !count + 1 ;
    Address !count

  let pp fmt = function
    | Address a ->
        F.fprintf fmt "&%d" a
    | Variable v ->
        let name = Llvm.value_name v in
        if name = "" then F.fprintf fmt "%s" (Utils.string_of_exp v)
        else F.fprintf fmt "%s" name
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

  let location l = Location l

  let func v = Function v

  let unknown = Unknown

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
  include Map.Make (struct
    type t = Location.t

    let compare = Location.compare
  end)

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
  type t = {stmt: Stmt.t; id: int; is_target: bool}

  let compare = compare

  let hash = Hashtbl.hash

  let equal = ( = )

  let make llctx instr id is_target =
    let stmt = Stmt.make llctx instr in
    {stmt; id; is_target}

  let to_string v = string_of_int v.id

  let label v = "[" ^ v.stmt.location ^ "]\n" ^ Stmt.to_string v.stmt

  let to_json v =
    match Stmt.to_json v.stmt with
    | `Assoc j ->
        `Assoc ([("id", `Int v.id)] @ j)
    | _ ->
        failwith "Node.to_json"
end

module DUGraph = struct
  include Graph.Persistent.Digraph.ConcreteBidirectional (Node)

  let graph_attributes g = []

  let edge_attributes e = []

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
    let vertices =
      fold_vertex
        (fun v l ->
          let vertex = Node.to_json v in
          vertex :: l)
        g []
    in
    let edges =
      fold_edges
        (fun src dst l ->
          let edge = `List [`Int src.Node.id; `Int dst.Node.id] in
          edge :: l)
        g []
    in
    `Assoc [("vertex", `List vertices); ("edge", `List edges)]
end

module NodeMap = struct
  type t = (Llvm.llvalue, Node.t) Hashtbl.t

  let create () = Hashtbl.create 65535

  let add = Hashtbl.add

  let find instr m = Hashtbl.find m instr
end

module State = struct
  type t =
    { stack: Stack.t
    ; memory: Value.t Memory.t
    ; trace: Trace.t
    ; visited_blocks: BlockSet.t
    ; visited_funcs: FuncSet.t
    ; reachingdef: Llvm.llvalue ReachingDef.t
    ; dugraph: DUGraph.t
    ; nodemap: NodeMap.t
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
    ; nodemap= NodeMap.create ()
    ; target= None
    ; target_visited= false }

  let push_stack x s = {s with stack= Stack.push x s.stack}

  let pop_stack s =
    match Stack.pop s.stack with
    | Some (x, stk) ->
        Some (x, {s with stack= stk})
    | None ->
        None

  let add_trace llctx x s =
    let stmt = Stmt.make llctx x in
    {s with trace= Trace.append stmt s.trace}

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

  let is_target node s =
    match s.target with Some t -> t = node | None -> false

  let add_du_edge src dst s =
    let src = NodeMap.find src s.nodemap in
    let dst = NodeMap.find dst s.nodemap in
    {s with dugraph= DUGraph.add_edge s.dugraph src dst}

  let add_semantic_du_edges lv_list instr s =
    let dugraph =
      List.fold_left
        (fun dugraph lv ->
          match ReachingDef.find lv s.reachingdef with
          | v ->
              let src = NodeMap.find v s.nodemap in
              let dst = NodeMap.find instr s.nodemap in
              DUGraph.add_edge dugraph src dst
          | exception Not_found ->
              dugraph)
        s.dugraph lv_list
    in
    {s with dugraph}

  let instr_count = ref (-1)

  let new_instr_count () =
    instr_count := !instr_count + 1 ;
    !instr_count

  let add_node llctx instr is_target s =
    let new_id = new_instr_count () in
    let node = Node.make llctx instr new_id is_target in
    NodeMap.add s.nodemap instr node ;
    s

  let visit_target s = {s with target_visited= true}
end
