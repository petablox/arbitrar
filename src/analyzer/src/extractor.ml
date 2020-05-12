open Semantics
module Metadata = Executor.Metadata

let run_one_slice lc outdir llctx llm initial_state idx (slice : Slicer.Slice.t)
    : Executor.Environment.t =
  Utils.clear_llvalue_string_cache () ;
  let poi = slice.call_edge in
  let boundaries = slice.functions in
  let entry = slice.entry in
  let target = poi.instr in
  let initial_state = State.set_target_instr target initial_state in
  let env = Executor.Environment.empty () in
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
    |> Utils.ll_func_name |> Option.get
  in
  let file_prefix = target_name ^ "-" ^ string_of_int idx in
  let dugraphs_prefix = outdir ^ "/dugraphs/" ^ file_prefix in
  let traces_prefix = outdir ^ "/traces/" ^ file_prefix in
  let dots_prefix = outdir ^ "/dots/" ^ file_prefix in
  if !Options.verbose > 0 then Executor.print_report lc env ;
  if !Options.output_trace then Executor.dump_traces ~prefix:traces_prefix env ;
  if !Options.output_dot then Executor.dump_dots ~prefix:dots_prefix env ;
  Executor.dump_dugraphs ~prefix:dugraphs_prefix env ;
  env

(* This should never happen *)

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
  (* Generate slices and dump json *)
  let slices = Slicer.slice llctx llm !Options.slice_depth in
  Slicer.Slices.dump_json ~prefix:outdir llm slices ;
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

let execute lc outdir llctx llm slices =
  let t0 = Sys.time () in
  let initial_state = Executor.initialize llctx llm State.empty in
  let _ =
    List.iteri
      (fun idx slice ->
        Printf.printf "%d/%d slices processing\r" (idx + 1) (List.length slices) ;
        flush stdout ;
        let _ = run_one_slice lc outdir llctx llm initial_state idx slice in
        ())
      slices
  in
  let msg =
    Printf.sprintf "Symbolic Execution complete in %f sec\n" (Sys.time () -. t0)
  in
  Printf.printf "\n%s" msg ; flush stdout ; Printf.fprintf lc "%s" msg

let main input_file =
  Printf.printf "Running extractor on %s...\n" input_file ;
  flush stdout ;
  let outdir = Options.outdir () in
  Utils.initialize_output_directories outdir ;
  let log_channel = setup_loc_channel outdir in
  let llctx, llm = setup_ll_module input_file in
  Printf.printf "Slicing program...\n" ;
  flush stdout ;
  let slices = get_slices log_channel outdir llctx llm in
  let _ = execute log_channel outdir llctx llm slices in
  close_out log_channel
