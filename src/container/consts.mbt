///|
/// JPEG XL bare codestream signature, `ff 0a`.
pub let codestream_sig : Bytes = b"\xff\x0a"

///|
/// JPEG XL container format signature, `00 00 00 0c 4a 58 4a 20 0d 0a 87 0a`.
pub let container_sig : Bytes = b"\x00\x00\x00\x0cJXL \x0d\x0a\x87\x0a"
