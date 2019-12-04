(* Debug Options *)
let debug = ref false

let no_filter_duplication = ref false

(* Output Options *)
let outdir_ = ref "out"

let outdir () = Utils.get_abs_path !outdir_

let verbose = ref 0

(* Slicer Options *)
let slice_depth = ref 5

let output_callgraph = ref false

let min_freq = ref 0

let target_function_name = ref ""

(* Executor Options *)
let continue_extraction = ref false

let max_traces = ref 50

let max_length = ref max_int

let max_trials = ref 2000

let no_control_flow = ref false

let output_dot = ref false

let output_trace = ref false

(* Analyzer Options *)
let report_threshold = ref 0.8

let common_opts_local =
  [ ("-debug", Arg.Set debug, "Enable debug mode")
  ; ("-verbose", Arg.Set_int verbose, "Verbose")
  ; ("-outdir", Arg.Set_string outdir_, "Output directory") ]

let slicer_opts_local =
  [ ("-n", Arg.Set_int slice_depth, "Code slicing depth")
  ; ("-output-callgraph", Arg.Set output_callgraph, "Output callgraph dot file")
  ; ( "-min-freq"
    , Arg.Set_int min_freq
    , "Target function requires minimum amount of slices" )
  ; ("-fn", Arg.Set_string target_function_name, "Target function name") ]

let executor_opts_local =
  [ ("-max-traces", Arg.Set_int max_traces, "Maximum number of traces")
  ; ("-max-length", Arg.Set_int max_length, "Maximum length of a trace")
  ; ("-max-trials", Arg.Set_int max_trials, "Maximum number of trials")
  ; ( "-no-filter-duplication"
    , Arg.Set no_filter_duplication
    , "Do not fliter out duplicatated def-use graphs" )
  ; ( "-no-control-flow"
    , Arg.Set no_control_flow
    , "Do not include control-flow edges" )
  ; ("-output-dot", Arg.Set output_dot, "Output Graphviz dot files")
  ; ("-output-trace", Arg.Set output_trace, "Output trace files") ]

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

let all_opts =
  common_opts_local @ slicer_opts_local @ executor_opts_local
  @ extractor_opts_local @ analyzer_opts_local

let common_opts = common_opts_local

let options = ref all_opts
