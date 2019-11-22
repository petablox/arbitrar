(* Debug Options *)
let debug = ref false

let no_filter_duplication = ref false

(* Output Options *)
let outdir = ref "extractor-out"

let verbose = ref 0

(* Slicer Options *)
let slice_depth = ref 5

let target_function_name = ref ""

(* Executor Options *)
let continue_extraction = ref false

let max_traces = ref max_int

let max_length = ref max_int

(* Analyzer Options *)
let report_threshold = ref 0.8

let common_opts_local =
  [ ("-debug", Arg.Set debug, "Enable debug mode")
  ; ("-verbose", Arg.Set_int verbose, "Verbose")
  ; ("-outdir", Arg.Set_string outdir, "Output directory") ]

let slicer_opts_local =
  [ ("-n", Arg.Set_int slice_depth, "Code slicing depth")
  ; ("-fn", Arg.Set_string target_function_name, "Target function name") ]

let executor_opts_local =
  [ ("-max-traces", Arg.Set_int max_traces, "Maximum number of traces")
  ; ("-max-length", Arg.Set_int max_length, "Maximum length of a trace")
  ; ( "-no-filter-duplication"
    , Arg.Set no_filter_duplication
    , "Do not fliter out duplicatated def-use graphs" ) ]

let extractor_opts_local =
  [ ( "-continue"
    , Arg.Set continue_extraction
    , "Continue from previously stopped position" ) ]

let analyzer_opts_local =
  [ ( "-thres"
    , Arg.Set_float report_threshold
    , "Score threshold for reporting bugs" )
  ; ("-fn", Arg.Set_string target_function_name, "Target function name") ]

let slicer_opts = common_opts_local @ slicer_opts_local

let executor_opts = common_opts_local @ executor_opts_local

let extractor_opts =
  common_opts_local @ slicer_opts_local @ executor_opts_local
  @ extractor_opts_local

let analyzer_opts = common_opts_local @ analyzer_opts_local

let common_opts = common_opts_local

let options = ref extractor_opts
