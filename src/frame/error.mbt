///|
/// jxl-frame `Error` variants map onto `@bitstream.JxlError`:
/// - `InvalidTocPermutation` → `Frame("InvalidTocPermutation")`
/// - `IncompleteFrameData { field }` → `IncompleteFrameData(field)`
/// - `OutOfMemory` → `OutOfMemory(0)`
/// - `HadError` → `Frame("HadError")`
/// Errors from other crates are already `JxlError`.
/// `Error::unexpected_eof` is `@bitstream.JxlError::unexpected_eof`.
let had_error : @bitstream.JxlError = Frame("HadError")
