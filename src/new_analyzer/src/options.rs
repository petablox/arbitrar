use clap::{App, Arg, ArgMatches};
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Options {
  // General Options
  pub input: String,
  pub output: String,
  pub use_serial: bool,

  // Call Graph Options
  pub no_remove_llvm_funcs: bool,

  // Slicer Options
  pub slice_depth: u8,
  pub target_inclusion_filter: Option<String>,
  pub target_exclusion_filter: Option<String>,
  pub entry_filter: Option<String>,
  pub use_regex_filter: bool,
  pub reduce_slice: bool,
  pub use_batch: bool,
  pub batch_size: usize,

  // Symbolic Execution Options
  pub max_trace_per_slice: usize,
  pub max_explored_trace_per_slice: usize,
  pub max_node_per_trace: usize,
  pub no_trace_reduction: bool,
  pub print_trace: bool,

  // Feature Extraction Options
}

impl Default for Options {
  fn default() -> Self {
    Self {
      input: "".to_string(),
      output: "".to_string(),
      use_serial: false,

      no_remove_llvm_funcs: false,

      slice_depth: 1,
      target_inclusion_filter: None,
      target_exclusion_filter: None,
      entry_filter: None,
      use_regex_filter: false,
      reduce_slice: false,

      use_batch: false,
      batch_size: 0,

      max_trace_per_slice: 50,
      max_explored_trace_per_slice: 1000,
      max_node_per_trace: 5000,
      no_trace_reduction: false,
      print_trace: false,
    }
  }
}

impl Options {
  pub fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app.args(&[

      // General options
      Arg::new("input").value_name("INPUT").index(1).required(true),
      Arg::new("output").value_name("OUTPUT").index(2).required(true),
      Arg::new("serial")
        .short('s')
        .long("serial")
        .about("Serialize execution rather than parallel"),

      // Call graph options
      Arg::new("no_remove_llvm_funcs")
        .long("--no-remove-llvm-funcs")
        .about("Do not remove llvm functions"),

      // Slicer options
      Arg::new("slice_depth")
        .value_name("SLICE_DEPTH")
        .takes_value(true)
        .short('d')
        .long("slice-depth")
        .about("Slice depth")
        .default_value("1"),
      Arg::new("target_inclusion_filter")
        .value_name("INCLUDE_TARGET")
        .takes_value(true)
        .long("include-target")
        .about("Include target functions. In the form of Regex"),
      Arg::new("use_regex_filter")
        .long("use-regex-filter")
        .about("Use Regex in inclusion/exclusion filter"),
      Arg::new("target_exclusion_filter")
        .value_name("EXCLUDE_TARGET")
        .takes_value(true)
        .long("exclude-target")
        .about("Exclude target functions. In the form of Regex"),
      Arg::new("entry_filter")
        .value_name("ENTRY_LOCATION")
        .takes_value(true)
        .long("entry-location")
        .about("Entry location filters. In the form of Regex"),
      Arg::new("reduce_slice")
        .long("reduce-slice")
        .about("Reduce slice using relevancy test"),
      Arg::new("use_batch").long("use-batch").about("Use batched execution"),
      Arg::new("batch_size")
        .value_name("BATCH_SIZE")
        .takes_value(true)
        .default_value("100")
        .long("batch-size"),

      // Symbolic Execution Options
      Arg::new("max_trace_per_slice")
        .value_name("MAX_TRACE_PER_SLICE")
        .takes_value(true)
        .long("max-trace-per-slice")
        .about("The maximum number of generated trace per slice")
        .default_value("50"),
      Arg::new("max_explored_trace_per_slice")
        .value_name("MAX_EXPLORED_TRACE_PER_SLICE")
        .takes_value(true)
        .long("max-explored-trace-per-slice")
        .about("The maximum number of explroed trace per slice")
        .default_value("1000"),
      Arg::new("max_node_per_trace")
        .value_name("MAX_NODE_PER_TRACE")
        .takes_value(true)
        .long("max-node-per-trace")
        .default_value("5000"),
      Arg::new("no_reduce_trace")
        .long("no-reduce-trace")
        .about("No trace reduction"),
      Arg::new("print_trace").long("print-trace").about("Print out trace"),
    ])
  }

  pub fn from_matches(matches: &ArgMatches) -> Result<Self, String> {
    Ok(Self {

      // General options
      input: String::from(matches.value_of("input").unwrap()),
      output: String::from(matches.value_of("output").unwrap()),
      use_serial: matches.is_present("serial"),

      // Call graph options
      no_remove_llvm_funcs: matches.is_present("no_remove_llvm_funcs"),

      // Slicer options
      slice_depth: matches
        .value_of_t::<u8>("slice_depth")
        .map_err(|_| String::from("Cannot parse depth"))?,
      target_inclusion_filter: matches.value_of("target_inclusion_filter").map(String::from),
      target_exclusion_filter: matches.value_of("target_exclusion_filter").map(String::from),
      entry_filter: matches.value_of("entry_filter").map(String::from),
      reduce_slice: matches.is_present("reduce_slice"),
      use_batch: matches.is_present("use_batch"),
      batch_size: matches
        .value_of_t::<usize>("batch_size")
        .map_err(|_| String::from("Cannot parse batch size"))?,
      use_regex_filter: matches.is_present("use_regex_filter"),

      //
      max_trace_per_slice: matches.value_of_t::<usize>("max_trace_per_slice").unwrap(),
      max_explored_trace_per_slice: matches.value_of_t::<usize>("max_explored_trace_per_slice").unwrap(),
      max_node_per_trace: matches.value_of_t::<usize>("max_node_per_trace").unwrap(),
      no_trace_reduction: matches.is_present("no_reduce_trace"),
      print_trace: matches.is_present("print_trace"),
    })
  }

  pub fn input_path(&self) -> PathBuf {
    PathBuf::from(self.input.as_str())
  }

  pub fn output_path(&self) -> PathBuf {
    PathBuf::from(self.output.as_str())
  }
}