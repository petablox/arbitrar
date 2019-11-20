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

  let compare = compare
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

  let compare = compare
end

module CheckerResultStats = struct
  module CheckerResultStatsMap = struct
    include Map.Make (CheckerResult)

    let from_results (results : CheckerResult.t list) : int t =
      List.fold_left
        (fun stats result ->
          update result
            (fun maybe_count ->
              match maybe_count with
              | Some count ->
                  Some (count + 1)
              | None ->
                  Some 1)
            stats)
        empty results

    let get_count (map : int t) (result : CheckerResult.t) : int =
      match find_opt result map with Some count -> count | None -> 0
  end

  type t = {map: int CheckerResultStatsMap.t; total_amount: int}

  let from_results (results : CheckerResult.t list) : t =
    let map = CheckerResultStatsMap.from_results results in
    let total_amount = List.length results in
    {map; total_amount}

  let eval (stats : t) (result : CheckerResult.t) : float =
    let count = CheckerResultStatsMap.get_count stats.map result in
    1.0 -. (float_of_int count /. float_of_int stats.total_amount)
end

let rec retval_checker_helper (dugraph : DUGraph.t) (retval : string)
    (fringe : Node.t list) (result : CheckerResult.t list) :
    CheckerResult.t list =
  match fringe with
  | hd :: tl ->
      let new_fringe = DUGraph.succ dugraph hd @ tl in
      let new_result =
        match hd.stmt with
        | Assume {pred; op0; op1} ->
            if op0 = retval then
              if (* Check if the compared value is constant *)
                 op1.[0] = '%'
              then []
              else [CheckerResult.RetValCheck (pred, op1)]
            else if op1 = retval then
              if
                (* Same. Check if the compared value is constant *)
                op0.[0] = '%'
              then []
              else [CheckerResult.RetValCheck (pred, op0)]
            else []
        | _ ->
            []
      in
      retval_checker_helper dugraph retval new_fringe (new_result @ result)
  | [] ->
      result

let retval_checker (dp : Datapoint.t) : CheckerResult.t list =
  let fringe = [dp.target] in
  match dp.target.stmt with
  | Call {result= Some retval} ->
      retval_checker_helper dp.dugraph retval fringe []
  | _ ->
      []

let checkers : (Datapoint.t -> CheckerResult.t list) list = [retval_checker]

let run_one_checker datapoints checker =
  let results = List.map checker datapoints |> List.flatten in
  let stats = CheckerResultStats.from_results results in
  List.iter
    (fun datapoint ->
      let results = checker datapoint in
      let scores = List.map (CheckerResultStats.eval stats) results in
      let min_score =
        List.fold_left
          (fun acc score -> if score < acc then score else acc)
          1.0 scores
      in
      if min_score > 0.7 then Printf.printf "Found bug!")
    datapoints

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
  List.iter (run_one_checker datapoints) checkers
