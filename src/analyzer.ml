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

  let from_json slice_json slice_id trace_id trace_json : t =
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

module type Checker = sig
  (* type t is the result of the checker *)
  type t

  val name : string

  val check : Trace.t -> t list

  val compare : t -> t -> int

  val default : t

  val to_string : t -> string

  val to_csv : t -> string
end

module RetValChecker : Checker = struct
  type t = Checked of Predicate.t * string | NoCheck

  let name = "retval_checker"

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

  let compare = compare

  let default = NoCheck

  let to_string r : string =
    match r with
    | Checked (pred, value) ->
        Printf.sprintf "Checked\t%s\t%s" (Predicate.to_string pred) value
    | NoCheck ->
        "NoCheck\t\t"

  let to_csv r : string =
    match r with
    | Checked (pred, value) ->
        Printf.sprintf "Checked,%s,%s" (Predicate.to_string pred) value
    | NoCheck ->
        "NoCheck,,"
end

module type CheckerStats = sig
  (* The structure storing checker result *)
  type result

  (* The structure storing statistic information *)
  type stats

  val checker_name : string
  (** Get the name of the checker *)

  val add_trace : stats -> Trace.t -> stats
  (** Add a single trace to existing stats *)

  val add_traces : stats -> Trace.t list -> stats
  (** Add traces to existing stats *)

  val from_traces : Trace.t list -> stats
  (** Generate stats from list of traces *)

  val evaluate : stats -> Trace.t -> result * float
  (** Evaluate the score of a trace based on the stats *)

  val result_to_string : result -> string

  val result_to_csv : result -> string

  val dump : out_channel -> stats -> unit
  (** Dump the statistics to the out channel *)

  val dump_csv : string -> stats -> unit
  (** Dump the statistics in csv format in the directory *)
end

module Stats (C : Checker) : CheckerStats = struct
  include Map.Make (String)

  module ResultStats = struct
    module ResultStatsMap = struct
      include Map.Make (C)

      type stats = int t
    end

    type t = {map: ResultStatsMap.stats; total: int}

    let empty = {map= ResultStatsMap.empty; total= 0}

    let add (stats : t) (results : C.t list) : t =
      let map =
        List.fold_left
          (fun stats result ->
            ResultStatsMap.update result
              (fun maybe_count ->
                match maybe_count with
                | Some count ->
                    Some (count + 1)
                | None ->
                    Some 1)
              stats)
          stats.map results
      in
      let total = stats.total + List.length results in
      {map; total}

    let eval (stats : t) (result : C.t) : float =
      let count = ResultStatsMap.find result stats.map in
      1.0 -. (float_of_int count /. float_of_int stats.total)

    let dump oc stats : unit =
      ResultStatsMap.iter
        (fun result count ->
          Printf.fprintf oc "%s\t%d\n" (C.to_string result) count)
        stats.map

    let dump_csv oc stats : unit =
      ResultStatsMap.iter
        (fun result count ->
          Printf.fprintf oc "%d,%s\n" count (C.to_csv result))
        stats.map
  end

  type result = C.t

  type stats = ResultStats.t t

  let checker_name = C.name

  let add_trace (stats : stats) (trace : Trace.t) : stats =
    let func_name = trace.call_edge.callee in
    let results = C.check trace in
    update func_name
      (fun maybe_result_stats ->
        match maybe_result_stats with
        | Some result_stats ->
            Some (ResultStats.add result_stats results)
        | None ->
            Some (ResultStats.add ResultStats.empty results))
      stats

  let add_traces (stats : stats) (traces : Trace.t list) : stats =
    let num_traces = List.length traces in
    let stats, _ =
      List.fold_left
        (fun (stats, i) trace ->
          Printf.printf "%d/%d traces added\r" (i + 1) num_traces ;
          let new_stats = add_trace stats trace in
          (new_stats, i + 1))
        (stats, 0) traces
    in
    stats

  let from_traces (traces : Trace.t list) : stats =
    let stats = add_traces empty traces in
    Printf.printf "\n" ; stats

  let evaluate (stats : stats) (trace : Trace.t) : result * float =
    let func_name = trace.call_edge.callee in
    let func_stats = find func_name stats in
    let results = C.check trace in
    List.fold_left
      (fun acc result ->
        let score = ResultStats.eval func_stats result in
        if score < snd acc then (result, score) else acc)
      (C.default, 1.0) results

  let result_to_string result : string = C.to_string result

  let result_to_csv result : string = C.to_csv result

  let dump (oc : out_channel) (stats : stats) =
    iter
      (fun (func_name : string) (stats : ResultStats.t) ->
        Printf.fprintf oc "Function %s (%d)\n" func_name stats.total ;
        ResultStats.dump oc stats)
      stats

  let dump_csv (dir : string) (stats : stats) =
    iter
      (fun (func_name : string) (stats : ResultStats.t) ->
        let oc = open_out (Printf.sprintf "%s/%s-stats.csv" dir func_name) in
        Printf.fprintf oc "Count,Result\n" ;
        ResultStats.dump_csv oc stats ;
        close_out oc)
      stats
