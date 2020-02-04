const path_to_dir = process.cwd() + "/" + process.argv[2];
const path_to_slices_json = path_to_dir + "/slices.json";
const slices = require(path_to_slices_json);
const id = parseInt(process.argv[3]);
console.log(slices[id]);