open Semantics
module Metadata = Llexecutor.Metadata

type task = All | Slice | Execute | DumpLL | CallGraph

let task = ref All

let input_file = ref ""

let get_filename name = Filename.concat (Sys.getcwd ()) name

let parse_arg arg =
  if !Arg.current = 1 then
    match arg with
    | "slice" ->
        Options.options := Options.slicer_opts ;
        task := Slice
    | "execute" ->
        Options.options := Options.executor_opts ;
        task := Execute
    | "dump-ll" ->
        Options.options := Options.common_opts ;
        task := DumpLL
    | "call-graph" ->
        Printf.printf "Printing call graph\n" ;
        Options.options := Options.common_opts ;
        task := CallGraph
    | _ ->
        input_file := get_filename arg
  else input_file := get_filename arg

let usage =
  "llexetractor [all | slice | execute | dump-ll | call-graph] [OPTIONS] [FILE]"

let dump input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  Llvm.dump_module llm

let call_graph input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let call_graph = Llslicer.get_call_graph llm in
  Llslicer.print_call_graph llm call_graph

let run_one_slice log_channel llctx llm idx (slice : Llslicer.Slice.t) =
  let poi = slice.call_edge in
  let boundaries = slice.functions in
  let entry = slice.entry in
  let target = poi.instr in
  let initial_state =
    Llexecutor.initialize llctx llm {State.empty with target= Some target}
  in
  let env =
    Llexecutor.execute_function llctx entry
      {Llexecutor.Environment.empty with boundaries; initial_state}
      initial_state
  in
  if !Options.verbose > 0 then
    Printf.printf "\n%d traces starting from %s\n"
      (Llexecutor.Traces.length env.Llexecutor.Environment.traces)
      (Llvm.value_name entry) ;
  let target_name =
    Llvm.operand target (Llvm.num_operands target - 1) |> Llvm.value_name
  in
  let file_prefix = target_name ^ "-" ^ string_of_int idx ^ "-" in
  let dugraph_prefix = !Options.outdir ^ "/dugraphs/" ^ file_prefix in
  let trace_prefix = !Options.outdir ^ "/traces/" ^ file_prefix in
  if !Options.verbose > 0 then Llexecutor.print_report log_channel env ;
  if !Options.debug then Llexecutor.dump_traces ~prefix:trace_prefix env ;
  Llexecutor.dump_dugraph ~prefix:dugraph_prefix env ;
  env.Llexecutor.Environment.metadata

let run input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let log_channel = open_out (!Options.outdir ^ "/log.txt") in
  let t0 = Sys.time () in
  let slices = Llslicer.slice llm !Options.slice_depth in
  Llslicer.Slices.dump_json ~prefix:!Options.outdir llm slices ;
  Printf.printf "Slicing complete in %f sec\n" (Sys.time () -. t0) ;
  flush stdout ;
  let t0 = Sys.time () in
  let metadata =
    List.fold_left
      (fun (metadata, idx) slice ->
        Printf.printf "%d/%d slices processing\r" (idx + 1)
          (List.length slices) ;
        flush stdout ;
        let m = run_one_slice log_channel llctx llm idx slice in
        (Metadata.merge metadata m, idx + 1))
      (Metadata.empty, 0) slices
    |> fst
  in
  Printf.printf "\n" ;
  Metadata.print stdout metadata ;
  flush stdout ;
  Printf.printf "Symbolic Execution complete in %f sec\n" (Sys.time () -. t0) ;
  close_out log_channel

let mkdir dirname =
  if Sys.file_exists dirname && Sys.is_directory dirname then ()
  else if Sys.file_exists dirname && not (Sys.is_directory dirname) then
    let _ = F.fprintf F.err_formatter "Error: %s already exists." dirname in
    exit 1
  else Unix.mkdir dirname 0o755

let initialize () =
  List.iter mkdir
    [ !Options.outdir
    ; !Options.outdir ^ "/dugraphs"
    ; !Options.outdir ^ "/traces" ]

let main () =
  Arg.parse_dynamic Options.options parse_arg usage ;
  initialize () ;
  match !task with
  | DumpLL ->
      dump !input_file
  | CallGraph ->
      call_graph !input_file
  | Slice ->
      Llslicer.main !input_file
  | Execute ->
      Llexecutor.main !input_file
  | All ->
      run !input_file

let _ = main ()
