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

module Trace = struct
  type t =
    { slice_id: int
    ; trace_id: int
    ; dugraph: DUGraph.t
    ; target_node: Node.t
    ; target_func_name: string
    ; location: string }

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
    let target_func_name, location = info_from_slice_json slice_json in
    let nodes = nodes_from_json (Utils.get_field trace_json "vertex") in
    let edges = edges_from_json (Utils.get_field trace_json "edge") in
    let target_id = Utils.int_from_json_field trace_json "target" in
    let target_node = Nodes.find_node_by_id nodes target_id in
    let dugraph = DUGraph.from_vertices_and_edges nodes target_node edges in
    {dugraph; target_node; target_func_name; slice_id; trace_id; location}
end

module type Checker = sig
  (* type t is the result of the checker *)
  type t

  val name : string

  val check : Trace.t -> t list

  val compare : t -> t -> int

  val default : t

  val to_string : t -> string
end

module RetValChecker : Checker = struct
  type t = Checked of Predicate.t * string | NoCheck

  let name = "Return Value Checker"

  let rec check_helper dugraph fringe result : t list =
    match fringe with
    | hd :: tl ->
        let new_fringe = DUGraph.succ dugraph hd @ tl in
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
        check_helper dugraph new_fringe (new_result @ result)
    | [] ->
        result

  let check (trace : Trace.t) : t list =
    let fringe = [trace.target_node] in
    match trace.target_node.stmt with
    | Call _ -> (
        let results = check_helper trace.dugraph fringe [] in
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

  val dump : out_channel -> stats -> unit
  (** Dump the statistics to out channel *)
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
      Printf.fprintf oc "Total: %d\n" stats.total ;
      ResultStatsMap.iter
        (fun result count ->
          Printf.fprintf oc "%s\t%d\n" (C.to_string result) count)
        stats.map
  end

  type result = C.t

  type stats = ResultStats.t t

  let checker_name = C.name

  let add_trace (stats : stats) (trace : Trace.t) : stats =
    let func_name = trace.target_func_name in
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
    List.fold_left add_trace stats traces

  let from_traces (traces : Trace.t list) : stats = add_traces empty traces

  let evaluate (stats : stats) (trace : Trace.t) : result * float =
    let func_name = trace.target_func_name in
    let func_stats = find func_name stats in
    let results = C.check trace in
    List.fold_left
      (fun acc result ->
        let score = ResultStats.eval func_stats result in
        if score < snd acc then (result, score) else acc)
      (C.default, 1.0) results

  let result_to_string result : string = C.to_string result

  let dump oc stats =
    iter
      (fun func_name stats ->
        Printf.fprintf oc "Function %s:\n" func_name ;
        ResultStats.dump oc stats)
      stats
end

let checker_stats_modules : (module CheckerStats) list =
  [(module Stats (RetValChecker))]

let callee_name_from_slice_json slice_json : string =
  let call_edge = Utils.get_field slice_json "call_edge" in
  Utils.string_from_json_field call_edge "callee"

let load_traces dugraphs_dir slices_json_dir : Trace.t list =
  let slices_json = Yojson.Safe.from_file slices_json_dir in
  let slice_json_list = Utils.list_from_json slices_json in
  let traces_list =
    List.mapi
      (fun slice_id slice_json ->
        let target_func_name = callee_name_from_slice_json slice_json in
        let dugraph_json_dir =
          Printf.sprintf "%s/%s-%d-dugraph.json" dugraphs_dir target_func_name
            slice_id
        in
        let dugraph_json = Yojson.Safe.from_file dugraph_json_dir in
        let trace_json_list = Utils.list_from_json dugraph_json in
        List.mapi (Trace.from_json slice_json slice_id) trace_json_list)
      slice_json_list
  in
  List.flatten traces_list

let run_one_checker traces checker_stats_module : unit =
  (* First get back the module *)
  let module M = (val checker_stats_module : CheckerStats) in
  Printf.printf "Running checker [%s]...\n" M.checker_name ;
  (* Then generate and dump stats *)
  let stats = M.from_traces traces in
  Printf.printf "Statistics:\n" ;
  M.dump stdout stats ;
  (* Run evaluation on each trace, report bug if found minority *)
  Printf.printf "Bug reports:\n" ;
  List.iter
    (fun (trace : Trace.t) ->
      let result, score = M.evaluate stats trace in
      if score > !Options.report_threshold then
        Printf.printf
          "[ Slice: %d, Trace: %d, Location: %s, Result: %s, Score: %f ]\n"
          trace.slice_id trace.trace_id trace.location
          (M.result_to_string result)
          score)
    traces

let main (input_directory : string) =
  let dugraphs_dir = input_directory ^ "/dugraphs" in
  let slices_json_dir = input_directory ^ "/slices.json" in
  let traces = load_traces dugraphs_dir slices_json_dir in
  List.iter (run_one_checker traces) checker_stats_modules
