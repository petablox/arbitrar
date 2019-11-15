const fs = require("fs");
const path = require("path");

const DATA_PATH = "../../data/libssl_crypto_zalloc_n_5/dugraphs/";

fs.readdir(DATA_PATH, (err, files) => {
  if (err) {
    console.log(err);
  } else {
    let numTraces = 0, numStmt = 0;
    let traceLengths = [];
    files.filter(fname => fname.indexOf(".json") >= 0).forEach((file) => {
      const data = require(path.join(DATA_PATH, file));
      for (const i in data) {
        const trace = data[i];
        const traceLen = trace.vertex.length;
        numTraces += 1;
        numStmt += traceLen;
        traceLengths.push(traceLen);
      }
    });

    console.log(`Average length of trace: ${numStmt / numTraces}`);
    fs.writeFileSync("trace_lengths.json", JSON.stringify(traceLengths));
  }
});