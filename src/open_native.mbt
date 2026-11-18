// `JxlImageBuilder::open` and `JxlImage::open_with_defaults` (native only).
//
// Not provided on wasm-gc: reading files there needs host functions
// (moonbitlang/x/fs imports `__moonbit_fs_unstable`) that a browser does not
// have, so a library importing them cannot be instantiated in a browser.
// Read the file yourself and use `read(Cursor::new(bytes))` there.

///|
#external
priv type FileHandle

///|
#borrow(path)
extern "C" fn fopen_ffi(path : Bytes) -> FileHandle = "suica_jxl_fopen"

///|
extern "C" fn is_null_ffi(ptr : FileHandle) -> Int32 = "suica_jxl_is_null"

///|
#borrow(buf)
extern "C" fn fread_ffi(
  buf : FixedArray[Byte],
  start : Int32,
  len : Int32,
  file : FileHandle,
) -> Int32 = "suica_jxl_fread"

///|
extern "C" fn fclose_ffi(file : FileHandle) -> Int32 = "suica_jxl_fclose"

///|
extern "C" fn last_error_ffi() -> Bytes = "suica_jxl_last_error"

///|
fn last_error() -> String {
  @utf8.decode_lossy(last_error_ffi())
}

///|
/// `std::fs::File` opened for reading.
pub struct File {
  priv handle : FileHandle
  priv mut closed : Bool
}

///|
/// `File::open`.
pub fn File::open(path : String) -> File raise @bitstream.JxlError {
  let encoded = @utf8.encode(path)
  let cpath = Bytes::makei(encoded.length() + 1, fn(i) {
    if i < encoded.length() {
      encoded[i]
    } else {
      b'\x00'
    }
  })
  let handle = fopen_ffi(cpath)
  if is_null_ffi(handle) != 0 {
    raise @bitstream.Io("\{last_error()}: \{path}")
  }
  { handle, closed: false, }
}

///|
/// Closes the file (Rust closes it on drop).
pub fn File::close(self : File) -> Unit {
  if !self.closed {
    self.closed = true
    fclose_ffi(self.handle) |> ignore
  }
}

///|
pub impl Read for File with fn read(self, buf, start, end) {
  if self.closed || end <= start {
    return 0
  }
  let n = fread_ffi(buf, start, end - start, self.handle)
  if n < 0 {
    raise @bitstream.Io(last_error())
  }
  n
}

///|
/// Consumes the builder, and creates a JPEG XL image decoder by reading image
/// from the file.
pub fn JxlImageBuilder::open(
  self : JxlImageBuilder,
  path : String,
) -> JxlImage raise @bitstream.JxlError {
  let file = File::open(path)
  defer file.close()
  self.read(file)
}

///|
/// Opens an image in the filesystem with default options.
pub fn JxlImage::open_with_defaults(
  path : String,
) -> JxlImage raise @bitstream.JxlError {
  JxlImage::builder().open(path)
}
