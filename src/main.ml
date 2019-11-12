open Semantics

type task = All | Slice | Execute

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
    | _ ->
        input_file := get_filename arg
  else input_file := get_filename arg

let usage = "llexetractor [all | slice | execute] [OPTIONS] [FILE]"

let run_one_slice llctx llm idx (boundaries, entry, poi) =
  let _, _, target = poi in
  let initial_state =
    Llexecutor.initialize llctx llm {State.empty with target= Some target}
  in
  let env =
    Llexecutor.execute_function llctx entry Llexecutor.Environment.empty
      initial_state
  in
  let dugraphs =
    let target_node = NodeMap.find target initial_state.State.nodemap in
    List.map (Llexecutor.slice target_node) env.dugraphs
  in
  let env = {env with dugraphs} in
  let target_name =
    Llvm.operand target (Llvm.num_operands target - 1) |> Llvm.value_name
  in
  let file_prefix = target_name ^ "-" ^ string_of_int idx ^ "-" in
  let dugraph_prefix = !Options.outdir ^ "/dugraphs/" ^ file_prefix in
  let trace_prefix = !Options.outdir ^ "/traces/" ^ file_prefix in
  Llexecutor.print_report env ;
  Llexecutor.dump_traces ~prefix:trace_prefix env ;
  Llexecutor.dump_dugraph ~prefix:dugraph_prefix env

let run input_file =
  let default_slice_depth = 5 in
  let llctx = Llvm.create_context () in
  let llmem = Llvm.MemoryBuffer.of_file input_file in
  let llm = Llvm_bitreader.parse_bitcode llctx llmem in
  (* Start getting call graph and after that, slices *)
  let call_graph = Llslicer.get_call_graph llm in
  let slices =
    List.map (Llslicer.find_slices default_slice_depth call_graph) call_graph
    |> List.flatten
  in
  List.iteri (run_one_slice llctx llm) slices

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
  | Slice ->
      Llslicer.main !input_file
  | Execute ->
      Llexecutor.main !input_file
  | All ->
      run !input_file

let _ = main ()
