// Port of jxl-oxide/src/aux_box.rs: auxiliary boxes (Exif, XMP, JPEG
// reconstruction data) of a JPEG XL container.

///|
priv enum DataKind {
  Init
  NoData
  Raw(Buffer)
  Brotli(@brotli.DecompressorWriter)
}

///|
pub struct AuxBoxReader {
  priv mut data : DataKind
  priv mut done : Bool
}

///|
fn AuxBoxReader::new() -> AuxBoxReader {
  { data: Init, done: false, }
}

///|
fn AuxBoxReader::ensure_raw(self : AuxBoxReader) -> Unit {
  if self.done {
    return
  }
  match self.data {
    Init => self.data = Raw(Buffer())
    NoData | Brotli(_) => abort("AuxBoxReader::ensure_raw")
    Raw(_) => ()
  }
}

///|
fn AuxBoxReader::ensure_brotli(self : AuxBoxReader) -> Unit {
  if self.done {
    return
  }
  match self.data {
    Init => self.data = Brotli(@brotli.DecompressorWriter::new())
    NoData | Raw(_) => abort("AuxBoxReader::ensure_brotli")
    Brotli(_) => ()
  }
}

///|
pub fn AuxBoxReader::feed_data(
  self : AuxBoxReader,
  data : BytesView,
) -> Unit raise @bitstream.JxlError {
  if self.done {
    raise @bitstream.Io("InvalidData: cannot feed into finalized box")
  }
  match self.data {
    Init => {
      let buf = Buffer()
      buf.write_bytesview(data)
      self.data = Raw(buf)
    }
    NoData => abort("unreachable")
    Raw(buf) => buf.write_bytesview(data)
    Brotli(writer) => writer.write_all(data.to_owned())
  }
}

///|
pub fn AuxBoxReader::finalize(
  self : AuxBoxReader,
) -> Unit raise @bitstream.JxlError {
  if self.done {
    return
  }
  match self.data {
    Init | NoData => self.data = NoData
    Raw(_) => ()
    Brotli(writer) => {
      writer.flush()
      writer.close()
      // `into_inner`: upstream keeps what was decompressed so far (with a
      // warning) when the decompressor is in an error state, which `close`
      // has already reported.
      let buf = Buffer()
      buf.write_bytes(writer.get_ref())
      self.data = Raw(buf)
    }
  }
  self.done = true
}

///|
pub fn AuxBoxReader::is_done(self : AuxBoxReader) -> Bool {
  self.done
}

///|
pub fn AuxBoxReader::data(self : AuxBoxReader) -> AuxBoxData[Bytes] {
  if !self.is_done() {
    return Decoding
  }
  match self.data {
    Init | Brotli(_) => Decoding
    NoData => NotFound
    Raw(buf) => Data(buf.to_bytes())
  }
}

///|
/// Auxiliary box data.
pub(all) enum AuxBoxData[T] {
  /// The box has data.
  Data(T)
  /// The box has not been decoded yet.
  Decoding
  /// The box was not found.
  NotFound
}

///|
pub fn[T] AuxBoxData::has_data(self : AuxBoxData[T]) -> Bool {
  self is Data(_)
}

///|
pub fn[T] AuxBoxData::is_decoding(self : AuxBoxData[T]) -> Bool {
  self is Decoding
}

///|
pub fn[T] AuxBoxData::is_not_found(self : AuxBoxData[T]) -> Bool {
  self is NotFound
}

///|
pub fn[T] AuxBoxData::unwrap(self : AuxBoxData[T]) -> T {
  guard self is Data(x) else {
    abort("cannot unwrap `AuxBoxData` which doesn't have any data")
  }
  x
}

///|
pub fn[T] AuxBoxData::unwrap_or(self : AuxBoxData[T], or : T) -> T {
  match self {
    Data(x) => x
    _ => or
  }
}

///|
pub fn[T, U] AuxBoxData::map(
  self : AuxBoxData[T],
  f : (T) -> U raise?,
) -> AuxBoxData[U] raise? {
  match self {
    Data(x) => Data(f(x))
    Decoding => Decoding
    NotFound => NotFound
  }
}

