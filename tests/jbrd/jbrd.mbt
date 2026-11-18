// Port of jxl-oxide-tests/tests/jbrd/mod.rs: JPEG bitstream reconstruction,
// checked by the SHA-256 of the reconstructed JPEG file.

///|
pub fn run_jbrd(path : String, hash : String) -> Unit raise Error {
  guard @harness.read_fixture(path) is Some(data) else { return }
  let input = @jxl.JxlImage::builder().read(data)
  let jpeg = input.reconstruct_jpeg()
  assert_eq(@harness.sha256_hex(jpeg[:]), hash)
}

///|
pub fn conformance(name : String) -> String {
  @harness.conformance_path(name)
}

///|
pub fn decode_case(name : String) -> String {
  @harness.decode_testcases_dir() + "/" + name + "/input.jxl"
}
