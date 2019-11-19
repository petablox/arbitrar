open Semantics
module Metadata = Executor.Metadata

let run_one_slice log_channel llctx llm idx (slice : Slicer.Slice.t) :
    Executor.Environment.t =
  let poi = slice.call_edge in
  let boundaries = slice.functions in
  let entry = slice.entry in
  let target = poi.instr in
  let initial_state =
    Executor.initialize llctx llm {State.empty with target= Some target}
  in
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
  let dugraph_prefix = !Options.outdir ^ "/dugraphs/" ^ file_prefix in
  let trace_prefix = !Options.outdir ^ "/traces/" ^ file_prefix in
  if !Options.verbose > 0 then Executor.print_report log_channel env ;
  if !Options.debug then Executor.dump_traces ~prefix:trace_prefix env ;
  Executor.dump_dugraph ~prefix:dugraph_prefix env ;
  env

let log_command log_channel : unit =
  Printf.fprintf log_channel "Command:\n# " ;
  Array.iter (fun arg -> Printf.fprintf log_channel "%s " arg) Sys.argv ;
  Printf.fprintf log_channel "\n" ;
  ()

let main input_file =
  (* Start a log channel *)
  let log_channel = open_out (!Options.outdir ^ "/log.txt") in
  log_command log_channel ;
  flush log_channel ;
  (* Setup the llvm context and module *)
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  (* Start to slice the program *)
  let t0 = Sys.time () in
  let slices = Slicer.slice llm !Options.slice_depth in
  Slicer.Slices.dump_json ~prefix:!Options.outdir llm slices ;
  Printf.printf "Slicing complete in %f sec\n" (Sys.time () -. t0) ;
  flush stdout ;
  (* Run execution on each slice and merge all metadata *)
  let t0 = Sys.time () in
  let metadata =
    List.fold_left
      (fun (metadata, idx) slice ->
        Printf.printf "%d/%d slices processing\r" (idx + 1)
          (List.length slices) ;
        flush stdout ;
        let env = run_one_slice log_channel llctx llm idx slice in
        (Metadata.merge metadata env.metadata, idx + 1))
      (Metadata.empty, 0) slices
    |> fst
  in
  (* Finish the run and log metadata *)
  Printf.printf "\n" ;
  flush stdout ;
  Metadata.print log_channel metadata ;
  Printf.printf "Symbolic Execution complete in %f sec\n" (Sys.time () -. t0) ;
  close_out log_channel
