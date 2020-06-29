module Predicate = struct
  type t = Eq | Ne | Ugt | Uge | Ult | Ule | Sgt | Sge | Slt | Sle

  let compare = compare

  let to_string pred =
    match pred with
    | Eq ->
        "eq"
    | Ne ->
        "ne"
    | Ugt ->
        "ugt"
    | Uge ->
        "uge"
    | Ult ->
        "ult"
    | Ule ->
        "ule"
    | Sgt ->
        "sgt"
    | Sge ->
        "sge"
    | Slt ->
        "slt"
    | Sle ->
        "sle"

  let of_string str =
    match str with
    | "eq" ->
        Eq
    | "ne" ->
        Ne
    | "ugt" ->
        Ugt
    | "uge" ->
        Uge
    | "ult" ->
        Ult
    | "ule" ->
        Ule
    | "sgt" ->
        Sgt
    | "sge" ->
        Sge
    | "slt" ->
        Slt
    | "sle" ->
        Sle
    | _ ->
        raise Utils.InvalidJSON

  let of_json json = Utils.string_from_json json |> of_string

  let to_json pred = `String (to_string pred)

  let to_yojson : t -> Yojson.Safe.t = to_json
end

module BinOp = struct
  type t =
    | Add
    | FAdd
    | Sub
    | FSub
    | Mul
    | FMul
    | UDiv
    | SDiv
    | FDiv
    | URem
    | SRem
    | FRem
    | Shl
    | LShr
    | AShr
    | And
    | Or
    | Xor

  let of_string str =
    match str with
    | "add" ->
        Add
    | "fadd" ->
        FAdd
    | "sub" ->
        Sub
    | "fsub" ->
        FSub
    | "mul" ->
        Mul
    | "fmul" ->
        FMul
    | "udiv" ->
        UDiv
    | "sdiv" ->
        SDiv
    | "fdiv" ->
        FDiv
    | "urem" ->
        URem
    | "srem" ->
        SRem
    | "frem" ->
        FRem
    | "shl" ->
        Shl
    | "lshr" ->
        LShr
    | "ashr" ->
        AShr
    | "and" ->
        And
    | "or" ->
        Or
    | "xor" ->
        Xor
    | _ ->
        raise Utils.InvalidJSON

  let is_binary_op str =
    try
      let _ = of_string str in
      true
    with _ -> false

  let of_json json = Utils.string_from_json json |> of_string

  let to_string = function
    | Add ->
        "add"
    | FAdd ->
        "fadd"
    | Sub ->
        "sub"
    | FSub ->
        "fsub"
    | Mul ->
        "mul"
    | FMul ->
        "fmul"
    | UDiv ->
        "udiv"
    | SDiv ->
        "sdiv"
    | FDiv ->
        "fdiv"
    | URem ->
        "urem"
    | SRem ->
        "srem"
    | FRem ->
        "frem"
    | Shl ->
        "shl"
    | LShr ->
        "lshr"
    | AShr ->
        "ashr"
    | And ->
        "and"
    | Or ->
        "or"
    | Xor ->
        "xor"

  let to_json op = `String (to_string op)

  let to_yojson = to_json
end

module SymbolSet = Semantics.SymbolSet
module RetIdSet = Semantics.RetIdSet
module SymExpr = Semantics.SymExpr
module TypeKind = Slicer.TypeKind
module FunctionType = Slicer.FunctionType

module Function = struct
  (* Function name, Function Type, Num Traces *)
  type t = string * FunctionType.t * int
end

module Location = struct
  type t =
    | Address of string
    | Argument of int
    | Variable of string
    | SymExpr of SymExpr.t
    | Gep of t * int option list
    | Global of string
    | Unknown
  [@@deriving yojson {exn= true}]
end

module Value = struct
  type t =
    | Function of string
    | SymExpr of SymExpr.t
    | Int of Int64.t
    | Location of Location.t
    | Argument of int
    | Global of string
    | Unknown
  [@@deriving yojson {exn= true}]

  let sem_equal v1 v2 =
    match (v1, v2) with Unknown, Unknown -> false | _, _ -> v1 = v2

  let of_json = of_yojson_exn

  let is_const = function Int _ -> true | _ -> false

  let get_const = function Int i -> i | _ -> raise Utils.InvalidArgument
