open Semantics
module Metadata = Executor.Metadata

let run_one_slice lc outdir llctx llm initial_state idx (slice : Slicer.Slice.t)
    : Executor.Environment.t =
  let poi = slice.call_edge in
  let boundaries = slice.functions in
  let entry = slice.entry in
  let target = poi.instr in
  let initial_state = State.set_target_instr target initial_state in
  let env = Executor.Environment.empty llctx target in
  let env =
    Executor.execute_function llctx entry
      {env with boundaries; initial_state}
      initial_state
  in
  if !Options.verbose > 0 then
    Printf.printf "\n%d traces starting from %s\n"
      (Executor.Traces.length env.Executor.Environment.traces)
      (Llvm.value_name entry) ;
  let target_name =
    Llvm.operand target (Llvm.num_operands target - 1)
    |> Utils.GlobalCache.ll_func |> Option.get
  in
  let file_prefix = target_name ^ "-" ^ string_of_int idx in
  let dugraphs_prefix = outdir ^ "/dugraphs/" ^ file_prefix in
  let traces_prefix = outdir ^ "/traces/" ^ file_prefix in
  let discarded_prefix = outdir ^ "/discarded/" ^ file_prefix in
  let dots_prefix = outdir ^ "/dots/" ^ file_prefix in
  if !Options.verbose > 0 then Executor.print_report lc env ;
  if !Options.output_trace then Executor.dump_traces ~prefix:traces_prefix env ;
  if !Options.output_trace then
    Executor.dump_discarded ~prefix:discarded_prefix env ;
  if !Options.output_dot then Executor.dump_dots ~prefix:dots_prefix env ;
  Executor.dump_dugraphs ~prefix:dugraphs_prefix env ;
  env

let log_command log_channel : unit =
  Printf.fprintf log_channel "Command:\n# " ;
  Array.iter (fun arg -> Printf.fprintf log_channel "%s " arg) Sys.argv ;
  Printf.fprintf log_channel "\n" ;
  ()

let setup_loc_channel outdir =
  let log_channel = open_out (outdir ^ "/log.txt") in
  log_command log_channel ; flush log_channel ; log_channel

let setup_ll_module input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_irreader.parse_ir llctx llmem in
  (llctx, llm)

let slice lc outdir llctx llm : Slicer.Slices.t =
  let t0 = Sys.time () in
  (* Generate slices *)
  let slices = Slicer.slice llctx llm !Options.slice_depth in
  (* Clean up GC *)
  Gc.compact () ;
  (* Dump json *)
  Slicer.Slices.dump_json ~prefix:outdir llm slices ;
  (* Clean up GC *)
  Gc.compact () ;
  (* Log and print *)
  let str = Printf.sprintf "Slicing complete in %f sec\n" (Sys.time () -. t0) in
  Printf.printf "%s" str ;
  flush stdout ;
  Printf.fprintf lc "%s" str ;
  (* Return slices *)
  slices

let slices_file_exists slice_file : bool = Sys.file_exists slice_file

let load_slices_from_json lc slice_file llm : Slicer.Slices.t =
  let json = Yojson.Safe.from_file slice_file in
  Slicer.Slices.from_json llm json

let get_slices lc outdir llctx llm : Slicer.Slices.t =
  let slice_file = outdir ^ "/slices.json" in
  if !Options.continue_extraction && slices_file_exists slice_file then
    load_slices_from_json lc slice_file llm
  else slice lc outdir llctx llm

let loading idx =
  let i = idx mod 4 in
  match i with 0 -> '|' | 1 -> '/' | 2 -> '-' | _ -> '\\'

