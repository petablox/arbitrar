type task = All | Analyze | Execute

let task = ref All

let input_file = ref ""

let get_filename name = Filename.concat (Sys.getcwd ()) name

let parse_arg arg =
  if !Arg.current = 1 then
    match arg with
    | "analyze" ->
        Options.options := Options.analyzer_opts ;
        task := Analyze
    | "execute" ->
        Options.options := Options.executor_opts ;
        task := Execute
    | _ ->
        input_file := get_filename arg
  else input_file := get_filename arg

let usage = "llexetractor [all | analyze | execute] [OPTIONS] [FILE]"

let main () =
  Arg.parse_dynamic Options.options parse_arg usage ;
  match !task with
  | Analyze ->
      Llanalyzer.main !input_file
  | Execute ->
      Llexecutor.main !input_file
  | All ->
      failwith "Not supported yet"

let _ = main ()
