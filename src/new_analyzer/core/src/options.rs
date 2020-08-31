use clap::{App, Arg, ArgMatches};
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Options {
  // General Options
  pub input: String,
  pub output: String,
  pub subfolder: Option<String>,
  pub use_serial: bool,

  // Call Graph Options
  pub no_remove_llvm_funcs: bool,
  pub print_call_graph: bool,

  // Slicer Options
  pub slice_depth: u8,
  pub target_inclusion_filter: Option<String>,
  pub target_exclusion_filter: Option<String>,
  pub entry_filter: Option<String>,
  pub use_regex_filter: bool,
  pub no_reduce_slice: bool,
  pub use_batch: bool,
  pub batch_size: usize,
  pub print_slice: bool,

  // Symbolic Execution Options
  pub max_work: usize,
  pub max_trace_per_slice: usize,
  pub max_explored_trace_per_slice: usize,
  pub max_node_per_trace: usize,
  pub no_trace_reduction: bool,
  pub no_random_work: bool,
  pub print_block_trace: bool,
  pub print_trace: bool,
  pub no_prefilter_block_trace: bool,

  // Feature Extraction Options
  pub causality_dictionary_size: usize,
}

impl Default for Options {
  fn default() -> Self {
    Self {
      // General options
      input: "".to_string(),
      output: "".to_string(),
      subfolder: None,
      use_serial: false,

      // Call graph options
      no_remove_llvm_funcs: false,
      print_call_graph: false,

      // Slicer options
      slice_depth: 1,
      target_inclusion_filter: None,
      target_exclusion_filter: None,
      entry_filter: None,
      use_regex_filter: false,
      no_reduce_slice: false,
      print_slice: false,

      // Batching options
      use_batch: false,
      batch_size: 0,

      // Symbolic execution options
      max_work: 50,
      max_trace_per_slice: 50,
      max_explored_trace_per_slice: 1000,
      max_node_per_trace: 5000,
      no_trace_reduction: false,
      no_random_work: false,
      print_block_trace: false,
      print_trace: false,
      no_prefilter_block_trace: false,

      // Feature extraction options
      causality_dictionary_size: 10,
    }
  }
}

