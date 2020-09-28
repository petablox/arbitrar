use std::path::PathBuf;

pub trait GeneralOptions {
  fn use_serial(&self) -> bool;

  fn seed(&self) -> u64;
}

pub trait IOOptions {
  fn input_path(&self) -> PathBuf;

  fn output_path(&self) -> PathBuf;

  fn default_package(&self) -> Option<&str>;

  fn with_package(&self, path: PathBuf) -> PathBuf {
    match self.default_package() {
      Some(package) => path.join(package),
      None => path,
    }
  }

  fn slice_dir(&self) -> PathBuf {
    self.output_path().join("slices")
  }

  fn slice_target_dir(&self, target: &str) -> PathBuf {
    self.with_package(self.slice_dir().join(target))
  }

  fn slice_target_file_path(&self, target: &str, slice_id: usize) -> PathBuf {
    self.slice_target_dir(target).join(format!("{}.json", slice_id))
  }

  fn slice_target_package_dir(&self, target: &str, package: &str) -> PathBuf {
    self.slice_dir().join(target).join(package)
  }

  fn slice_target_package_file_path(&self, target: &str, package: &str, slice_id: usize) -> PathBuf {
    self
      .slice_target_package_dir(target, package)
      .join(format!("{}.json", slice_id))
  }

  fn trace_dir(&self) -> PathBuf {
    self.output_path().join("traces")
  }

  fn trace_target_dir(&self, target: &str) -> PathBuf {
    self.with_package(self.trace_dir().join(target))
  }

  fn trace_target_slice_dir(&self, target: &str, slice_id: usize) -> PathBuf {
    self.trace_target_dir(target).join(slice_id.to_string())
  }

  fn trace_target_slice_file_path(&self, target: &str, slice_id: usize, trace_id: usize) -> PathBuf {
    self
      .trace_target_slice_dir(target, slice_id)
      .join(format!("{}.json", trace_id))
  }

  fn trace_target_package_slice_dir(&self, target: &str, package: &str, slice_id: usize) -> PathBuf {
    self.trace_dir().join(target).join(package).join(slice_id.to_string())
  }

  fn trace_target_package_slice_file_path(
    &self,
    target: &str,
    package: &str,
    slice_id: usize,
    trace_id: usize,
  ) -> PathBuf {
    self
      .trace_target_package_slice_dir(target, package, slice_id)
      .join(format!("{}.json", trace_id))
  }

  fn feature_dir(&self) -> PathBuf {
    self.output_path().join("features")
  }

  fn feature_target_dir(&self, target: &str) -> PathBuf {
    self.with_package(self.feature_dir().join(target))
  }

  fn feature_target_slice_dir(&self, target: &str, slice_id: usize) -> PathBuf {
    self.feature_target_dir(target).join(slice_id.to_string())
  }

  fn feature_target_slice_file_path(&self, target: &str, slice_id: usize, trace_id: usize) -> PathBuf {
    self
      .feature_target_slice_dir(target, slice_id)
      .join(format!("{}.json", trace_id))
  }

  fn feature_target_package_slice_dir(&self, target: &str, package: &str, slice_id: usize) -> PathBuf {
    self.feature_dir().join(target).join(package).join(slice_id.to_string())
  }

  fn feature_target_package_slice_file_path(
    &self,
    target: &str,
    package: &str,
    slice_id: usize,
    trace_id: usize,
  ) -> PathBuf {
    self
      .feature_target_package_slice_dir(target, package, slice_id)
      .join(format!("{}.json", trace_id))
  }
}
