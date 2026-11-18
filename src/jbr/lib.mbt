// Port of jxl-jbr/src/lib.rs: JPEG bitstream reconstruction data (`jbrd`
// box) parsing.

///|
let header_icc : Bytes = b"ICC_PROFILE\x00"

///|
let header_exif : Bytes = b"Exif\x00\x00"

///|
let header_xmp : Bytes = b"http://ns.adobe.com/xap/1.0/\x00"

///|
/// JPEG bitstream reconstruction data.
pub struct JpegBitstreamData {
  header : JpegBitstreamHeader
  priv data_stream : @brotli.DecompressorWriter
}

///|
/// Decodes the JPEG bitstream reconstruction data from the buffer.
///
/// Returns `Some(_)` if header is decoded successfully, and `None` if the
/// input is insufficient.
///
/// Raises if the header is invalid, or data section could not be
/// decompressed.
pub fn JpegBitstreamData::try_parse(
  data : Bytes,
) -> JpegBitstreamData? raise @bitstream.JxlError {
  let bitstream = @bitstream.Bitstream::new(data)
  let header = JpegBitstreamHeader::parse(bitstream) catch {
    e => if e.unexpected_eof() { return None } else { raise e }
  }
  bitstream.zero_pad_to_byte()
  let bytes_read = bitstream.num_read_bits() / 8
  let compressed_data = data[bytes_read:].to_owned()
  let data_stream = @brotli.DecompressorWriter::new()
  data_stream.write_all(compressed_data)
  Some({ header, data_stream, })
}

///|
/// Feeds more bytes to be decompressed.
pub fn JpegBitstreamData::feed_bytes(
  self : JpegBitstreamData,
  data : Bytes,
) -> Unit {
  self.data_stream.write_all(data)
}

///|
/// Finalizes the stream and checks for potential errors.
pub fn JpegBitstreamData::finalize(
  self : JpegBitstreamData,
) -> Unit raise @bitstream.JxlError {
  self.data_stream.flush()
  let decompressed_len = self.data_stream.get_ref().length()
  if decompressed_len != self.header.expected_data_len() {
    // Data section length of jbrd box doesn't match expected length
    raise err_invalid_data()
  }
}

///|
pub fn JpegBitstreamData::header(
  self : JpegBitstreamData,
) -> JpegBitstreamHeader {
  self.header
}

///|
/// The decompressed data section (valid after `finalize`).
pub fn JpegBitstreamData::data(self : JpegBitstreamData) -> Bytes {
  self.data_stream.get_ref()
}

///|
pub(all) struct JpegBitstreamHeader {
  is_gray : Bool
  markers : Array[Int32]
  app_markers : Array[AppMarker]
  com_lengths : Array[Int32]
  quant_tables : Array[QuantTable]
  components : Array[Component]
  huffman_codes : Array[HuffmanCode]
  scan_info : Array[ScanInfo]
  restart_interval : Int32
  scan_more_info : Array[ScanMoreInfo]
  intermarker_lengths : Array[Int32]
  tail_data_length : Int32
  padding_bits : Padding?
}

///|
pub fn JpegBitstreamHeader::parse(
  bitstream : @bitstream.Bitstream,
) -> JpegBitstreamHeader raise @bitstream.JxlError {
  let is_gray = bitstream.read_bool()
  let markers : Array[Int32] = []
  let mut num_app_markers = 0
  let mut num_com_markers = 0
  let mut num_scans = 0
  let mut num_intermarkers = 0
  let mut has_dri = false
  while markers.last() != Some(0xd9) {
    let marker_bits = bitstream.read_bits_int(6) + 0xc0
    match marker_bits {
      0xe0..<=0xef => num_app_markers += 1
      0xfe => num_com_markers += 1
      0xda => num_scans += 1
      0xff => num_intermarkers += 1
      0xdd => has_dri = true
      _ => ()
    }
    markers.push(marker_bits)
  }
  let app_markers = []
  for _ in 0..<num_app_markers {
    app_markers.push(AppMarker::parse(bitstream))
  }
  let com_lengths = []
  for _ in 0..<num_com_markers {
    com_lengths.push(bitstream.read_bits_int(16) + 1)
  }
  let num_quant_tables = bitstream.read_bits_int(2) + 1
  let quant_tables = []
  for _ in 0..<num_quant_tables {
    quant_tables.push(QuantTable::parse(bitstream))
  }
  let comp_type = bitstream.read_bits_int(2)
  let component_ids : Array[Int32] = match comp_type {
    0 => [1]
    1 => [1, 2, 3]
    2 => ['R'.to_int(), 'G'.to_int(), 'B'.to_int()]
    _ => {
      let num_comp = bitstream.read_bits_int(2) + 1
      let ids = []
      for _ in 0..<num_comp {
        ids.push(bitstream.read_bits_int(8))
      }
      ids
    }
  }
  let components = []
  for id in component_ids {
    let q_idx = bitstream.read_bits_int(2)
    components.push({ id, q_idx, })
  }
  let num_huff = bitstream
    .read_u32(
      @bitstream.c(4),
      @bitstream.cu(2, 3),
      @bitstream.cu(10, 4),
      @bitstream.cu(26, 6),
    )
    .reinterpret_as_int()
  let huffman_codes = []
  for _ in 0..<num_huff {
    huffman_codes.push(HuffmanCode::parse(bitstream))
  }
  let scan_info = []
  for _ in 0..<num_scans {
    scan_info.push(ScanInfo::parse(bitstream))
  }
  let restart_interval = if has_dri { bitstream.read_bits_int(16) } else { 0 }
  let scan_more_info = []
  for _ in 0..<num_scans {
    scan_more_info.push(ScanMoreInfo::parse(bitstream))
  }
  let intermarker_lengths = []
  for _ in 0..<num_intermarkers {
    intermarker_lengths.push(bitstream.read_bits_int(16))
  }
  let tail_data_length = bitstream
    .read_u32(
      @bitstream.c(0),
      @bitstream.cu(1, 8),
      @bitstream.cu(257, 16),
      @bitstream.cu(65793, 22),
    )
    .reinterpret_as_int()
  let has_padding = bitstream.read_bool()
  let padding_bits = if has_padding {
    Some(Padding::parse(bitstream))
  } else {
    None
  }
  {
    is_gray,
    markers,
    app_markers,
    com_lengths,
    quant_tables,
    components,
    huffman_codes,
    scan_info,
    restart_interval,
    scan_more_info,
    intermarker_lengths,
    tail_data_length,
    padding_bits,
  }
}