///|
/// Auxiliary box list of a JPEG XL container, which may contain Exif and/or
/// XMP metadata.
pub struct AuxBoxList {
  priv boxes : Array[(@container.ContainerBoxType, AuxBoxReader)]
  priv jbrd : Jbrd
  priv mut current_box_ty : @container.ContainerBoxType?
  priv mut current_box : AuxBoxReader
  priv mut last_box : Bool
}

///|
fn AuxBoxList::new() -> AuxBoxList {
  {
    boxes: [],
    jbrd: Jbrd::new(),
    current_box_ty: None,
    current_box: AuxBoxReader::new(),
    last_box: false,
  }
}

///|
fn AuxBoxList::handle_event(
  self : AuxBoxList,
  event : @container.ParseEvent,
) -> Unit raise @bitstream.JxlError {
  let jbrd_ty = @container.ContainerBoxType::jpeg_reconstruction()
  match event {
    BitstreamKind(_) => ()
    Codestream(_) => ()
    NoMoreAuxBox => {
      self.current_box_ty = None
      self.last_box = true
    }
    AuxBoxStart(ty~, brotli_compressed~, last_box~) => {
      self.current_box_ty = Some(ty)
      if ty != jbrd_ty {
        if brotli_compressed {
          self.current_box.ensure_brotli()
        } else {
          self.current_box.ensure_raw()
        }
      }
      self.last_box = last_box
    }
    AuxBoxData(ty, buf) => {
      self.current_box_ty = Some(ty)
      if ty == jbrd_ty {
        self.jbrd.feed_bytes(buf)
      } else {
        self.current_box.feed_data(buf)
      }
    }
    AuxBoxEnd(ty) => {
      self.current_box_ty = Some(ty)
      self.finalize()
    }
  }
}

///|
fn AuxBoxList::finalize(self : AuxBoxList) -> Unit raise @bitstream.JxlError {
  match self.current_box_ty {
    Some(ty) if ty == @container.ContainerBoxType::jpeg_reconstruction() =>
      self.jbrd.finalize()
    Some(ty) => {
      self.current_box.finalize()
      let finished_box = self.current_box
      self.current_box = AuxBoxReader::new()
      self.boxes.push((ty, finished_box))
    }
    None => return
  }
  self.current_box_ty = None
}

///|
fn AuxBoxList::eof(self : AuxBoxList) -> Unit raise @bitstream.JxlError {
  self.finalize()
  self.last_box = true
}

///|
fn AuxBoxList::jbrd(self : AuxBoxList) -> AuxBoxData[@jbr.JpegBitstreamData] {
  if self.jbrd.data() is Some(data) {
    Data(data)
  } else if self.last_box &&
    self.current_box_ty !=
    Some(@container.ContainerBoxType::jpeg_reconstruction()) {
    NotFound
  } else {
    Decoding
  }
}

///|
fn AuxBoxList::first_of_type(
  self : AuxBoxList,
  ty : @container.ContainerBoxType,
) -> AuxBoxData[Bytes] {
  for entry in self.boxes {
    if entry.0 == ty {
      return entry.1.data()
    }
  }
  if self.last_box && self.current_box_ty != Some(ty) {
    NotFound
  } else {
    Decoding
  }
}

///|
/// Returns the first Exif metadata, if any.
pub fn AuxBoxList::first_exif(
  self : AuxBoxList,
) -> AuxBoxData[RawExif] raise @bitstream.JxlError {
  self.first_of_type(@container.ContainerBoxType::exif()).map(RawExif::new)
}

///|
/// Returns the first XML metadata, if any.
pub fn AuxBoxList::first_xml(self : AuxBoxList) -> AuxBoxData[Bytes] {
  self.first_of_type(@container.ContainerBoxType::xml())
}

///|
/// `AuxBoxData::as_ref` (values are shared references here).
pub fn[T] AuxBoxData::as_ref(self : AuxBoxData[T]) -> AuxBoxData[T] {
  self
}

///|
/// `AuxBoxData<Result<T, E>>::transpose`.
pub fn[T, E] AuxBoxData::transpose(
  self : AuxBoxData[Result[T, E]],
) -> Result[AuxBoxData[T], E] {
  match self {
    Data(Ok(x)) => Ok(Data(x))
    Data(Err(e)) => Err(e)
    Decoding => Ok(Decoding)
    NotFound => Ok(NotFound)
  }
}