end

module Branch = struct
  type t = Then | Else
end

module Statement = struct
  type t =
    | Call of {func: string; args: Value.t list; result: Value.t option}
    | Assume of {pred: Predicate.t; op0: Value.t; op1: Value.t; result: Value.t}
    | ConditionalBranch of {br: Branch.t}
    | UnconditionalBranch
    | Return of Value.t option
    | Store of {value: Value.t; loc: Value.t}
    | Load of {loc: Value.t; result: Value.t}
    | GetElementPtr of {op0: Value.t; result: Value.t}
    | Binary of {op: BinOp.t; op0: Value.t; op1: Value.t; result: Value.t}
    | Other

  let predicate_from_stmt_json json : Predicate.t =
    Predicate.of_json (Utils.get_field json "predicate")

  let icmp_from_json json : t =
    let pred = predicate_from_stmt_json json in
    let op0 = Value.of_json (Utils.get_field json "op0_sem") in
    let op1 = Value.of_json (Utils.get_field json "op1_sem") in
    let result = Value.of_json (Utils.get_field json "result_sem") in
    Assume {pred; op0; op1; result}

  let call_from_json json : t =
    let func = Utils.string_from_json_field json "func" in
    let args =
      Utils.list_from_json (Utils.get_field json "args_sem")
      |> List.map Value.of_json
    in
    let result =
      match Utils.get_field_not_null json "result" with
      | Some _ ->
          Utils.get_field_not_null json "result_sem" |> Option.map Value.of_json
      | _ ->
          None
    in
    Call {func; args; result}

  let return_from_json json : t =
    let op0 =
      Utils.get_field_not_null json "op0_sem" |> Option.map Value.of_json
    in
    Return op0

  let store_from_json json : t =
    let value = Value.of_json (Utils.get_field json "op0_sem") in
    let loc = Value.of_json (Utils.get_field json "op1_sem") in
    Store {value; loc}

  let load_from_json json : t =
    let loc = Value.of_json (Utils.get_field json "op0_sem") in
    let result = Value.of_json (Utils.get_field json "result_sem") in
    Load {loc; result}

  let getelementptr_from_json json : t =
    let op0 = Value.of_json (Utils.get_field json "op0_sem") in
    let result = Value.of_json (Utils.get_field json "result_sem") in
    GetElementPtr {op0; result}

  let br_from_json json : t =
    let maybe_then_br = Utils.get_field_opt json "then_br" in
    match maybe_then_br with
    | Some (`Bool true) ->
        ConditionalBranch {br= Branch.Then}
    | Some (`Bool false) ->
        ConditionalBranch {br= Branch.Else}
    | Some _ ->
        raise Utils.InvalidJSON
    | None ->
        UnconditionalBranch

  let binary_from_json json : t =
    let op = BinOp.of_json (Utils.get_field json "opcode") in
    let op0 = Value.of_json (Utils.get_field json "op0_sem") in
    let op1 = Value.of_json (Utils.get_field json "op1_sem") in
    let result = Value.of_json (Utils.get_field json "result_sem") in
    Binary {op; op0; op1; result}

  let from_json json : t =
    match Utils.get_field_opt json "opcode" with
    | Some opcode_json -> (
      match Utils.string_from_json opcode_json with
      | "icmp" ->
          icmp_from_json json
      | "call" ->
          call_from_json json
      | "ret" ->
          return_from_json json
      | "store" ->
          store_from_json json
      | "load" ->
          load_from_json json
      | "getelementptr" ->
          getelementptr_from_json json
      | "br" ->
          br_from_json json
      | s when BinOp.is_binary_op s ->
          binary_from_json json
      | _ ->
          Other )
    | None ->
        Other
end

