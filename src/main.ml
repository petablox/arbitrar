type task = All | Slice | Extract | Analyze | DumpLL | CallGraph

let task = ref All

let input_file = ref ""

let parse_arg arg =
  if !Arg.current = 1 then
    match arg with
    | "slice" ->
        Options.options := Options.slicer_opts ;
        task := Slice
    | "extract" ->
        Options.options := Options.extractor_opts ;
        task := Extract
    | "analyze" ->
        Options.options := Options.analyzer_opts ;
        task := Analyze
    | "dump-ll" ->
        Options.options := Options.common_opts ;
        task := DumpLL
    | "call-graph" ->
        Options.options := Options.common_opts ;
        task := CallGraph
    | _ ->
        input_file := Utils.get_abs_path arg
  else input_file := Utils.get_abs_path arg

let usage =
  "llexetractor [all | slice | extract | analyze | dump-ll | call-graph] \
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
  let call_graph = Slicer.CallGraph.from_llm llm in
  Slicer.dump_call_graph call_graph ;
  Slicer.print_call_graph llm call_graph

let main () =
  Arg.parse_dynamic Options.options parse_arg usage ;
  match !task with
  | DumpLL ->
      dump !input_file
  | CallGraph ->
      call_graph !input_file
  | Slice ->
      Slicer.main !input_file
  | Extract ->
      Extractor.main !input_file
  | Analyze ->
      Analyzer.main !input_file
  | All ->
      Extractor.main !input_file ;
      Analyzer.main (Options.outdir ())

let _ = main ()
