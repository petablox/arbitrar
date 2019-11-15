const fs = require("fs");
const path = require("path");

const DATA_PATH = "../../data/libssl_crypto_zalloc_n_5/dugraphs/";

fs.readdir(DATA_PATH, (err, files) => {
  if (err) {
    console.log(err);
  } else {
    let numTraces = 0, numTracesWithIcmpAfterZalloc = 0;
    let succTraceIds = [], failTraceIds = [];
    files.filter(fname => fname.indexOf(".json") >= 0).forEach((file) => {
      const data = require(path.join(DATA_PATH, file));
      for (const i in data) {
        const trace = data[i];
        const traceId = { file, index: i };
        let hasZalloc = false, hasIcmpAfterZalloc = false;
        for (const stmt of trace.vertex.reverse()) {
          const instr = stmt["Instr"];
          if (!hasZalloc && instr.indexOf("CRYPTO_zalloc") >= 0) {
            hasZalloc = true;
          }
          if (hasZalloc && instr.indexOf("icmp") >= 0) {
            hasIcmpAfterZalloc = true;
            break;
          }
        }
        numTraces += 1;
        if (hasIcmpAfterZalloc) {
          succTraceIds.push(traceId);
          numTracesWithIcmpAfterZalloc += 1;
        } else {
          failTraceIds.push(traceId);
        }
      }
    });

    console.log(`Total number of traces: ${numTraces}`);
    console.log(`The number of traces with "Icmp" after "zalloc": ${numTracesWithIcmpAfterZalloc}`);

    fs.writeFileSync("./traces_with_icmp_after_zalloc.json", JSON.stringify(succTraceIds));
    fs.writeFileSync("./traces_without.json", JSON.stringify(failTraceIds));
  }
});