module Node = struct
  type t = {id: int; stmt: Statement.t; location: string}

  let compare n1 n2 = compare n1.id n2.id

  let hash = Hashtbl.hash

  let equal n1 n2 = n1.id = n2.id

  let from_json (json : Yojson.Safe.t) : t =
    let id = Utils.int_from_json_field json "id" in
    let stmt = Statement.from_json json in
    let location = Utils.string_from_json_field json "location" in
    {id; stmt; location}

  let context n =
    let loc = n.location in
    match String.rindex_opt loc ':' with
    | Some fst_colon -> (
      match String.rindex_from_opt loc (fst_colon - 1) ':' with
      | Some scd_colon ->
          String.sub loc 0 scd_colon
      | None ->
          loc )
    | None ->
        loc
end

module Nodes = struct
  exception CannotFindNodeById

  type t = Node.t list

  let find_node_by_id nodes id : Node.t =
    match List.find_opt (fun (node : Node.t) -> node.id = id) nodes with
    | Some node ->
        node
    | None ->
        raise CannotFindNodeById
end

module NodeSet = Set.Make (Node)

module NodeGraph = struct
  include Graph.Persistent.Digraph.ConcreteBidirectional (Node)

  type edge = int * int

  let from_vertices_and_edges (nodes : Node.t list) (target : Node.t)
      (edges : edge list) =
    let with_target = add_vertex empty target in
    List.fold_left
      (fun graph (id1, id2) ->
        let n1 = Nodes.find_node_by_id nodes id1 in
        let n2 = Nodes.find_node_by_id nodes id2 in
        add_edge graph n1 n2)
      with_target edges
end

module CallEdge = struct
  type t = {caller: string; callee: string; location: string}

  let from_json json : t =
    let callee = Utils.string_from_json_field json "callee" in
    let caller = Utils.string_from_json_field json "caller" in
    let location = Utils.string_from_json_field json "location" in
    {caller; callee; location}
end

