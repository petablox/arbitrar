open Semantics
module Metadata = Executor.Metadata

let run_one_slice lc llctx llm initial_state idx (slice : Slicer.Slice.t) :
    Executor.Environment.t =
  let poi = slice.call_edge in
  let boundaries = slice.functions in
  let entry = slice.entry in
  let target = poi.instr in
  let initial_state = State.set_target target initial_state in
  let env =
    Executor.execute_function llctx entry
      {Executor.Environment.empty with boundaries; initial_state}
      initial_state
  in
  if !Options.verbose > 0 then
    Printf.printf "\n%d traces starting from %s\n"
      (Executor.Traces.length env.Executor.Environment.traces)
      (Llvm.value_name entry) ;
  let target_name =
    Llvm.operand target (Llvm.num_operands target - 1) |> Llvm.value_name
  in
  let file_prefix = target_name ^ "-" ^ string_of_int idx ^ "-" in
  let dugraphs_prefix = !Options.outdir ^ "/dugraphs/" ^ file_prefix in
  let traces_prefix = !Options.outdir ^ "/traces/" ^ file_prefix in
  let dots_prefix = !Options.outdir ^ "/dots/" ^ file_prefix in
  if !Options.verbose > 0 then Executor.print_report lc env ;
  if !Options.output_trace then Executor.dump_traces ~prefix:traces_prefix env ;
  if !Options.output_dot then Executor.dump_dots ~prefix:dots_prefix env ;
  Executor.dump_dugraphs ~prefix:dugraphs_prefix env ;
  env

let log_command log_channel : unit =
  Printf.fprintf log_channel "Command:\n# " ;
  Array.iter (fun arg -> Printf.fprintf log_channel "%s " arg) Sys.argv ;
  Printf.fprintf log_channel "\n" ;
  ()

let setup_loc_channel () =
  let log_channel = open_out (!Options.outdir ^ "/log.txt") in
  log_command log_channel ; flush log_channel ; log_channel

let setup_ll_module input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  (llctx, llm)

let slice lc llctx llm : Slicer.Slices.t =
  let t0 = Sys.time () in
  (* Generate slices and dump json *)
  let slices = Slicer.slice llctx llm !Options.slice_depth in
  Slicer.Slices.dump_json ~prefix:!Options.outdir llm slices ;
  (* Log and print *)
  let str =
    Printf.sprintf "Slicing complete in %f sec\n" (Sys.time () -. t0)
  in
  Printf.printf "%s" str ;
  flush stdout ;
  Printf.fprintf lc "%s" str ;
  (* Return slices *)
  slices

let slices_file_exists slice_file : bool = Sys.file_exists slice_file

let load_slices_from_json lc slice_file llm : Slicer.Slices.t =
  let json = Yojson.Safe.from_file slice_file in
  Slicer.Slices.from_json llm json

let get_slices lc llctx llm : Slicer.Slices.t =
  let slice_file = !Options.outdir ^ "/slices.json" in
  if !Options.continue_extraction && slices_file_exists slice_file then
    load_slices_from_json lc slice_file llm
  else slice lc llctx llm

let execute lc llctx llm slices =
  let t0 = Sys.time () in
  let initial_state = Executor.initialize llctx llm State.empty in
  let metadata =
    List.fold_left
      (fun (metadata, idx) slice ->
        Printf.printf "%d/%d slices processing\r" (idx + 1)
          (List.length slices) ;
        flush stdout ;
        let env = run_one_slice lc llctx llm initial_state idx slice in
        (Metadata.merge metadata env.metadata, idx + 1))
      (Metadata.empty, 0) slices
    |> fst
  in
  let msg =
    Printf.sprintf "Symbolic Execution complete in %f sec\n" (Sys.time () -. t0)
  in
  Printf.printf "\n%s" msg ;
  flush stdout ;
  Printf.fprintf lc "%s" msg ;
  Metadata.print lc metadata

let initialize_directories () =
  List.iter Utils.mkdir
    [ !Options.outdir
    ; !Options.outdir ^ "/dugraphs"
    ; !Options.outdir ^ "/dots"
    ; !Options.outdir ^ "/traces" ]

let main input_file =
  initialize_directories () ;
  let log_channel = setup_loc_channel () in
  let llctx, llm = setup_ll_module input_file in
  let slices = get_slices log_channel llctx llm in
  let _ = execute log_channel llctx llm slices in
  close_out log_channel
