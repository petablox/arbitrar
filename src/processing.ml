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

  let of_json json =
    match Utils.string_from_json json with
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

  let to_json pred = `String (to_string pred)
end

module SymExpr = struct
  include Semantics.SymExpr
end

module Value = struct
  type t =
    | Function of string
    | SymExpr of SymExpr.t
    | Int of Int64.t
    | Location of string
    | Unknown
  [@@deriving yojson {exn= true}]

  let of_json json =
    try of_yojson_exn json
    with _ ->
      Printf.printf "Error Parsing JSON:\n%s\n" (Yojson.Safe.to_string json) ;
      raise Utils.InvalidJSON

  let is_const = function Int _ -> true | _ -> false

  let get_const = function Int i -> i | _ -> raise Utils.InvalidArgument
end

module Statement = struct
  type t =
    | Call of {func: string; args: Value.t list; result: Value.t option}
    | Assume of {pred: Predicate.t; op0: Value.t; op1: Value.t; result: Value.t}
    | Other

  let predicate_from_stmt_json (json : Yojson.Safe.t) : Predicate.t =
    Predicate.of_json (Utils.get_field json "predicate")

  let icmp_from_json (json : Yojson.Safe.t) : t =
    let pred = predicate_from_stmt_json json in
    let op0 = Value.of_json (Utils.get_field json "op0_sem") in
    let op1 = Value.of_json (Utils.get_field json "op1_sem") in
    let result = Value.of_json (Utils.get_field json "result_sem") in
    Assume {pred; op0; op1; result}

  let call_from_json (json : Yojson.Safe.t) : t =
    let func = Utils.string_from_json_field json "func" in
    let args =
      Utils.list_from_json (Utils.get_field json "args_sem")
      |> List.map Value.of_json
    in
    let result =
      Utils.get_field_not_null json "result_sem" |> Option.map Value.of_json
    in
    Call {func; args; result}

  let from_json (json : Yojson.Safe.t) : t =
    match Utils.get_field_opt json "opcode" with
    | Some opcode_json -> (
      match Utils.string_from_json opcode_json with
      | "icmp" ->
          icmp_from_json json
      | "call" ->
          call_from_json json
      | _ ->
          Other )
    | None ->
        Other
end

module Node = struct
  type t = {id: int; stmt: Statement.t}

  let compare n1 n2 = compare n1.id n2.id

  let hash = Hashtbl.hash

  let equal n1 n2 = n1.id = n2.id

  let from_json (json : Yojson.Safe.t) : t =
    let id = Utils.int_from_json_field json "id" in
    let stmt = Statement.from_json json in
    {id; stmt}
end

module Nodes = struct
  type t = Node.t list

  let find_node_by_id nodes id : Node.t =
    List.find (fun (node : Node.t) -> node.id = id) nodes
end

module NodeSet = Set.Make (Node)

module DUGraph = struct
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
    ; dugraph: DUGraph.t
    ; target_node: Node.t
    ; call_edge: CallEdge.t }

  let nodes_from_json json : Node.t list =
    let json_list = Utils.list_from_json json in
    List.map Node.from_json json_list

  let edge_from_json json : DUGraph.edge =
    match json with
    | `List [j1; j2] ->
        (Utils.int_from_json j1, Utils.int_from_json j2)
    | _ ->
        raise Utils.InvalidJSON

  let edges_from_json json : DUGraph.edge list =
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
    let edges = edges_from_json (Utils.get_field trace_json "du_edge") in
    let target_id = Utils.int_from_json_field trace_json "target" in
    let target_node = Nodes.find_node_by_id nodes target_id in
    let dugraph = DUGraph.from_vertices_and_edges nodes target_node edges in
    {slice_id; trace_id; entry; dugraph; target_node; call_edge}
end

let callee_name_from_slice_json slice_json : string =
  let call_edge = Utils.get_field slice_json "call_edge" in
  Utils.string_from_json_field call_edge "callee"

let fold_traces dugraphs_dir slices_json_dir f base =
  let slices_json = Yojson.Safe.from_file slices_json_dir in
  let slice_json_list = Utils.list_from_json slices_json in
  let result, _ =
    List.fold_left
      (fun (acc, slice_id) slice_json ->
        let target_func_name = callee_name_from_slice_json slice_json in
        let dugraph_json_dir =
          Printf.sprintf "%s/%s-%d-dugraph.json" dugraphs_dir target_func_name
            slice_id
        in
        try
          let dugraph_json = Yojson.Safe.from_file dugraph_json_dir in
          let trace_json_list = Utils.list_from_json dugraph_json in
          let next_acc, _ =
            List.fold_left
              (fun (acc, trace_id) trace_json ->
                let trace =
                  Trace.from_json slice_id slice_json trace_id trace_json
                in
                let next_acc = f acc trace in
                (next_acc, trace_id + 1))
              (acc, 0) trace_json_list
          in
          (next_acc, slice_id + 1)
        with Sys_error _ -> (acc, slice_id + 1))
      (base, 0) slice_json_list
  in
  result

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

  let label dugraphs_dir label bugs : unit =
    SliceIdMap.iter
      (fun (func_name, slice_id) trace_ids ->
        let dugraph_json_dir =
          Printf.sprintf "%s/%s-%d-dugraph.json" dugraphs_dir func_name
            slice_id
        in
        let dugraph_json = Yojson.Safe.from_file dugraph_json_dir in
        let trace_json_list =
          List.mapi
            (fun trace_id trace_json ->
              if TraceIdSet.mem trace_id trace_ids then
                match trace_json with
                | `Assoc assocs ->
                    `Assoc ((label, `Bool true) :: assocs)
                | _ ->
                    raise Utils.InvalidJSON
              else trace_json)
            (Utils.list_from_json dugraph_json)
        in
        let dugraph_json = `List trace_json_list in
        let oc = open_out dugraph_json_dir in
        Options.json_to_channel oc dugraph_json ;
        close_out oc)
      bugs
end
