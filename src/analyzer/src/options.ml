(* Debug Options *)
let debug = ref false

let no_filter_duplication = ref false

(* Output Options *)
let outdir_ = ref "llextractor-out"

let outdir () = Utils.get_abs_path !outdir_

let verbose = ref 0

let pretty_json = ref false

let json_to_channel oc json =
  if !pretty_json then Yojson.Safe.pretty_to_channel oc json
  else Yojson.Safe.to_channel oc json

(* Slicer Options *)
let slice_depth = ref 5

let output_callgraph = ref false

let min_freq = ref 0

let include_func = ref ""

let exclude_func = ref ""

(* Occurrence Options *)
let occ_output_csv = ref true

let occ_output_json = ref false

(* Filter Options *)
let no_filter = ref false

(* Executor Options *)
let serial_execution = ref false

let continue_extraction = ref false

let max_traces = ref 50

let max_length = ref max_int

let max_trials = ref 2000

let max_symbols = ref 10

let no_control_flow = ref false

let include_instr = ref false

let output_dot = ref false

let output_trace = ref false

let no_reduction = ref false

let no_path_constraint = ref false

(* Analyzer Options *)
let no_analysis = ref false

let report_threshold = ref 0.9

let checker = ref "all"

(* Feature Options *)
let causality_dict_size = ref 5

let common_opts_local =
  [ ("-debug", Arg.Set debug, "Enable debug mode")
  ; ("-verbose", Arg.Set_int verbose, "Verbose")
  ; ("-outdir", Arg.Set_string outdir_, "Output directory")
  ; ("-pretty-json", Arg.Set pretty_json, "Output prettified JSON") ]

let slicer_opts_local =
  [ ("-n", Arg.Set_int slice_depth, "Code slicing depth")
  ; ("-output-callgraph", Arg.Set output_callgraph, "Output callgraph dot file")
  ; ( "-min-freq"
    , Arg.Set_int min_freq
    , "Target function requires minimum amount of slices" )
  ; ("-include-fn", Arg.Set_string include_func, "Target function regex")
  ; ("-exclude-fn", Arg.Set_string exclude_func, "Exclude function regex") ]

let occurrence_opts_local =
  [("-json", Arg.Set occ_output_json, "Output .json file")]

let executor_opts_local =
  [ ("-max-traces", Arg.Set_int max_traces, "Maximum number of traces per slice")
  ; ("-max-length", Arg.Set_int max_length, "Maximum length of a trace")
  ; ("-max-trials", Arg.Set_int max_trials, "Maximum number of trials")
  ; ( "-no-filter-duplication"
    , Arg.Set no_filter_duplication
    , "Do not fliter out duplicatated def-use graphs" )
  ; ( "-max-symbols"
    , Arg.Set_int max_symbols
    , "Maximum size of a symbolic expression" )
  ; ( "-no-control-flow"
    , Arg.Set no_control_flow
    , "Do not include control-flow edges" )
  ; ("-output-dot", Arg.Set output_dot, "Output Graphviz dot files")
  ; ("-output-trace", Arg.Set output_trace, "Output trace files")
  ; ( "-include-instr"
    , Arg.Set include_instr
    , "Include instruction in dugraph JSON" )
  ; ("-no-reduction", Arg.Set no_reduction, "Do not reduce graphs")
  ; ( "-no-path-constraint"
    , Arg.Set no_path_constraint
    , "Do not use path constraint" )
  ; ("-serial", Arg.Set serial_execution, "Execute in serial as opposed to parallel") ]

let extractor_opts_local =
  [ ( "-continue"
    , Arg.Set continue_extraction
    , "Continue from previously stopped position" ) ]

let filter_opts_local =
  [("-no-filter", Arg.Set no_filter, "Does not check undersize")]

let analyzer_opts_local =
  [ ("-no-analysis", Arg.Set no_analysis, "No analysis")
  ; ( "-thres"
    , Arg.Set_float report_threshold
    , "Score threshold for reporting bugs" )
  ; ( "-checker"
    , Arg.Set_string checker
    , "The checker to run. e.g. argrel, retval" ) ]

let feature_opts_local =
  [ ( "-causality-dict-size"
    , Arg.Set_int causality_dict_size
    , "Causality Dictionary Size" ) ]

let slicer_opts = common_opts_local @ slicer_opts_local

let occurrence_opts =
  common_opts_local @ slicer_opts_local @ occurrence_opts_local

let executor_opts = common_opts_local @ executor_opts_local

let extractor_opts =
  common_opts_local @ slicer_opts_local @ executor_opts_local
  @ extractor_opts_local

let filter_opts = common_opts_local @ filter_opts_local

let analyzer_opts = common_opts_local @ analyzer_opts_local

let feature_opts = common_opts_local @ slicer_opts_local @ feature_opts_local

let all_opts =
  common_opts_local @ slicer_opts_local @ executor_opts_local
  @ extractor_opts_local @ filter_opts_local @ analyzer_opts_local
  @ feature_opts_local

let common_opts = common_opts_local

let options = ref all_opts
