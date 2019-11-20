module F = Format

type task = All | Slice | Execute | Analyze | DumpLL | CallGraph

let task = ref All

let input_file = ref ""

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
        Options.options := Options.common_opts ;
        task := CallGraph
    | "analyze" ->
        Options.options := Options.common_opts ;
        task := Analyze
    | _ ->
        input_file := Utils.get_abs_path arg
  else input_file := Utils.get_abs_path arg

let usage =
  "llexetractor [all | slice | execute | analyze | dump-ll | call-graph] \
   [OPTIONS] [FILE]"

let dump input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  Llvm.dump_module llm

let call_graph input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  let call_graph = Slicer.get_call_graph llm in
  Slicer.dump_call_graph call_graph ;
  Slicer.print_call_graph llm call_graph

let mkdir dirname =
  if Sys.file_exists dirname && Sys.is_directory dirname then ()
  else if Sys.file_exists dirname && not (Sys.is_directory dirname) then
    let _ = F.fprintf F.err_formatter "Error: %s already exists." dirname in
    exit 1
  else Unix.mkdir dirname 0o755

let initialize_directories () =
  List.iter mkdir
    [ !Options.outdir
    ; !Options.outdir ^ "/dugraphs"
    ; !Options.outdir ^ "/traces" ]

let main () =
  Arg.parse_dynamic Options.options parse_arg usage ;
  match !task with
  | DumpLL ->
      dump !input_file
  | CallGraph ->
      call_graph !input_file
  | Analyze ->
      Analyzer.main !input_file
  | Slice ->
      Slicer.main !input_file
  | Execute ->
      initialize_directories () ; Executor.main !input_file
  | All ->
      initialize_directories () ; Extractor.main !input_file

let _ = main ()
