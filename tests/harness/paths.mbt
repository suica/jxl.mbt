// Port of jxl-oxide-tests/src/lib.rs: locating test data.
//
// `CARGO_MANIFEST_DIR` (the root of the jxl-oxide-tests crate) is the root of
// this module, `tests/` in the repository: `moon test` runs test executables
// with the current directory set to it on both `native` and `wasm-gc`
// (moonrun), so `manifest_dir()` is ".". The layout mirrors the crate:
//
//   tests/conformance/        the libjxl conformance repository (git submodule
//                             upstream; created by scripts/fetch_fixtures.sh)
//   tests/decode/             jxl-oxide-testdata (submodule upstream; ditto)
//   tests/tests/<test>/       the ported integration tests (`tests/<test>/mod.rs`)
//   tests/tests/cache/        downloaded objects (`JXL_OXIDE_CACHE`)
//
// The `net` feature is off: MoonBit tests have no HTTP client, so a fixture
// missing from the cache fails the test with upstream's message;
// scripts/fetch_fixtures.sh downloads the same URLs to the same file names.

///|
/// `env!("CARGO_MANIFEST_DIR")`.
pub fn manifest_dir() -> String {
  "."
}

///|
/// `std::env::var(name)`: `Some` when set (to valid Unicode).
fn env_var(name : String) -> String? {
  @env.get_env_var(name)
}

///|
pub fn debug_enabled() -> Bool {
  env_var("JXL_OXIDE_DEBUG") is Some(_)
}

///|
pub fn conformance_testcases_dir() -> String {
  match env_var("JXL_OXIDE_CONFORMANCE_TESTCASES") {
    Some(testcases_dir) if testcases_dir != "" => testcases_dir
    _ => manifest_dir() + "/conformance/testcases"
  }
}

///|
pub fn conformance_path(name : String) -> String {
  conformance_testcases_dir() + "/" + name + "/input.jxl"
}

///|
pub fn decode_testcases_dir() -> String {
  match env_var("JXL_OXIDE_DECODE_TESTCASES") {
    Some(testcases_dir) if testcases_dir != "" => testcases_dir
    _ => manifest_dir() + "/decode"
  }
}

///|
pub fn cache_dir() -> String {
  match env_var("JXL_OXIDE_CACHE") {
    Some(cache_dir) if cache_dir != "" => cache_dir
    _ => manifest_dir() + "/tests/cache"
  }
}

///|
pub fn download_object_with_cache(hash : String, ext : String) -> Bytes raise {
  let url = "https://storage.googleapis.com/storage/v1/b/jxl-conformance/o/objects%2F\{hash}?alt=media"
  let name = "\{hash}.\{ext}"
  download_url_with_cache(url, name)
}

///|
/// Reads `name` from the cache. Without the `net` feature (always, here) a
/// missing file panics with upstream's message; scripts/fetch_fixtures.sh
/// fills the cache.
pub fn download_url_with_cache(url : String, name : String) -> Bytes raise {
  let cache_dir = cache_dir()
  let path = cache_file_path(cache_dir, name)
  if @fs.path_exists(path) {
    if read_file_opt(path) is Some(buf) {
      return buf
    }
  }
  fail(
    "Fixture \{name} (\{url}) not found in \{cache_dir}, but network is disabled",
  )
}

///|
pub fn cache_file_path(cache_dir : String, name : String) -> String {
  cache_dir + "/" + name
}

///|
fn read_file_opt(path : String) -> Bytes? {
  Some(@fs.read_file_to_bytes(path)) catch {
    _ => None
  }
}

// Helpers used by the tests (`std::fs::read` and friends).

///|
/// The conformance testcase directory of `name`.
pub fn conformance_case_dir(name : String) -> String {
  conformance_testcases_dir() + "/" + name
}

///|
pub fn file_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
/// `std::fs::read(path).expect(..)`: fails when the file cannot be read.
pub fn read_file(path : String) -> Bytes raise Failure {
  @fs.read_file_to_bytes(path) catch {
    IOError(msg) => fail("Failed to read file \{path}: \{msg}")
  }
}

///|
pub fn read_text(path : String) -> String raise Failure {
  @fs.read_file_to_string(path) catch {
    IOError(msg) => fail("Failed to read file \{path}: \{msg}")
  }
}

///|
/// Reads a fixture file; fails naming scripts/fetch_fixtures.sh when it is
/// missing.
pub fn read_fixture(path : String) -> Bytes raise Failure {
  if !@fs.path_exists(path) {
    fail("fixture missing: \{path} (run scripts/fetch_fixtures.sh)")
  }
  read_file(path)
}

///|
/// Returns `dir` if `dir/probe` exists; fails naming
/// scripts/fetch_fixtures.sh otherwise.
pub fn fixture_dir(dir : String, probe : String) -> String raise Failure {
  if !@fs.path_exists(dir + "/" + probe) {
    fail("fixture missing: \{dir}/\{probe} (run scripts/fetch_fixtures.sh)")
  }
  dir
}

///|
/// Writes a file (crop failure artifacts).
pub fn write_file(path : String, data : Bytes) -> Unit raise Failure {
  @fs.write_bytes_to_file(path, data) catch {
    IOError(msg) => fail("Failed to write \{path}: \{msg}")
  }
}

///|
/// `std::fs::create_dir_all`.
pub fn create_dir_all(path : String) -> Unit raise Failure {
  let parts = path.split("/").collect()
  let mut cur = ""
  for i, p in parts {
    cur = if i == 0 { p.to_owned() } else { cur + "/" + p.to_owned() }
    if cur != "" && cur != "." && !@fs.path_exists(cur) {
      @fs.create_dir(cur) catch {
        IOError(msg) => fail("Failed to create \{cur}: \{msg}")
      }
    }
  }
}
