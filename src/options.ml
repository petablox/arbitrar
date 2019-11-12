let debug = ref false

let slicer_opts = [("-debug", Arg.Set debug, "Enable debug mode")]

let executor_opts = [("-debug", Arg.Set debug, "Enable debug mode")]

let options = ref [("-debug", Arg.Set debug, "Enable debug mode")]