///|
fn JpegBitstreamHeader::app_data_len(self : JpegBitstreamHeader) -> Int32 {
  let mut sum = 0
  for marker in self.app_markers {
    if marker.ty == 0 {
      sum += marker.length
    }
  }
  sum
}

///|
fn JpegBitstreamHeader::com_data_len(self : JpegBitstreamHeader) -> Int32 {
  let mut sum = 0
  for x in self.com_lengths {
    sum += x
  }
  sum
}

///|
fn JpegBitstreamHeader::intermarker_data_len(
  self : JpegBitstreamHeader,
) -> Int32 {
  let mut sum = 0
  for x in self.intermarker_lengths {
    sum += x
  }
  sum
}

///|
pub fn JpegBitstreamHeader::expected_data_len(
  self : JpegBitstreamHeader,
) -> Int32 {
  self.app_data_len() +
  self.com_data_len() +
  self.intermarker_data_len() +
  self.tail_data_length
}

///|
pub fn JpegBitstreamHeader::expected_icc_len(
  self : JpegBitstreamHeader,
) -> Int32 {
  let mut sum = 0
  for am in self.app_markers {
    if am.ty == 1 {
      sum += am.length - 5 - header_icc.length()
    }
  }
  sum
}

///|
pub fn JpegBitstreamHeader::expected_exif_len(
  self : JpegBitstreamHeader,
) -> Int32 {
  for am in self.app_markers {
    if am.ty == 2 {
      return am.length - 3 - header_exif.length()
    }
  }
  0
}

///|
pub fn JpegBitstreamHeader::expected_xmp_len(
  self : JpegBitstreamHeader,
) -> Int32 {
  for am in self.app_markers {
    if am.ty == 3 {
      return am.length - 3 - header_xmp.length()
    }
  }
  0
}

///|
pub(all) struct AppMarker {
  ty : Int32
  length : Int32
}

///|
pub fn AppMarker::parse(
  bitstream : @bitstream.Bitstream,
) -> AppMarker raise @bitstream.JxlError {
  let ty = bitstream
    .read_u32(
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.cu(2, 1),
      @bitstream.cu(4, 2),
    )
    .reinterpret_as_int()
  let length = bitstream.read_bits_int(16) + 1
  { ty, length, }
}

///|
pub(all) struct QuantTable {
  precision : Int32
  index : Int32
  is_last : Bool
}

///|
pub fn QuantTable::parse(
  bitstream : @bitstream.Bitstream,
) -> QuantTable raise @bitstream.JxlError {
  let precision = bitstream.read_bits_int(1)
  let index = bitstream.read_bits_int(2)
  let is_last = bitstream.read_bool()
  { precision, index, is_last, }
}

///|
pub(all) struct Component {
  id : Int32
  q_idx : Int32
}

///|
pub(all) struct ScanInfo {
  ss : Int32
  se : Int32
  al : Int32
  ah : Int32
  component_info : Array[ScanComponentInfo]
  last_needed_pass : Int32
}

///|
pub fn ScanInfo::parse(
  bitstream : @bitstream.Bitstream,
) -> ScanInfo raise @bitstream.JxlError {
  let num_comps = bitstream.read_bits_int(2) + 1
  let ss = bitstream.read_bits_int(6)
  let se = bitstream.read_bits_int(6)
  let al = bitstream.read_bits_int(4)
  let ah = bitstream.read_bits_int(4)
  let component_info = []
  for _ in 0..<num_comps {
    component_info.push(ScanComponentInfo::parse(bitstream))
  }
  let last_needed_pass = bitstream
    .read_u32(
      @bitstream.c(0),
      @bitstream.c(1),
      @bitstream.c(2),
      @bitstream.cu(3, 3),
    )
    .reinterpret_as_int() &
    0xff
  { ss, se, al, ah, component_info, last_needed_pass, }
}

