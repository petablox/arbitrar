const path_to_dir = process.cwd() + "/" + process.argv[2];
const path_to_slices_json = path_to_dir + "/slices.json";
const dugraphs_dir = path_to_dir + "/dugraphs/";
const slices = require(path_to_slices_json);
const label = process.argv[3];

let count = 0;

for (var i = 0; i < slices.length; i++) {
  const slice = slices[i];
  const callee = slice.call_edge.callee;
  const slice_file_name = `${callee}-${i}.json`;
  const slice_file = dugraphs_dir + slice_file_name;
  const traces = require(slice_file);
  for (const trace of traces) {
    if (trace["labels"]) {
      const labels = trace.labels;
      if (labels.indexOf(label) >= 0) {
        count += 1;
        process.stdout.write(`Slice Id ${i}, Count ${count}\r`);
      }
    }
  }
  delete require.cache[slice_file];
}

console.log(`\nLabel ${label} appeared ${count} times`);