use std::collections::HashMap;
use std::path::PathBuf;
use structopt::StructOpt;

use analyzer::{call_graph::*, feature_extraction::*, options::*, slicer::*, symbolic_execution::*, utils::*};

#[derive(StructOpt, Debug, Clone)]
#[structopt(name = "analyzer")]
pub struct Options {
  #[structopt(index = 1, required = true, value_name = "INPUT")]
  pub input: String,

  #[structopt(index = 2, required = true, value_name = "OUTPUT")]
  pub output: String,

  #[structopt(long, takes_value = true, value_name = "SUBFOLDER")]
  pub subfolder: Option<String>,

  /// Serialize execution rather than parallel
  #[structopt(short = "s", long)]
  pub use_serial: bool,

  #[structopt(long)]
  pub print_options: bool,

  /// Random seed
  #[structopt(long, takes_value = true, default_value = "12345", value_name = "SEED")]
  pub seed: u64,

  /// Do not remove llvm functions
  #[structopt(long)]
  pub no_remove_llvm_funcs: bool,

  /// Maximum number of blocks per slice
  #[structopt(long, takes_value = true, default_value = "300", value_name = "MAX_AVG_NUM_BLOCKS")]
  pub max_avg_num_blocks: usize,

  /// Print call graph
  #[structopt(long)]
  pub print_call_graph: bool,

  #[structopt(
    short = "d",
    long,
    takes_value = true,
    default_value = "1",
    value_name = "SLICE_DEPTH"
  )]
  pub slice_depth: usize,

  /// Execute only slice
  #[structopt(long, takes_value = true, value_name = "EXECUTE_ONLY_SLICE_ID")]
  pub execute_only_slice_id: Option<usize>,

  #[structopt(long, takes_value = true, value_name = "EXECUTE_ONLY_SLICE_NAME")]
  pub execute_only_slice_function_name: Option<String>,

  #[structopt(long, takes_value = true, value_name = "INCLUDE_TARGET")]
  pub target_inclusion_filter: Option<String>,

  #[structopt(long, takes_value = true, value_name = "EXCLUDE_TARGET")]
  pub target_exclusion_filter: Option<String>,

  /// Entry location filters. In the form of Regex if the option `use_regex_filter` is supplied
  #[structopt(long, takes_value = true, value_name = "ENTRY_LOCATION")]
  pub entry_filter: Option<String>,

  /// Use regex in the filters
  #[structopt(long)]
  pub use_regex_filter: bool,

  /// Don't do slice reduction
  #[structopt(long)]
  pub no_reduce_slice: bool,

  /// Use batch execution. Especially useful when applying to large dataset
  #[structopt(long)]
  pub use_batch: bool,

  /// The number of slices inside each batch
  #[structopt(long, takes_value = true, default_value = "50", value_name = "BATCH_SIZE")]
  pub batch_size: usize,

  /// Print slice
  #[structopt(long)]
  pub print_slice: bool,

  /// Dump target-num-slices-map file
  #[structopt(long, takes_value = true, value_name = "TARGET_NUM_SLICES_MAP")]
  pub target_num_slices_map_file: Option<String>,

  #[structopt(long, takes_value = true, default_value = "50", value_name = "MAX_WORK")]
  pub max_work: usize,

  /// The maximum number of generated trace per slice
  #[structopt(long, takes_value = true, default_value = "50", value_name = "MAX_TRACE_PER_SLICE")]
  pub max_trace_per_slice: usize,

  #[structopt(
    long,
    takes_value = true,
    default_value = "1000",
    value_name = "MAX_EXPLORED_TRACE_PER_SLICE"
  )]
  pub max_explored_trace_per_slice: usize,

  #[structopt(long, takes_value = true, default_value = "5000", value_name = "MAX_NODE_PER_TRACE")]
  pub max_node_per_trace: usize,

  #[structopt(long)]
  pub no_trace_reduction: bool,

  #[structopt(long)]
  pub no_random_work: bool,

  #[structopt(long)]
  pub print_block_trace: bool,

  #[structopt(long)]
  pub print_trace: bool,

  #[structopt(long)]
  pub no_prefilter_block_trace: bool,

  #[structopt(long)]
  pub no_feature: bool,

  #[structopt(long)]
  pub feature_only: bool,

  #[structopt(
    long,
    takes_value = true,
    default_value = "10",
    value_name = "CAUSALITY_DICTIONARY_SIZE"
  )]
  pub causality_dictionary_size: usize,
}

impl GeneralOptions for Options {
  fn use_serial(&self) -> bool {
    self.use_serial
  }

  fn seed(&self) -> u64 {
    self.seed
  }
}

impl IOOptions for Options {
  fn input_path(&self) -> PathBuf {
    PathBuf::from(&self.input)
  }

  fn output_path(&self) -> PathBuf {
    PathBuf::from(&self.output)
  }

  fn default_package(&self) -> Option<&str> {
    match &self.subfolder {
      Some(subfolder) => Some(&subfolder),
      None => None,
    }
  }
}

impl Options {
  fn target_num_slices_map_path(&self) -> Option<PathBuf> {
    if let Some(filename) = &self.target_num_slices_map_file {
      Some(self.output_path().join(filename))
    } else {
      None
    }
  }

  fn num_slices(&self, target: &str) -> usize {
    match std::fs::read_dir(self.slice_target_dir(target)) {
      Ok(dirs) => dirs.count(),
      _ => 0,
    }
  }
}

impl CallGraphOptions for Options {
  fn remove_llvm_funcs(&self) -> bool {
    !self.no_remove_llvm_funcs
  }
}

impl SlicerOptions for Options {
  fn no_reduce_slice(&self) -> bool {
    self.no_reduce_slice
  }

  fn slice_depth(&self) -> usize {
    self.slice_depth as usize
  }