end

let checker_stats_modules : (module CheckerStats) list =
  [(module Stats (RetValChecker))]

let callee_name_from_slice_json slice_json : string =
  let call_edge = Utils.get_field slice_json "call_edge" in
  Utils.string_from_json_field call_edge "callee"

let load_traces dugraphs_dir slices_json_dir : Trace.t list =
  Printf.printf "Loading traces...\n" ;
  flush stdout ;
  let t0 = Sys.time () in
  let slices_json = Yojson.Safe.from_file slices_json_dir in
  let slice_json_list = Utils.list_from_json slices_json in
  let num_slices = List.length slice_json_list in
  let traces_list =
    List.mapi
      (fun slice_id slice_json ->
        Printf.printf "%d/%d slice loaded...\r" (slice_id + 1) num_slices ;
        flush stdout ;
        let target_func_name = callee_name_from_slice_json slice_json in
        let dugraph_json_dir =
          Printf.sprintf "%s/%s-%d-dugraph.json" dugraphs_dir target_func_name
            slice_id
        in
        try
          let dugraph_json = Yojson.Safe.from_file dugraph_json_dir in
          let trace_json_list = Utils.list_from_json dugraph_json in
          let trace_list =
            List.mapi (Trace.from_json slice_json slice_id) trace_json_list
          in
          Some trace_list
        with Sys_error _ -> None)
      slice_json_list
  in
  Printf.printf "\nTraces loaded in %f sec\n" (Sys.time () -. t0) ;
  flush stdout ;
  List.flatten (List.filter_map (fun x -> x) traces_list)

let init_checker_dir (prefix : string) (name : string) : string =
  let dir = prefix ^ "/" ^ name in
  Utils.mkdir dir ; dir

let run_one_checker analysis_dir traces checker_stats_module : unit =
  (* First get back the module *)
  let module M = (val checker_stats_module : CheckerStats) in
  Printf.printf "Running checker [%s]...\n" M.checker_name ;
  flush stdout ;
  let checker_dir = init_checker_dir analysis_dir M.checker_name in
  (* Then generate and dump stats *)
  let stats = M.from_traces traces in
  Printf.printf "Dumping statistics...\n" ;
  flush stdout ;
  M.dump_csv checker_dir stats ;
  (* Run evaluation on each trace, report bug if found minority *)
  let header =
    Printf.sprintf "Slice Id,Trace Id,Entry,Function,Location,Score,Result\n"
  in
  let results_oc = open_out (checker_dir ^ "/results.csv") in
  Printf.fprintf results_oc "%s" header ;
  let bugs_oc = open_out (checker_dir ^ "/bugs.csv") in
  Printf.fprintf bugs_oc "%s" header ;
  Printf.printf "Dumping results and bug reports...\n" ;
  flush stdout ;
  let _ =
    List.iter
      (fun (trace : Trace.t) ->
        let result, score = M.evaluate stats trace in
        let csv_row =
          Printf.sprintf "%d,%d,%s,%s,%s,%f,%s\n" trace.slice_id trace.trace_id
            trace.entry trace.call_edge.callee trace.call_edge.location score
            (M.result_to_csv result)
        in
        Printf.fprintf results_oc "%s" csv_row ;
        if score > !Options.report_threshold then
          Printf.fprintf bugs_oc "%s" csv_row)
      traces
  in
  close_out results_oc ; close_out bugs_oc

let init_analysis_dir (prefix : string) : string =
  let analysis_dir = prefix ^ "/analysis" in
  Utils.mkdir analysis_dir ; analysis_dir

let main (input_directory : string) =
  Printf.printf "Analyzing %s...\n" input_directory ;
  flush stdout ;
  let analysis_dir = init_analysis_dir input_directory in
  let dugraphs_dir = input_directory ^ "/dugraphs" in
  let slices_json_dir = input_directory ^ "/slices.json" in
  let traces = load_traces dugraphs_dir slices_json_dir in
  List.iter (run_one_checker analysis_dir traces) checker_stats_modules
