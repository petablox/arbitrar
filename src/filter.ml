open Processing

let rec used_in_location (ret : Value.t) (loc : Location.t) : bool =
  match loc with
  | Location.SymExpr e ->
      ret = Value.SymExpr e
  | Location.Gep l ->
      used_in_location ret l
  | _ ->
      false

(* Assuming store/load/ret does not count as "use" *)
let used_in_stmt (ret : Value.t) (stmt : Statement.t) : bool =
  match stmt with
  | Call {args} ->
      List.find_opt (( = ) ret) args |> Option.is_some
  | Assume {op0; op1} ->
      op0 = ret || op1 = ret
  | Binary {op0; op1} ->
      op0 = ret || op1 = ret
  | Store {loc; value} ->
      let used_in_loc =
        match loc with
        | Location loc ->
            used_in_location ret loc
        | _ ->
            loc = ret
      in
      used_in_loc || value = ret
  | GetElementPtr {op0} ->
      op0 = ret
  | _ ->
      false

let initialized_in_stmt (arg : Value.t) (stmt : Statement.t) : bool =
  match stmt with
  | Call {result= Some res} ->
      arg = res
  | Assume {result} ->
      arg = result
  | Load {result} ->
      arg = result
  | Binary {result} ->
      arg = result
  | _ ->
      false

let rec arg_initialized dugraph explored fringe arg =
  match NodeSet.choose_opt fringe with
  | Some hd ->
      let rst = NodeSet.remove hd fringe in
      if NodeSet.mem hd explored then arg_initialized dugraph explored rst arg
      else if initialized_in_stmt arg hd.stmt then true
      else
        let explored = NodeSet.add hd explored in
        let predecessors = NodeSet.of_list (NodeGraph.pred dugraph hd) in
        let fringe = NodeSet.union predecessors rst in
        arg_initialized dugraph explored fringe arg
  | None ->
      false

let args_initialized (trace : Trace.t) : bool =
  match trace.target_node.stmt with
  | Call {args} ->
      let non_const_args =
        List.filter (fun arg -> Value.is_const arg |> not) args
      in
      if List.length non_const_args = 0 then false
      else
        let fringe = NodeSet.singleton trace.target_node in
        List.map
          (arg_initialized trace.dugraph NodeSet.empty fringe)
          non_const_args
        |> List.fold_left ( && ) true
  | _ ->
      false

let rec result_used_helper ret dugraph explored fringe =
  match NodeSet.choose_opt fringe with
  | Some hd ->
      if NodeSet.mem hd explored then false
      else if used_in_stmt ret hd.stmt then true
      else
        let rst = NodeSet.remove hd fringe in
        let explored = NodeSet.add hd explored in
        let successors = NodeSet.of_list (NodeGraph.succ dugraph hd) in
        let fringe = NodeSet.union successors rst in
        result_used_helper ret dugraph explored fringe
  | None ->
      false

let result_used (trace : Trace.t) : bool =
  match trace.target_node.stmt with
  | Call {result} -> (
    match result with
    | Some ret ->
        let sgt_target = NodeSet.singleton trace.target_node in
        result_used_helper ret trace.dugraph NodeSet.empty sgt_target
    | None ->
        false )
  | _ ->
      false

let has_context (trace : Trace.t) : bool =
  args_initialized trace || result_used trace

let do_filter_and_label input_directory =
  Printf.printf "Filtering %s...\n" input_directory ;
  flush stdout ;
  let dugraphs_dir = input_directory ^ "/dugraphs" in
  let slices_json_dir = input_directory ^ "/slices.json" in
  Printf.printf "Loading traces...\n" ;
  flush stdout ;
  let no_contexts =
    fold_traces dugraphs_dir slices_json_dir
      (fun acc trace ->
        let keep = has_context trace in
        if not keep then
          IdSet.add acc
            (Trace.target_func_name trace)
            trace.slice_id trace.trace_id
        else acc)
      IdSet.empty
  in
  Printf.printf "Labeling filter result...\n" ;
  flush stdout ;
  IdSet.label dugraphs_dir "no-context" no_contexts

let main input_directory : unit =
  if not !Options.no_filter then do_filter_and_label input_directory
