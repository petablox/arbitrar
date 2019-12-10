open Processing

module type CHECKER = sig
  type t

  val name : string

  val default : t

  val compare : t -> t -> int

  val to_string : t -> string

  val check : Trace.t -> t list
end

module RetValChecker : CHECKER = struct
  type t = Checked of Predicate.t * int64 | NoCheck

  let name = "retval_checker"

  let default = NoCheck

  let compare = compare

  let to_string r : string =
    match r with
    | Checked (pred, value) ->
        Printf.sprintf "Checked(%s,%s)" (Predicate.to_string pred)
          (Int64.to_string value)
    | NoCheck ->
        "NoCheck"

  let rec check_helper dugraph ret explored fringe result =
    match NodeSet.choose_opt fringe with
    | Some hd ->
        let rst = NodeSet.remove hd fringe in
        if NodeSet.mem hd explored then
          check_helper dugraph ret explored rst result
        else
          let new_explored = NodeSet.add hd explored in
          let new_fringe =
            NodeSet.union (NodeSet.of_list (DUGraph.succ dugraph hd)) rst
          in
          let new_result =
            match hd.stmt with
            | Assume {pred; op0; op1} ->
                let is_op0_const = Value.is_const op0 in
                let is_op1_const = Value.is_const op1 in
                if is_op0_const && is_op0_const then []
                else if is_op0_const && Value.sem_equal op1 ret then
                  [Checked (pred, Value.get_const op0)]
                else if is_op1_const && Value.sem_equal op0 ret then
                  [Checked (pred, Value.get_const op1)]
                else []
            | _ ->
                []
          in
          check_helper dugraph ret new_explored new_fringe (new_result @ result)
    | None ->
        result

  let check (trace : Trace.t) : t list =
    match trace.target_node.stmt with
    | Call {result} -> (
      match result with
      | Some ret -> (
          let targets = NodeSet.singleton trace.target_node in
          let results =
            check_helper trace.dugraph ret NodeSet.empty targets []
          in
          match results with [] -> [NoCheck] | _ -> results )
      | None ->
          [] )
    | _ ->
        []
end

module ArgRelChecker : CHECKER = struct
  type t = Relation of int * int | NoRelation

  let name = "argrel_checker"

  let default = NoRelation

  let compare = compare

  let to_string r : string =
    match r with
    | Relation (i, j) ->
        Printf.sprintf "Relation(%d,%d)" i j
    | NoRelation ->
        "NoRelation"

  let intersect v1 v2 =
    match (v1, v2) with
    | Value.SymExpr e1, Value.SymExpr e2 ->
        let s1 = SymExpr.get_used_symbols e1 in
        let s2 = SymExpr.get_used_symbols e2 in
        let itsct = SymbolSet.inter s1 s2 in
        SymbolSet.cardinal itsct > 0
    | _ ->
        false

  let combinations (ls : 'a list) : (int * 'a * int * 'a) list =
    List.mapi
      (fun i1 e1 ->
        List.mapi
          (fun i2 e2 -> if i1 <> i2 then Some (i1, e1, i2, e2) else None)
          ls)
      ls
    |> List.flatten
    |> List.filter_map (fun x -> x)

  let check (trace : Trace.t) : t list =
    let target_stmt = trace.target_node.stmt in
    match target_stmt with
    | Call {args} ->
        let cart = combinations args in
        List.filter_map
          (fun (i1, e1, i2, e2) ->
            if intersect e1 e2 then Some (Relation (i1, i2)) else None)
          cart
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

    val iter : (Checker.t -> int -> unit) -> t -> unit
  end

  type stats

  val empty : stats

  val add_trace : stats -> Trace.t -> stats

  val eval : stats -> Trace.t -> Checker.t * float

  val iter : (string -> FunctionStats.t -> unit) -> stats -> unit
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

    let iter f stats = ResultCountMap.iter f stats.map
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

  let iter = iter
end

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
  let filter trace = not (Trace.has_label "undersized" trace) in
  let stats, _ =
    fold_traces_with_filter dugraphs_dir slices_json_dir filter
      (fun (stats, i) (trace : Trace.t) ->
        Printf.printf "%d traces loaded\r" (i + 1) ;
        flush stdout ;
        let new_stats = M.add_trace stats trace in
        (new_stats, i + 1))
      (M.empty, 0)
  in
  Printf.printf "\nDumping statistics...\n" ;
  flush stdout ;
  let func_stats_dir = init_func_stats_dir checker_dir in
  M.iter
    (fun func_name stats ->
      let oc =
        open_out (Printf.sprintf "%s/%s-stats.csv" func_stats_dir func_name)
      in
      Printf.fprintf oc "Count,Result\n" ;
      M.FunctionStats.iter
        (fun result count ->
          Printf.fprintf oc "%d,%s\n" count (M.Checker.to_string result))
        stats ;
      close_out oc)
    stats ;
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
  let bugs, _ =
    fold_traces_with_filter dugraphs_dir slices_json_dir filter
      (fun (bugs, last_slice) trace ->
        let result, score = M.eval stats trace in
        let csv_row =
          Printf.sprintf "%d,%d,%s,%s,%s,%f,\"%s\"\n" trace.slice_id
            trace.trace_id trace.entry trace.call_edge.callee
            trace.call_edge.location score
            (M.Checker.to_string result)
        in
        Printf.fprintf results_oc "%s" csv_row ;
        let bugs =
          if score > !Options.report_threshold then (
            Printf.fprintf bugs_oc "%s" csv_row ;
            let bugs =
              IdSet.add bugs trace.call_edge.callee trace.slice_id
                trace.trace_id
            in
            ( if last_slice <> trace.slice_id then
              let brief_csv_row =
                Printf.sprintf "%d,%s,%s,%s,%f,\"%s\"\n" trace.slice_id
                  trace.entry trace.call_edge.callee trace.call_edge.location
                  score
                  (M.Checker.to_string result)
              in
              Printf.fprintf bugs_brief_oc "%s" brief_csv_row ) ;
            bugs )
          else bugs
        in
        (bugs, trace.slice_id))
      (IdSet.empty, -1)
  in
  Printf.printf "Labeling bugs in-place...\n" ;
  flush stdout ;
  IdSet.label dugraphs_dir "alarm" bugs ;
  close_out results_oc ;
  close_out bugs_oc ;
  close_out bugs_brief_oc

let init_analysis_dir (prefix : string) : string =
  let analysis_dir = prefix ^ "/analysis" in
  Utils.mkdir analysis_dir ; analysis_dir

module RetValCheckerStats = CheckerStats (RetValChecker)
module ArgRelCheckerStats = CheckerStats (ArgRelChecker)

let checker_stats_modules : (module CHECKER_STATS) list =
  [(module RetValCheckerStats); (module ArgRelCheckerStats)]

let main (input_directory : string) =
  Printf.printf "Analyzing %s...\n" input_directory ;
  flush stdout ;
  let analysis_dir = init_analysis_dir input_directory in
  let dugraphs_dir = input_directory ^ "/dugraphs" in
  let slices_json_dir = input_directory ^ "/slices.json" in
  List.iter
    (run_one_checker dugraphs_dir slices_json_dir analysis_dir)
    checker_stats_modules
