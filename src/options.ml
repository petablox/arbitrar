let debug = ref false

let outdir = ref "extractor-out"

let common_opt =
  [ ("-debug", Arg.Set debug, "Enable debug mode")
  ; ("-outdir", Arg.Set_string outdir, "Output directory") ]

let slicer_opts = common_opt

let executor_opts = common_opt

let extractor_opts = common_opt

let options = ref extractor_opts
