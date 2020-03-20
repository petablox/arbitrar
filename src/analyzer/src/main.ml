type task =
  | All
  | Slice
  | Occurence
  | Extract
  | Filter
  | Analyze
  | CallGraph
  | Feature

let task = ref All

let input_file = ref ""

let parse_arg arg =
  if !Arg.current = 1 then
    match arg with
    | "slice" ->
        Options.options := Options.slicer_opts ;
        task := Slice
    | "occurence" ->
        task := Occurence
    | "extract" ->
        Options.options := Options.extractor_opts ;
        task := Extract
    | "filter" ->
        Options.options := Options.common_opts ;
        task := Filter
    | "analyze" ->
        Options.options := Options.analyzer_opts ;
        task := Analyze
    | "call-graph" ->
        Options.options := Options.common_opts ;
        task := CallGraph
    | "feature" ->
        task := Feature
    | _ ->
        input_file := Utils.get_abs_path arg
  else input_file := Utils.get_abs_path arg

let usage =
  "llexetractor [all | slice | occurence | extract | filter | analyze | \
   feature |call-graph] [OPTIONS] [FILE]"

let call_graph input_file =
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_irreader.parse_ir llctx llmem in
  let call_graph = Slicer.CallGraph.from_llm llm in
  Slicer.dump_call_graph call_graph ;
  Slicer.print_call_graph llm call_graph

let main () =
  Arg.parse_dynamic Options.options parse_arg usage ;
  let outdir = Options.outdir () in
  match !task with
  | CallGraph ->
      call_graph !input_file
  | Occurence ->
      Slicer.occurence !input_file
  | Slice ->
      Slicer.main !input_file
  | Extract ->
      Extractor.main !input_file
  | Filter ->
      Filter.main !input_file
  | Analyze ->
      Analyzer.main !input_file
  | Feature ->
      Features.main !input_file
  | All ->
      Extractor.main !input_file ;
      Filter.main outdir ;
      Analyzer.main outdir ;
      Features.main outdir

let _ = main ()

(* Static API Misuse Detection *)