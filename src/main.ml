let analyzer_opts = []

let executor_opts = []

let options = ref []

type task = All | Analyze | Execute

let task = ref All

let input_file = ref ""

let get_filename name = Filename.concat (Sys.getcwd ()) name

let parse_arg arg =
  if !Arg.current = 1 then
    match arg with
    | "analyze" ->
        options := analyzer_opts ;
        task := Analyze
    | "execute" ->
        options := executor_opts ;
        task := Execute
    | _ ->
        input_file := get_filename arg
  else input_file := get_filename arg

let usage = "llexetractor [all | analyze | execute] [OPTIONS] [FILE]"

let main () =
  Arg.parse_dynamic options parse_arg usage ;
  match !task with
  | Analyze ->
      Llanalyzer.main !input_file
  | Execute ->
      Llexecutor.main !input_file
  | All ->
      failwith "Not supported yet"

let _ = main ()
