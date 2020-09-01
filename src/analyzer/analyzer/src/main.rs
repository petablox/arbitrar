use clap::App;

use analyzer_core::*;
use call_graph::*;
use feature_extraction::*;
use options::*;
use slicer::*;
use symbolic_execution::*;
use utils::*;

fn arg_parser<'a>() -> App<'a> {
  let app = App::new("analyzer");
  Options::setup_parser(app)
}

fn main() -> Result<(), String> {
  let options = Options::from_matches(&arg_parser().get_matches())?;
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

  // Generate slices
  logging_ctx.log_generated_call_edges(target_edges_map.num_elements())?;
  let target_slices_map = TargetSlicesMap::from_target_edges_map(&target_edges_map, &call_graph, &options);
  let target_num_slices_map = target_slices_map.keyed_num_elements();

  // Dump slices
  logging_ctx.log_generated_slices(target_slices_map.num_elements())?;
  target_slices_map.dump(&options);

  // Divide target slices into batches
  logging_ctx.log_dividing_batches(options.use_batch)?;
  let mut global_metadata = MetaData::new();
  for (i, target_slices_map) in target_slices_map.batches(options.use_batch, options.batch_size) {
    // Generate slices from the edges
    logging_ctx.log_executing_batch(i, options.use_batch, target_slices_map.num_elements())?;
    let sym_exec_ctx = SymbolicExecutionContext::new(&llmod, &call_graph, &options)?;
    let metadata = sym_exec_ctx.execute_target_slices_map(target_slices_map);
    global_metadata = global_metadata.combine(metadata.clone());
    logging_ctx.log_finished_execution_batch(i, options.use_batch, metadata)?;
  }
  logging_ctx.log_finished_execution(options.use_batch, global_metadata)?;

  // Extract features
  logging_ctx.log_extracting_features()?;
  let feat_ext_ctx = FeatureExtractionContext::new(&llmod, target_num_slices_map, &options)?;
  feat_ext_ctx.extract_features();
  logging_ctx.log_finished_extracting_features()?;

  Ok(())
}
