let debug = ref false

let outdir = ref "extractor-out"

let slice_depth = ref 5

let target_function_name = ref ""

let verbose = ref 0

let max_traces = ref (-1)

let max_length = ref (-1)

let common_opts_local =
  [ ("-debug", Arg.Set debug, "Enable debug mode")
  ; ("-verbose", Arg.Set_int verbose, "Verbose")
  ; ("-outdir", Arg.Set_string outdir, "Output directory") ]

let slicer_opts_local =
  [ ("-n", Arg.Set_int slice_depth, "Code slicing depth")
  ; ("-fn", Arg.Set_string target_function_name, "Target function name") ]

let executor_opts_local =
  [ ("-max-traces", Arg.Set_int max_traces, "Maximum number of traces")
  ; ("-max-length", Arg.Set_int max_length, "Maximum length of a trace") ]

let slicer_opts = common_opts_local @ slicer_opts_local

let executor_opts = common_opts_local @ executor_opts_local

let extractor_opts =
  common_opts_local @ slicer_opts_local @ executor_opts_local

let common_opts = common_opts_local

let options = ref extractor_opts