impl Options {
  pub fn setup_parser<'a>(app: App<'a>) -> App<'a> {
    app.args(&[
      // General options
      Arg::new("input").value_name("INPUT").index(1).required(true),
      Arg::new("output").value_name("OUTPUT").index(2).required(true),
      Arg::new("subfolder")
        .value_name("SUBFOLDER")
        .long("subfolder")
        .takes_value(true),
      Arg::new("serial")
        .short('s')
        .long("serial")
        .about("Serialize execution rather than parallel"),
      // Call graph options
      Arg::new("no_remove_llvm_funcs")
        .long("--no-remove-llvm-funcs")
        .about("Do not remove llvm functions"),
      Arg::new("print_call_graph")
        .long("--print-call-graph")
        .about("Print call graph"),
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
      Arg::new("no_reduce_slice")
        .long("no-reduce-slice")
        .about("No reduce slice using relevancy test"),
      Arg::new("use_batch").long("use-batch").about("Use batched execution"),
      Arg::new("batch_size")
        .value_name("BATCH_SIZE")
        .takes_value(true)
        .default_value("100")
        .long("batch-size"),
      Arg::new("print_slice").long("print-slice").about("Print slice"),
      // Symbolic Execution Options
      Arg::new("max_work")
        .long("max-work")
        .value_name("MAX_WORK")
        .takes_value(true)
        .default_value("50")
        .about("Max number of work in work list"),
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
      Arg::new("no_random_work")
        .long("no-random-work")
        .about("Don't use randomized work popping when executing traces"),
      Arg::new("no_reduce_trace")
        .long("no-reduce-trace")
        .about("No trace reduction"),
      Arg::new("print_block_trace")
        .long("print-block-trace")
        .about("Print out block trace"),
      Arg::new("print_trace").long("print-trace").about("Print out trace"),
      Arg::new("no_prefilter_block_trace")
        .long("no-prefilter-block-trace")
        .about("No prefilter of block trace"),
      Arg::new("causality_dictionary_size")
        .long("causality-dictionary-size")
        .takes_value(true)
        .value_name("CAUSALITY_DICTIONARY_SIZE")
        .default_value("10"),
    ])
  }

  pub fn from_matches(matches: &ArgMatches) -> Result<Self, String> {
    Ok(Self {
      // General options
      input: String::from(matches.value_of("input").unwrap()),
      output: String::from(matches.value_of("output").unwrap()),
      subfolder: if matches.is_present("subfolder") {
        Some(String::from(matches.value_of("subfolder").unwrap()))
      } else {
        None
      },
      use_serial: matches.is_present("serial"),

      // Call graph options
      no_remove_llvm_funcs: matches.is_present("no_remove_llvm_funcs"),
      print_call_graph: matches.is_present("print_call_graph"),

      // Slicer options
      slice_depth: matches
        .value_of_t::<u8>("slice_depth")
        .map_err(|_| String::from("Cannot parse depth"))?,
      target_inclusion_filter: matches.value_of("target_inclusion_filter").map(String::from),
      target_exclusion_filter: matches.value_of("target_exclusion_filter").map(String::from),
      entry_filter: matches.value_of("entry_filter").map(String::from),
      no_reduce_slice: matches.is_present("no_reduce_slice"),
      use_batch: matches.is_present("use_batch"),
      batch_size: matches
        .value_of_t::<usize>("batch_size")
        .map_err(|_| String::from("Cannot parse batch size"))?,
      use_regex_filter: matches.is_present("use_regex_filter"),
      print_slice: matches.is_present("print_slice"),

      // Symbolic execution options
      max_work: matches.value_of_t::<usize>("max_work").unwrap(),
      max_trace_per_slice: matches.value_of_t::<usize>("max_trace_per_slice").unwrap(),
      max_explored_trace_per_slice: matches.value_of_t::<usize>("max_explored_trace_per_slice").unwrap(),
      max_node_per_trace: matches.value_of_t::<usize>("max_node_per_trace").unwrap(),
      no_random_work: matches.is_present("no_random_work"),
      no_trace_reduction: matches.is_present("no_reduce_trace"),
      print_block_trace: matches.is_present("print_block_trace"),
      print_trace: matches.is_present("print_trace"),
      no_prefilter_block_trace: matches.is_present("no_prefilter_block_trace"),

      // Feature extraction options
      causality_dictionary_size: matches.value_of_t::<usize>("causality_dictionary_size").unwrap(),
    })
  }

  /// Generate input path
  pub fn input_path(&self) -> PathBuf {
    PathBuf::from(self.input.as_str())
  }

  /// Generate output path
  pub fn output_path(&self) -> PathBuf {
    PathBuf::from(self.output.as_str())
  }

  pub fn with_subfolder(&self, path: PathBuf) -> PathBuf {
    match &self.subfolder {
      Some(s) => path.join(s.as_str()),
      None => path,
    }
  }

  pub fn slice_dir_path(&self) -> PathBuf {
    self.output_path().join("slices")
  }

  pub fn slice_target_dir_path(&self, target: &str) -> PathBuf {
    self.with_subfolder(self.slice_dir_path().join(target))
  }

  pub fn slice_file_path(&self, target: &str, slice_id: usize) -> PathBuf {
    self
      .slice_target_dir_path(target)
      .join(format!("{}.json", slice_id).to_string())
  }

  pub fn trace_dir_path(&self) -> PathBuf {
    self.output_path().join("traces")
  }

  pub fn trace_target_slice_dir_path(&self, target: &str, slice_id: usize) -> PathBuf {
    self
      .with_subfolder(self.trace_dir_path().join(target))
      .join(slice_id.to_string())
  }

  pub fn trace_file_path(&self, target: &str, slice_id: usize, trace_id: usize) -> PathBuf {
    self
      .trace_target_slice_dir_path(target, slice_id)
      .join(format!("{}.json", trace_id).as_str())
  }

  pub fn features_dir_path(&self) -> PathBuf {
    self.output_path().join("features")
  }

  pub fn features_target_slice_dir_path(&self, target: &str, slice_id: usize) -> PathBuf {
    self
      .with_subfolder(self.features_dir_path().join(target))
      .join(slice_id.to_string())
  }

  pub fn features_file_path(&self, target: &str, slice_id: usize, trace_id: usize) -> PathBuf {
    self
      .features_target_slice_dir_path(target, slice_id)
      .join(format!("{}.json", trace_id).as_str())
  }
}