  fn entry_filter(&self) -> &Option<String> {
    &self.entry_filter
  }

  fn target_inclusion_filter(&self) -> &Option<String> {
    &self.target_inclusion_filter
  }

  fn target_exclusion_filter(&self) -> &Option<String> {
    &self.target_exclusion_filter
  }

  fn use_regex_filter(&self) -> bool {
    self.use_regex_filter
  }

  fn max_avg_num_blocks(&self) -> usize {
    self.max_avg_num_blocks
  }
}

impl SymbolicExecutionOptions for Options {
  fn slice_depth(&self) -> usize {
    self.slice_depth
  }

  fn max_work(&self) -> usize {
    self.max_work
  }

  fn no_random_work(&self) -> bool {
    self.no_random_work
  }

  fn max_node_per_trace(&self) -> usize {
    self.max_node_per_trace
  }

  fn max_explored_trace_per_slice(&self) -> usize {
    self.max_explored_trace_per_slice
  }

  fn max_trace_per_slice(&self) -> usize {
    self.max_trace_per_slice
  }

  fn no_trace_reduction(&self) -> bool {
    self.no_trace_reduction
  }

  fn no_prefilter_block_trace(&self) -> bool {
    self.no_prefilter_block_trace
  }

  fn print_block_trace(&self) -> bool {
    self.print_block_trace
  }

  fn print_trace(&self) -> bool {
    self.print_trace
  }
}

impl FeatureExtractorOptions for Options {
  fn causality_dictionary_size(&self) -> usize {
    self.causality_dictionary_size
  }
}

fn main() -> Result<(), String> {
  let options = Options::from_args();
  if options.print_options {
    println!("{:?}", options);
  }

  // Load a logging context
  let mut logging_ctx = LoggingContext::new(&options)?;

  // Load the byte code module and generate analyzer context
  logging_ctx.log_loading_bc()?;
  let llctx = llir::Context::create();
  let llmod = llctx
    .load_module(&options.input_path())
    .map_err(|err| err.to_string())?;

  // Generate call graph
  logging_ctx.log_generating_call_graph()?;
  let call_graph = CallGraph::from_module(&llmod, &options);
  if options.print_call_graph {
    call_graph.print();
  }

  // Finding call edges
  logging_ctx.log_finding_call_edges()?;
  let target_edges_map = TargetEdgesMap::from_call_graph(&call_graph, &options)?;

  // Check if we need to "redo" the symbolic execution
  let target_num_slices_map = if !options.feature_only {
    // Generate slices
    logging_ctx.log_generated_call_edges(target_edges_map.num_elements())?;
    let target_slices_map = TargetSlicesMap::from_target_edges_map(&target_edges_map, &call_graph, &options);
    let target_num_slices_map = target_slices_map.keyed_num_elements();

    // Dump slices
    logging_ctx.log_generated_slices(target_slices_map.num_elements())?;
    target_slices_map.dump(&options);

    if let Some(slice_id) = &options.execute_only_slice_id {
      let func_name = if let Some(func_name) = &options.execute_only_slice_function_name {
        func_name
      } else {
        return Err(format!("Must provide function name"));
      };

      // Only execute slice
      logging_ctx.log(&format!(
        "Executing the only slice for function {} and slice id {}",
        func_name, slice_id
      ))?;

      return if let Some(slices) = target_slices_map.get(func_name) {
        if let Some(slice) = slices.get(*slice_id) {
          // Do symbolic execution on that single slice
          let sym_exec_ctx = SymbolicExecutionContext::new(&llmod, &call_graph, &options);
          let metadata = sym_exec_ctx.execute_slice(slice.clone(), *slice_id);

          // Print the result
          logging_ctx.log(&format!(
            "Result executing slice {} {} {:?}",
            func_name, slice_id, metadata
          ))?;

          Ok(())
        } else {
          Err(format!(
            "Cannot find slice for function {} with slice id {}",
            func_name, slice_id
          ))
        }
      } else {
        Err(format!("Cannot find slice for function {}", func_name))
      };
    } else {
      // Divide target slices into batches
      logging_ctx.log_dividing_batches(options.use_batch)?;
      let mut global_metadata = MetaData::new();
      for (i, target_slices_map) in target_slices_map.batches(options.use_batch, options.batch_size) {
        // Generate slices from the edges
        logging_ctx.log_executing_batch(i, options.use_batch, target_slices_map.num_elements())?;
        let sym_exec_ctx = SymbolicExecutionContext::new(&llmod, &call_graph, &options);
        let metadata = sym_exec_ctx.execute_target_slices_map(target_slices_map);
        global_metadata = global_metadata.combine(metadata.clone());
        logging_ctx.log_finished_execution_batch(i, options.use_batch, metadata)?;
      }
      logging_ctx.log_finished_execution(options.use_batch, global_metadata)?;

      if let Some(filename) = options.target_num_slices_map_path() {
        target_num_slices_map.dump(filename)?;
      }

      target_num_slices_map
    }
  } else {
    // If not, we directly load slices information from file
    load_target_num_slices_map(target_edges_map, &options)
  };

  if !options.no_feature {
    // Extract features
    logging_ctx.log_extracting_features()?;
    let feat_ext_ctx = FeatureExtractionContext::new(&llmod, target_num_slices_map, &options)?;
    feat_ext_ctx.extract_features(&mut logging_ctx);
    logging_ctx.log_finished_extracting_features()?;
  }

  Ok(())
}

fn load_target_num_slices_map(target_edges_map: TargetEdgesMap, options: &Options) -> HashMap<String, usize> {
  target_edges_map
    .into_iter()
    .map(|(target, _)| {
      let num_slices = options.num_slices(&target);
      (target, num_slices)
    })
    .collect()
}