///|
pub fn ScanInfo::num_comps(self : ScanInfo) -> Int32 {
  self.component_info.length()
}

///|
pub(all) struct ScanComponentInfo {
  comp_idx : Int32
  ac_tbl_idx : Int32
  dc_tbl_idx : Int32
}

///|
pub fn ScanComponentInfo::parse(
  bitstream : @bitstream.Bitstream,
) -> ScanComponentInfo raise @bitstream.JxlError {
  let comp_idx = bitstream.read_bits_int(2)
  let ac_tbl_idx = bitstream.read_bits_int(2)
  let dc_tbl_idx = bitstream.read_bits_int(2)
  { comp_idx, ac_tbl_idx, dc_tbl_idx, }
}

///|
pub(all) struct ScanMoreInfo {
  reset_points : @hashset.HashSet[Int32]
  extra_zero_runs : @hashmap.HashMap[Int32, Int32]
}

///|
fn saturating_add_u32(a : Int32, b : Int32) -> Int32 {
  let s = a.to_int64() + b.to_int64()
  if s > 0xFFFFFFFFL {
    // Saturated values are rejected by the callers' range check anyway.
    0x7FFFFFFF
  } else if s > 0x7FFFFFFFL {
    0x7FFFFFFF
  } else {
    s.to_int()
  }
}

///|
pub fn ScanMoreInfo::parse(
  bitstream : @bitstream.Bitstream,
) -> ScanMoreInfo raise @bitstream.JxlError {
  let num_reset_points = bitstream
    .read_u32(
      @bitstream.c(0),
      @bitstream.cu(1, 2),
      @bitstream.cu(4, 4),
      @bitstream.cu(20, 16),
    )
    .reinterpret_as_int()
  let mut last_block_idx : Int32? = None
  let reset_points = @hashset.HashSet([])
  for _ in 0..<num_reset_points {
    let diff = bitstream
      .read_u32(
        @bitstream.c(0),
        @bitstream.cu(1, 3),
        @bitstream.cu(9, 5),
        @bitstream.cu(41, 28),
      )
      .reinterpret_as_int()
    let block_idx = match last_block_idx {
      Some(last) => saturating_add_u32(last, diff + 1)
      None => diff
    }
    if block_idx > 3 << 26 {
      raise @bitstream.JxlError::ValidationFailed("reset_points too large")
    }
    last_block_idx = Some(block_idx)
    reset_points.add(block_idx)
  }
  let num_extra_zero_runs = bitstream
    .read_u32(
      @bitstream.c(0),
      @bitstream.cu(1, 2),
      @bitstream.cu(4, 4),
      @bitstream.cu(20, 16),
    )
    .reinterpret_as_int()
  last_block_idx = None
  let extra_zero_runs = @hashmap.HashMap([])
  for _ in 0..<num_extra_zero_runs {
    let { num_runs, run_length, } = ExtraZeroRun::parse(bitstream)
    let block_idx = match last_block_idx {
      Some(last) => saturating_add_u32(last, run_length + 1)
      None => run_length
    }
    if block_idx > 3 << 26 {
      raise @bitstream.JxlError::ValidationFailed(
        "extra_zero_runs.block_idx too large",
      )
    }
    last_block_idx = Some(block_idx)
    extra_zero_runs.set(block_idx, num_runs)
  }
  { reset_points, extra_zero_runs, }
}

///|
pub(all) struct ExtraZeroRun {
  num_runs : Int32
  run_length : Int32
}

///|
pub fn ExtraZeroRun::parse(
  bitstream : @bitstream.Bitstream,
) -> ExtraZeroRun raise @bitstream.JxlError {
  let num_runs = bitstream
    .read_u32(
      @bitstream.c(1),
      @bitstream.cu(2, 2),
      @bitstream.cu(5, 4),
      @bitstream.cu(20, 8),
    )
    .reinterpret_as_int()
  let run_length = bitstream
    .read_u32(
      @bitstream.c(0),
      @bitstream.cu(1, 3),
      @bitstream.cu(9, 5),
      @bitstream.cu(41, 28),
    )
    .reinterpret_as_int()
  { num_runs, run_length, }
}

///|
pub(all) struct Padding {
  bits : Array[Byte]
}

///|
pub fn Padding::parse(
  bitstream : @bitstream.Bitstream,
) -> Padding raise @bitstream.JxlError {
  let num_bits = bitstream.read_bits_int(24)
  let full_bytes = num_bits / 8
  let extra_bits = num_bits % 8
  let bits = []
  for _ in 0..<full_bytes {
    bits.push(bitstream.read_bits_int(8).to_byte())
  }
  bits.push(bitstream.read_bits_int(extra_bits).to_byte())
  { bits, }
}
