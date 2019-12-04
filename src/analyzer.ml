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
          raise Utils.InvalidJSON )
    | _ ->
        raise Utils.InvalidJSON

  let compare = compare

  let to_string (pred : t) : string =
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

module type CHECKER = sig
  type t

  val name : string

  val default : t

  val compare : t -> t -> int

  val to_string : t -> string

  val check : Trace.t -> t list
end

module RetValChecker : CHECKER = struct
  type t = Checked of Predicate.t * string | NoCheck

  let name = "retval_checker"

  let default = NoCheck

  let compare = compare

  let to_string r : string =
    match r with
    | Checked (pred, value) ->
        Printf.sprintf "\"Checked(%s,%s)\"" (Predicate.to_string pred) value
    | NoCheck ->
        "NoCheck"

  let rec check_helper (dugraph : DUGraph.t) (explored : NodeSet.t)
      (fringe : NodeSet.t) (result : t list) : t list =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        let rst = NodeSet.remove hd fringe in
        if NodeSet.mem hd explored then
          check_helper dugraph explored rst result
        else
          let new_explored = NodeSet.add hd explored in
          let new_fringe =
            NodeSet.union (NodeSet.of_list (DUGraph.succ dugraph hd)) rst
          in
          let new_result =
            match hd.stmt with
            | Assume {pred; op0; op1} ->
                let is_op0_var = op0.[0] = '%' in
                let is_op1_var = op1.[0] = '%' in
                if is_op0_var && is_op1_var then []
                else if is_op0_var then [Checked (pred, op1)]
                else if is_op1_var then [Checked (pred, op0)]
                else []
            | _ ->
                []
          in
          check_helper dugraph new_explored new_fringe (new_result @ result)
    | None ->
        result

  let check (trace : Trace.t) : t list =
    match trace.target_node.stmt with
    | Call _ -> (
        let results =
          check_helper trace.dugraph NodeSet.empty
            (NodeSet.singleton trace.target_node)
            []
        in
        match results with [] -> [NoCheck] | _ -> results )
    | _ ->
        []
end

module type CHECKER_STATS = sig
  module Checker : CHECKER

  module FunctionStats : sig
    type t

    val empty : t

    val add : t -> Checker.t -> t

    val eval : t -> Checker.t -> float

    val dump : out_channel -> t -> unit
  end

  type stats

  val empty : stats

  val add_trace : stats -> Trace.t -> stats

  val eval : stats -> Trace.t -> Checker.t * float

  val dump : string -> stats -> unit
end

module CheckerStats (C : CHECKER) : CHECKER_STATS = struct
  include Map.Make (String)
  module Checker = C

  module FunctionStats = struct
    module ResultCountMap = struct
      include Map.Make (Checker)

      type stats = int t
    end

    type t = {map: ResultCountMap.stats; total: int}

    let empty = {map= ResultCountMap.empty; total= 0}

    let add stats result =
      let map =
        ResultCountMap.update result
          (fun maybe_count ->
            match maybe_count with
            | Some count ->
                Some (count + 1)
            | None ->
                Some 1)
          stats.map
      in
      let total = stats.total + 1 in
      {map; total}

    let eval stats result =
      let count = ResultCountMap.find result stats.map in
      1.0 -. (float_of_int count /. float_of_int stats.total)

    let dump oc stats =
      ResultCountMap.iter
        (fun result count ->
          Printf.fprintf oc "%d,%s\n" count (Checker.to_string result))
        stats.map
  end

  type stats = FunctionStats.t t

  let add_trace (stats : stats) (trace : Trace.t) =
    let func_name = trace.call_edge.callee in
    let results = C.check trace in
    update func_name
      (fun maybe_result_stats ->
        let stats =
          match maybe_result_stats with
          | Some result_stats ->
              result_stats
          | None ->
              FunctionStats.empty
        in
        Some
          (List.fold_left
             (fun stats result -> FunctionStats.add stats result)
             stats results))
      stats

  let eval (stats : stats) (trace : Trace.t) : Checker.t * float =
    let func_name = trace.call_edge.callee in
    let func_stats = find func_name stats in
    let results = C.check trace in
    List.fold_left
      (fun acc result ->
        let score = FunctionStats.eval func_stats result in
        if score < snd acc then (result, score) else acc)
      (C.default, 1.0) results

  let dump (dir : string) (stats : stats) =
    iter
      (fun (func_name : string) (stats : FunctionStats.t) ->
        let oc = open_out (Printf.sprintf "%s/%s-stats.csv" dir func_name) in
        Printf.fprintf oc "Count,Result\n" ;
        FunctionStats.dump oc stats ;
        close_out oc)
      stats
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

