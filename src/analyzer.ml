open Processing
open Checker

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
      if stats.total = 0 then 0.0
      else
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

let needs_run_checker checker_name : bool =
  if String.equal !Options.checker "all" then true
  else String.equal checker_name !Options.checker

let run_one_checker dug_dir slcs_dir ana_dir cs_mod =
  let module M = (val cs_mod : CHECKER_STATS) in
  if needs_run_checker M.Checker.name then (
    Printf.printf "Running checker [%s]...\n" M.Checker.name ;
    flush stdout ;
    let checker_dir = init_checker_dir ana_dir M.Checker.name in
    let filter (func, trace) =
      (not (Trace.has_label "no-context" trace)) && M.Checker.filter func
    in
    let stats, checked_traces =
      fold_traces_with_filter dug_dir slcs_dir filter
        (fun ((stats, idset) : M.stats * IdSet.t) ((func_name, _), trace) ->
          Printf.printf "%d slices loaded (trace_id: %d)\r" trace.slice_id
            trace.trace_id ;
          flush stdout ;
          let new_stats = M.add_trace stats trace in
          let new_idset =
            IdSet.add idset func_name trace.slice_id trace.trace_id
          in
          (new_stats, new_idset))
        (M.empty, IdSet.empty)
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
    Printf.printf "\nDumping results and bug reports...\n" ;
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
      fold_traces_with_filter dug_dir slcs_dir filter
        (fun (bugs, last_slice) (_, trace) ->
          Printf.printf "%d slices loaded (trace_id: %d)\r" trace.slice_id
            trace.trace_id ;
          flush stdout ;
          let result, score = M.eval stats trace in
          let csv_row =
            Printf.sprintf "%d,%d,%s,%s,%s,%f,\"%s\"\n" trace.slice_id
              trace.trace_id trace.entry trace.call_edge.callee
              trace.call_edge.location score
              (M.Checker.to_string result)
          in
          Printf.fprintf results_oc "%s" csv_row ;
          if score > !Options.report_threshold then (
            Printf.fprintf bugs_oc "%s" csv_row ;
            let bugs =
              IdSet.add bugs trace.call_edge.callee trace.slice_id
                trace.trace_id
            in
            if last_slice <> trace.slice_id then (
              let brief_csv_row =
                Printf.sprintf "%d,%s,%s,%s,%f,\"%s\"\n" trace.slice_id
                  trace.entry trace.call_edge.callee trace.call_edge.location
                  score
                  (M.Checker.to_string result)
              in
              Printf.fprintf bugs_brief_oc "%s" brief_csv_row ;
              (bugs, trace.slice_id) )
            else (bugs, last_slice) )
          else (bugs, last_slice))
        (IdSet.empty, -1)
    in
    Printf.printf "\nLabeling bugs in-place...\n" ;
    flush stdout ;
    let alarm_label = M.Checker.name ^ "-alarm" in
    IdSet.label dug_dir alarm_label bugs ;
    let checked_label = M.Checker.name ^ "-checked" in
    IdSet.label dug_dir checked_label checked_traces ;
    close_out results_oc ;
    close_out bugs_oc ;
    close_out bugs_brief_oc )

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
