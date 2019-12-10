open Processing

let target_args_used (trace : Trace.t) : bool = raise Utils.NotImplemented

let target_result_used (trace : Trace.t) : bool = raise Utils.NotImplemented

let filter (trace : Trace.t) : bool =
  target_args_used trace && target_result_used trace

let main input_directory : unit =
  Printf.printf "Filtering %s...\n" input_directory ;
  flush stdout ;
  let dugraphs_dir = input_directory ^ "/dugraphs" in
  let slices_json_dir = input_directory ^ "/slices.json" in
  Printf.printf "Loading traces...\n" ;
  flush stdout ;
  let bugs =
    fold_traces dugraphs_dir slices_json_dir
      (fun acc trace ->
        let keep = filter trace in
        if not keep then
          IdSet.add acc
            (Trace.target_func_name trace)
            trace.slice_id trace.trace_id
        else acc)
      IdSet.empty
  in
  Printf.printf "Labeling filter result...\n" ;
  flush stdout ;
  IdSet.label dugraphs_dir "label_undersized" bugs