let init_checker_dir (prefix : string) (name : string) : string =
  let dir = prefix ^ "/" ^ name in
  Utils.mkdir dir ; dir

let init_func_stats_dir (prefix : string) : string =
  let dir = prefix ^ "/functions" in
  Utils.mkdir dir ; dir

let run_one_checker dugraphs_dir slices_json_dir analysis_dir
    checker_stats_module =
  let module M = (val checker_stats_module : CHECKER_STATS) in
  Printf.printf "Running checker [%s]...\n" M.Checker.name ;
  flush stdout ;
  let checker_dir = init_checker_dir analysis_dir M.Checker.name in
  let func_stats_dir = init_func_stats_dir checker_dir in
  let stats, _ =
    fold_traces dugraphs_dir slices_json_dir
      (fun (stats, i) (trace : Trace.t) ->
        Printf.printf "%d traces loaded\r" (i + 1) ;
        let new_stats = M.add_trace stats trace in
        (new_stats, i + 1))
      (M.empty, 0)
  in
  Printf.printf "Dumping statistics...\n" ;
  flush stdout ;
  M.dump func_stats_dir stats ;
  (* Run evaluation on each trace, report bug if found minority *)
  Printf.printf "Dumping results and bug reports...\n" ;
  flush stdout ;
  let header = "Slice Id,Trace Id,Entry,Function,Location,Score,Result\n" in
  let brief_header = "Slice Id,Entry,Function,Location,Score,Result\n" in
  let results_oc = open_out (checker_dir ^ "/results.csv") in
  Printf.fprintf results_oc "%s" header ;
  let bugs_oc = open_out (checker_dir ^ "/bugs.csv") in
  Printf.fprintf bugs_oc "%s" header ;
  let bugs_brief_oc = open_out (checker_dir ^ "/bugs_brief.csv") in
  Printf.fprintf bugs_brief_oc "%s" brief_header ;
  let _ =
    fold_traces dugraphs_dir slices_json_dir
      (fun last_slice trace ->
        let result, score = M.eval stats trace in
        let csv_row =
          Printf.sprintf "%d,%d,%s,%s,%s,%f,%s\n" trace.slice_id trace.trace_id
            trace.entry trace.call_edge.callee trace.call_edge.location score
            (M.Checker.to_string result)
        in
        Printf.fprintf results_oc "%s" csv_row ;
        if score > !Options.report_threshold then (
          Printf.fprintf bugs_oc "%s" csv_row ;
          if last_slice <> trace.slice_id then
            let brief_csv_row =
              Printf.sprintf "%d,%s,%s,%s,%f,%s\n" trace.slice_id trace.entry
                trace.call_edge.callee trace.call_edge.location score
                (M.Checker.to_string result)
            in
            Printf.fprintf bugs_brief_oc "%s" brief_csv_row ) ;
        trace.slice_id)
      (-1)
  in
  close_out results_oc ; close_out bugs_oc ; close_out bugs_brief_oc

let init_analysis_dir (prefix : string) : string =
  let analysis_dir = prefix ^ "/analysis" in
  Utils.mkdir analysis_dir ; analysis_dir

module RetValCheckerStats = CheckerStats (RetValChecker)

let checker_stats_modules : (module CHECKER_STATS) list =
  [(module RetValCheckerStats)]

let main (input_directory : string) =
  Printf.printf "Analyzing %s...\n" input_directory ;
  flush stdout ;
  let analysis_dir = init_analysis_dir input_directory in
  let dugraphs_dir = input_directory ^ "/dugraphs" in
  let slices_json_dir = input_directory ^ "/slices.json" in
  List.iter
    (run_one_checker dugraphs_dir slices_json_dir analysis_dir)
    checker_stats_modules
