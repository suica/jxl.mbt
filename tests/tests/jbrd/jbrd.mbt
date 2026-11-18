// Port of jxl-oxide-tests/tests/jbrd/mod.rs: JPEG bitstream reconstruction,
// checked by the SHA-256 of the reconstructed JPEG file (`ring::digest`).

///|
/// The body of a `test!` test.
pub fn run_jbrd(input_jxl : String, hash : String) -> Unit raise Error {
  // `JxlImage::builder().open(input_jxl)` through a reader (open is
  // native-only)
  let input = @jxl.JxlImage::builder().read(
    @jxl.Cursor::new(@harness.read_file(input_jxl)),
  )
  let jpeg = Buffer()
  input.reconstruct_jpeg(jpeg)
  let digest = @harness.sha256(jpeg.to_bytes()[:])
  let expected = @harness.from_hex(hash)
  assert_eq(digest, expected)
}
