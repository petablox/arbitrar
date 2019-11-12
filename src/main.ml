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

let main () =
  Arg.parse_dynamic Options.options parse_arg usage ;
  match !task with
  | Slice ->
      Llslicer.main !input_file
  | Execute ->
      Llexecutor.main !input_file
  | All ->
      failwith "Not supported yet"

let _ = main ()
