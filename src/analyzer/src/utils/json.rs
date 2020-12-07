use serde::de;
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

pub fn load_json(path: &PathBuf) -> Result<serde_json::Value, String> {
  let file = File::open(PathBuf::from(path)).map_err(|_| "Cannot open file".to_string())?;
  serde_json::from_reader(file).map_err(|x| format!("Cannot parse file: {:?}", x))
}

pub fn load_json_t<T: de::DeserializeOwned>(path: &PathBuf) -> Result<T, String> {
  load_json(path).and_then(|json| serde_json::from_value(json).map_err(|x| format!("Cannot parse json into T: {:?}", x)))
}