let execute lc outdir llctx llm slices =
  let t0 = Sys.time () in
  let initial_state = Executor.initialize llctx llm State.empty in
  let num_slices = List.length slices in
  if num_slices > 0 then (
    if !Options.serial_execution then
      List.iteri
        (fun i slice ->
          Printf.printf "Doing symbolic execution on %d/%d slice\r" (i + 1)
            num_slices ;
          flush stdout ;
          let _ = run_one_slice lc outdir llctx llm initial_state i slice in
          ())
        slices
    else
      let array_slices = Array.of_list slices in
      ignore
        (Parmap.parmap
           (fun idx ->
             let slice = array_slices.(idx) in
             let _ =
               run_one_slice lc outdir llctx llm initial_state idx slice
             in
             Gc.compact () ;
             Printf.printf "Doing symbolic execution on %d slice %c\r"
               num_slices (loading idx) ;
             flush stdout)
           (Parmap.L (Utils.range num_slices))) ;
      let msg =
        Printf.sprintf "Symbolic Execution complete in %f sec\n"
          (Sys.time () -. t0)
      in
      Printf.printf "\n%s" msg ; flush stdout ; Printf.fprintf lc "%s" msg )

let extractor_main input_file =
  Printf.printf "Running extractor on %s...\n" input_file ;
  flush stdout ;
  let outdir = Options.outdir () in
  Utils.initialize_output_directories outdir ;
  flush stdout ;
  let log_channel = setup_loc_channel outdir in
  Printf.printf "Loading input file %s...\n" input_file ;
  flush stdout ;
  let llctx, llm = setup_ll_module input_file in
  Printf.printf "Slicing program...\n" ;
  flush stdout ;
  let slices = get_slices log_channel outdir llctx llm in
  let _ = execute log_channel outdir llctx llm slices in
  close_out log_channel

let get_batches edge_entries =
  let _, last_batch, batches =
    Slicer.EdgeEntriesMap.fold
      (fun edge entries (index, curr_batch, batches) ->
        if index > 0 && index mod !Options.batch_size == 0 then
          ( index + 1
          , Slicer.EdgeEntriesMap.add Slicer.EdgeEntriesMap.empty edge entries
          , curr_batch :: batches )
        else
          (index + 1, Slicer.EdgeEntriesMap.add curr_batch edge entries, batches))
      edge_entries
      (0, Slicer.EdgeEntriesMap.empty, [])
  in
  last_batch :: batches

let batched_extractor_main input_file =
  Printf.printf "Running extractor with batch size %d on %s...\n"
    !Options.batch_size input_file ;
  flush stdout ;
  let outdir = Options.outdir () in
  Utils.mkdir outdir ;
  Printf.printf "Loading input file %s...\n" input_file ;
  flush stdout ;
  let llctx, llm = setup_ll_module input_file in
  Printf.printf "Generating slicing context...\n" ;
  flush stdout ;
  let slicing_ctx =
    Slicer.SlicingContext.create llctx llm !Options.slice_depth
  in
  Printf.printf "Generating call edges...\n" ;
  flush stdout ;
  let func_counter, edge_entries = Slicer.call_edges slicing_ctx in
  Printf.printf "Generating batches with %d call edges...\n"
    (Slicer.EdgeEntriesMap.size edge_entries) ;
  flush stdout ;
  let batches = get_batches edge_entries in
  Printf.printf "Dividing into %d batches...\n" (List.length batches) ;
  flush stdout ;
  List.iteri
    (fun i batched_edge_entries ->
      Gc.compact () ;
      Printf.printf "Executing batch %d with %d edges...\n" i
        (Slicer.EdgeEntriesMap.size batched_edge_entries) ;
      flush stdout ;
      let outdir = Options.batched_outdir i in
      Utils.initialize_output_directories outdir ;
      let log_channel = setup_loc_channel outdir in
      let num_slices, slices =
        Slicer.slices_from_edges func_counter batched_edge_entries slicing_ctx
      in
      Slicer.Slices.dump_json ~prefix:outdir llm slices ;
      Printf.printf "Doing symbolic execution on %d slice        \r" num_slices ;
      flush stdout ;
      let _ = execute log_channel outdir llctx llm slices in
      close_out log_channel)
    batches

let main input_file =
  if !Options.use_batch then batched_extractor_main input_file
  else extractor_main input_file