module Trace = struct
  type t =
    { slice_id: int
    ; trace_id: int
    ; entry: string
    ; nodes: Nodes.t
    ; dugraph: NodeGraph.t
    ; cfgraph: NodeGraph.t
    ; target_node: Node.t
    ; call_edge: CallEdge.t
    ; labels: string list }

  let target_func_name t : string = t.call_edge.callee

  let has_label label trace =
    List.find_opt (String.equal label) trace.labels |> Option.is_some

  let nodes_from_json json : Node.t list =
    let json_list = Utils.list_from_json json in
    List.map Node.from_json json_list

  let edge_from_json json : NodeGraph.edge =
    match json with
    | `List [j1; j2] ->
        (Utils.int_from_json j1, Utils.int_from_json j2)
    | _ ->
        raise Utils.InvalidJSON

  let edges_from_json json : NodeGraph.edge list =
    let json_list = Utils.list_from_json json in
    List.map edge_from_json json_list

  let info_from_slice_json slice_json : string * string =
    let call_edge = Utils.get_field slice_json "call_edge" in
    let callee_name = Utils.string_from_json_field call_edge "callee" in
    let location = Utils.string_from_json_field call_edge "location" in
    (callee_name, location)

  let from_json slice_id slice_json trace_id trace_json : t =
    let entry = Utils.string_from_json_field slice_json "entry" in
    let call_edge =
      CallEdge.from_json (Utils.get_field slice_json "call_edge")
    in
    let nodes = nodes_from_json (Utils.get_field trace_json "vertex") in
    let du_edges = edges_from_json (Utils.get_field trace_json "du_edge") in
    let cf_edges = edges_from_json (Utils.get_field trace_json "cf_edge") in
    let target_id = Utils.int_from_json_field trace_json "target" in
    let target_node = Nodes.find_node_by_id nodes target_id in
    let dugraph =
      NodeGraph.from_vertices_and_edges nodes target_node du_edges
    in
    let cfgraph =
      NodeGraph.from_vertices_and_edges nodes target_node cf_edges
    in
    let labels =
      Utils.get_field_opt trace_json "labels"
      |> Utils.option_map_default Utils.string_list_from_json []
    in
    { slice_id
    ; trace_id
    ; entry
    ; nodes
    ; dugraph
    ; cfgraph
    ; target_node
    ; call_edge
    ; labels }

  let node (trace : t) (id : int) : Node.t =
    Nodes.find_node_by_id trace.nodes id
end

let callee_name_from_slice_json slice_json : string =
  let call_edge = Utils.get_field slice_json "call_edge" in
  Utils.string_from_json_field call_edge "callee"

let func_type_from_slice_json slice_json : FunctionType.t =
  let func_type_json = Utils.get_field slice_json "target_type" in
  FunctionType.of_yojson_exn func_type_json

let fold_traces dugraphs_dir slices_json_dir
    (f : 'a -> Function.t * Trace.t -> 'a) (base : 'a) =
  let slices_json = Yojson.Safe.from_file slices_json_dir in
  let slice_json_list = Utils.list_from_json slices_json in
  let result, _ =
    List.fold_left
      (fun (acc, slice_id) slice_json ->
        let target_func_name = callee_name_from_slice_json slice_json in
        let func_type = func_type_from_slice_json slice_json in
        let dugraph_json_dir =
          Printf.sprintf "%s/%s-%d.json" dugraphs_dir target_func_name slice_id
        in
        try
          let dugraph_json = Yojson.Safe.from_file dugraph_json_dir in
          let trace_json_list = Utils.list_from_json dugraph_json in
          let num_traces = List.length trace_json_list in
          let func = (target_func_name, func_type, num_traces) in
          let next_acc, _ =
            List.fold_left
              (fun (acc, trace_id) trace_json ->
                let trace =
                  Trace.from_json slice_id slice_json trace_id trace_json
                in
                let next_acc = f acc (func, trace) in
                (next_acc, trace_id + 1))
              (acc, 0) trace_json_list
          in
          (next_acc, slice_id + 1)
        with Sys_error _ -> (acc, slice_id + 1))
      (base, 0) slice_json_list
  in
  result

let fold_traces_with_filter dugraphs_dir slices_json_dir filter f base =
  fold_traces dugraphs_dir slices_json_dir
    (fun acc info -> if filter info then f acc info else acc)
    base

module IdSet = struct
  module SliceIdMap = Map.Make (struct
    (* Target function name, Slice id *)
    type t = string * int

    let compare = compare
  end)

  module TraceIdSet = Set.Make (Int)

  type t = TraceIdSet.t SliceIdMap.t

  let empty = SliceIdMap.empty

  let add bugs func_name slice_id trace_id =
    SliceIdMap.update (func_name, slice_id)
      (fun maybe_trace_id_set ->
        let new_set =
          match maybe_trace_id_set with
          | Some set ->
              TraceIdSet.add trace_id set
          | None ->
              TraceIdSet.singleton trace_id
        in
        Some new_set)
      bugs

  let label_trace_json trace_json label =
    match trace_json with
    | `Assoc assocs -> (
      match List.find_opt (fun (k, _) -> k = "labels") assocs with
      | Some (_, labels) ->
          let labels = Utils.string_list_from_json labels in
          let has_label =
            List.find_opt (String.equal label) labels |> Option.is_some
          in
          let labels = if has_label then labels else label :: labels in
          let json_labels = `List (List.map (fun s -> `String s) labels) in
          `Assoc (("labels", json_labels) :: List.remove_assoc "labels" assocs)
      | None ->
          `Assoc (("labels", `List [`String label]) :: assocs) )
    | _ ->
        raise Utils.InvalidJSON

  let label dugraphs_dir label bugs : unit =
    SliceIdMap.iter
      (fun (func_name, slice_id) trace_ids ->
        let dugraph_json_dir =
          Printf.sprintf "%s/%s-%d.json" dugraphs_dir func_name slice_id
        in
        let dugraph_json = Yojson.Safe.from_file dugraph_json_dir in
        let trace_json_list =
          List.mapi
            (fun trace_id trace_json ->
              if TraceIdSet.mem trace_id trace_ids then
                label_trace_json trace_json label
              else trace_json)
            (Utils.list_from_json dugraph_json)
        in
        let dugraph_json = `List trace_json_list in
        let oc = open_out dugraph_json_dir in
        Options.json_to_channel oc dugraph_json ;
        close_out oc)
      bugs
end
