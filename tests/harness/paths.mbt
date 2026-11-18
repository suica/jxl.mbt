// Locating test data.
//
// Port of jxl-oxide-tests/src/lib.rs. `moon test` runs test executables with
// the current directory set to the root of the `suica/jxl_tests` module
// (`tests/` in the repository) on both `native` and `wasm-gc` (moonrun), so
// the defaults below are relative to that directory. Each location can be
// overridden by an environment variable (absolute path recommended).

///|
/// Root of downloaded/decompressed fixtures (`fixtures/cache` at the repo root).
/// Override: `JXL_FIXTURES_CACHE`.
pub fn cache_dir() -> String {
  env_or("JXL_FIXTURES_CACHE", "../fixtures/cache")
}

///|
/// libjxl conformance `testcases` directory.
/// Override: `JXL_OXIDE_CONFORMANCE_TESTCASES` (same name as upstream).
pub fn conformance_testcases_dir() -> String {
  env_or("JXL_OXIDE_CONFORMANCE_TESTCASES", cache_dir() + "/conformance")
}

///|
pub fn conformance_case_dir(name : String) -> String {
  conformance_testcases_dir() + "/" + name
}

///|
pub fn conformance_path(name : String) -> String {
  conformance_case_dir(name) + "/input.jxl"
}

///|
/// jxl-oxide decode test data (`<name>/input.jxl`, `<name>/output.buf`).
/// Override: `JXL_OXIDE_DECODE_TESTCASES` (same name as upstream).
pub fn decode_testcases_dir() -> String {
  env_or("JXL_OXIDE_DECODE_TESTCASES", cache_dir() + "/decode")
}

///|
/// Data committed in the tests module (fuzz findings, cmyk_layers.jxl, ...),
/// relative to the module root. Override: `JXL_TESTS_DATA`.
pub fn data_dir() -> String {
  env_or("JXL_TESTS_DATA", "data")
}

///|
pub fn debug_enabled() -> Bool {
  @env.get_env_var("JXL_OXIDE_DEBUG") is Some(_)
}

///|
/// When set, a missing fixture fails the test instead of skipping it.
pub fn require_fixtures() -> Bool {
  match @env.get_env_var("JXL_TESTS_REQUIRE_FIXTURES") {
    Some(v) => v != "" && v != "0"
    None => false
  }
}

///|
fn env_or(name : String, default : String) -> String {
  match @env.get_env_var(name) {
    Some(v) if v != "" => v
    _ => default
  }
}

///|
pub fn file_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
pub fn read_file(path : String) -> Bytes raise Failure {
  @fs.read_file_to_bytes(path) catch {
    IOError(msg) => fail("cannot read \{path}: \{msg}")
  }
}

///|
pub fn read_text(path : String) -> String raise Failure {
  @fs.read_file_to_string(path) catch {
    IOError(msg) => fail("cannot read \{path}: \{msg}")
  }
}

///|
/// Reads a fixture file. Returns `None` (after printing a SKIP line) if it is
/// missing, unless `JXL_TESTS_REQUIRE_FIXTURES` is set, then fails.
pub fn read_fixture(path : String) -> Bytes? raise Failure {
  if !@fs.path_exists(path) {
    if require_fixtures() {
      fail("fixture missing: \{path} (run scripts/fetch_fixtures.sh)")
    }
    println("SKIP: fixture missing: \{path} (run scripts/fetch_fixtures.sh)")
    return None
  }
  Some(read_file(path))
}
