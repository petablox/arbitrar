module Predicate = struct
  type t = Eq | Ne | Ugt | Uge | Ult | Ule | Sgt | Sge | Slt | Sle

  let from_json (json : Yojson.Safe.t) : t =
    match json with
    | `String name -> (
      match name with
      | "eq" ->
          Eq
      | "ne" ->
          Ne
      | "ugt" ->
          Ugt
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
          raise Utils.InvalidJSON )
    | _ ->
        raise Utils.InvalidJSON
end

module Statement = struct
  type t =
    | Call of {func: string; args: string list; result: string}
    | Assume of {pred: Predicate.t; op0: string; op1: string; result: string}
    | Other

  let predicate_from_stmt_json (json : Yojson.Safe.t) : Predicate.t =
    Predicate.from_json (Utils.get_field json "predicate")

  let icmp_from_json (json : Yojson.Safe.t) : t =
    let pred = predicate_from_stmt_json json in
    let op0 = Utils.string_from_json_field json "op0" in
    let op1 = Utils.string_from_json_field json "op1" in
    let result = Utils.string_from_json_field json "result" in
    Assume {pred; op0; op1; result}

  let call_from_json (json : Yojson.Safe.t) : t =
    let func = Utils.string_from_json_field json "func" in
    let args = Utils.string_list_from_json (Utils.get_field json "args") in
    let result = Utils.string_from_json_field json "result" in
    Call {func; args; result}

  let from_json (json : Yojson.Safe.t) : t =
    match Utils.string_from_json_field json "opcode" with
    | "icmp" ->
        icmp_from_json json
    | "call" ->
        call_from_json json
    | _ ->
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

module DUGraphSimple = struct
  include Graph.Persistent.Digraph.ConcreteBidirectional (Node)

  let nodes_from_json json =
    let json_list = Utils.list_from_json json in
    List.map Node.from_json json_list

  let edge_from_json json =
    match json with
    | `List [j1; j2] ->
        (Utils.int_from_json j1, Utils.int_from_json j2)
    | _ ->
        raise Utils.InvalidJSON

  let edges_from_json json =
    let json_list = Utils.list_from_json json in
    List.map edge_from_json json_list

  let find_node_by_id (nodes : Node.t list) (id : int) : Node.t option =
    List.find_opt (fun (node : Node.t) -> node.id = id) nodes

  let from_json (json : Yojson.Safe.t) =
    let nodes : Node.t list =
      nodes_from_json (Utils.get_field json "vertex")
    in
    let edges : (int * int) list =
      edges_from_json (Utils.get_field json "edge")
    in
    (* let target_id = Utils.int_from_json_field json "target" in *)
    List.fold_left
      (fun graph (id1, id2) ->
        let maybe_n1 = find_node_by_id nodes id1 in
        let maybe_n2 = find_node_by_id nodes id2 in
        match (maybe_n1, maybe_n2) with
        | Some n1, Some n2 ->
            add_edge graph n1 n2
        | _ ->
            raise Utils.InvalidJSON)
      empty edges
end

let main (input_directory : string) : unit =
  Printf.printf "Analyzing directory %s\n" input_directory ;
  raise Utils.NotImplemented
