use serde_json::Value;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;

pub fn dump_json(json: &Value, path: PathBuf) -> Result<(), String> {
  let json_str = serde_json::to_string(json).map_err(|_| "Cannot turn trace into json".to_string())?;
  let mut file = File::create(path).map_err(|_| "Cannot create trace file".to_string())?;
  file
    .write_all(json_str.as_bytes())
    .map_err(|_| "Cannot write to trace file".to_string())
}