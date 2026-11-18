///|
/// jxl-render `Error` variants map onto `@bitstream.JxlError::Render(name)`:
/// `IncompleteFrame`, `FailedReference`, `UninitializedLfFrame(n)`,
/// `InvalidReference(n)` and `NotReady`. Errors from other crates keep their
/// own `JxlError` variants.

///|
pub fn incomplete_frame() -> @bitstream.JxlError {
  @bitstream.Render("IncompleteFrame")
}

///|
pub fn failed_reference() -> @bitstream.JxlError {
  @bitstream.Render("FailedReference")
}

///|
pub fn uninitialized_lf_frame(lf_level : Int) -> @bitstream.JxlError {
  @bitstream.Render("UninitializedLfFrame(\{lf_level})")
}

///|
pub fn invalid_reference(idx : Int) -> @bitstream.JxlError {
  @bitstream.Render("InvalidReference(\{idx})")
}

///|
pub fn not_ready() -> @bitstream.JxlError {
  @bitstream.Render("NotReady")
}

///|
/// Whether `e` is jxl-render's `Error::IncompleteFrame`.
pub fn is_incomplete_frame(e : @bitstream.JxlError) -> Bool {
  e is @bitstream.Render("IncompleteFrame")
}
