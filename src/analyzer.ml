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
    | Call of {func: string; args: string list; result: string option}
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
    let result = Utils.string_opt_from_json_field json "result" in
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

  let find_node (nodes : t list) (id : int) : t option =
    List.find_opt (fun (node : t) -> node.id = id) nodes

  let from_json (json : Yojson.Safe.t) : t =
    let id = Utils.int_from_json_field json "id" in
    let stmt = Statement.from_json json in
    {id; stmt}
end

module DUGraph = struct
  include Graph.Persistent.Digraph.ConcreteBidirectional (Node)

  let from_vertices_and_edges (nodes : Node.t list) (edges : (int * int) list)
      =
    List.fold_left
      (fun graph (id1, id2) ->
        let maybe_n1 = Node.find_node nodes id1 in
        let maybe_n2 = Node.find_node nodes id2 in
        match (maybe_n1, maybe_n2) with
        | Some n1, Some n2 ->
            add_edge graph n1 n2
        | _ ->
            raise Utils.InvalidJSON)
      empty edges
end

module Datapoint = struct
  type t = {dugraph: DUGraph.t; target: Node.t}

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

  let from_json (json : Yojson.Safe.t) =
    let nodes : Node.t list =
      nodes_from_json (Utils.get_field json "vertex")
    in
    let edges : (int * int) list =
      edges_from_json (Utils.get_field json "edge")
    in
    let target_id = Utils.int_from_json_field json "target" in
    let target =
      match Node.find_node nodes target_id with
      | Some target ->
          target
      | None ->
          raise Utils.InvalidJSON
    in
    let dugraph = DUGraph.from_vertices_and_edges nodes edges in
    {dugraph; target}
end

module CheckerResult = struct
  type t = RetValCheck of (Predicate.t * string)
end

let rec retval_checker_helper (dugraph : DUGraph.t) (retval : string)
    (fringe : Node.t list) : CheckerResult.t list =
  match fringe with
  | hd :: tl -> (
      let new_fringe = DUGraph.succ dugraph hd @ tl in
      let rest = retval_checker_helper dugraph retval new_fringe in
      match hd.stmt with
      | Assume {pred; op0; op1} ->
          if op0 = retval then
            if (* Check if the compared value is constant *)
               op1.[0] = '%' then rest
            else RetValCheck (pred, op1) :: rest
          else if op1 = retval then
            if (* Same. Check if the compared value is constant *)
               op0.[0] = '%'
            then rest
            else RetValCheck (pred, op0) :: rest
          else rest
      | _ ->
          rest )
  | [] ->
      []

let retval_checker (dp : Datapoint.t) : CheckerResult.t list =
  let fringe = [dp.target] in
  match dp.target.stmt with
  | Call {result= Some retval} ->
      retval_checker_helper dp.dugraph retval fringe
  | _ ->
      []

let checkers : (Datapoint.t -> CheckerResult.t list) list = [retval_checker]

let main (input_directory : string) : unit =
  Printf.printf "Analyzing directory %s\n" input_directory ;
  let dugraphs_dir = input_directory ^ "/dugraphs/" in
  let children = Sys.readdir dugraphs_dir in
  let datapoints =
    Array.fold_left
      (fun acc file ->
        let is_json = file.[String.length file - 1] == 'n' in
        if is_json then
          let file_dir = input_directory ^ "/dugraphs/" ^ file in
          let json = Yojson.Safe.from_file file_dir in
          let json_dp_list = Utils.list_from_json json in
          let dps = List.map Datapoint.from_json json_dp_list in
          acc @ dps
        else acc)
      [] children
  in
  List.iter
    (fun checker ->
      let results = List.map checker datapoints |> List.flatten in
      raise Utils.NotImplemented)
    checkers
  |> List.flatten
