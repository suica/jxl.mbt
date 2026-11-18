///|
/// Iterator that reads over a buffer and emits parser events.
pub struct ParseEvents {
  priv inner : ContainerParser
  priv mut remaining_input : BytesView
  priv mut finished : Bool
}

///|
fn ParseEvents::new(parser : ContainerParser, input : BytesView) -> ParseEvents {
  parser.previous_consumed_bytes = 0
  { inner: parser, remaining_input: input, finished: false, }
}

///|
fn starts_with(buf : BytesView, prefix : BytesView) -> Bool {
  if buf.length() < prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if buf[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
fn ParseEvents::emit_single(
  self : ParseEvents,
) -> ParseEvent? raise @bitstream.JxlError {
  let inner = self.inner
  while true {
    let buf = self.remaining_input
    if buf.length() == 0 {
      self.finished = true
      return None
    }
    match inner.state {
      WaitingSignature =>
        if starts_with(buf, codestream_sig) {
          inner.state = InCodestream(
            kind=BareCodestream,
            bytes_left=None,
            pending_no_more_aux_box=true,
          )
          return Some(BitstreamKind(BareCodestream))
        } else if starts_with(buf, container_sig) {
          inner.state = WaitingBoxHeader
          self.remaining_input = buf[container_sig.length():]
          return Some(BitstreamKind(Container))
        } else if !starts_with(codestream_sig, buf) &&
          !starts_with(container_sig, buf) {
          inner.state = InCodestream(
            kind=Invalid,
            bytes_left=None,
            pending_no_more_aux_box=true,
          )
          return Some(BitstreamKind(Invalid))
        } else {
          return None
        }
      WaitingBoxHeader =>
        match ContainerBoxHeader::parse(buf) {
          Done(header~, header_size~) => {
            self.remaining_input = buf[header_size:]
            let tbox = header.box_type()
            if tbox == ContainerBoxType::codestream() {
              match inner.jxlp_index_state {
                Initial => inner.jxlp_index_state = SingleJxlc
                SingleJxlc => raise InvalidBox
                Jxlp(_) | JxlpFinished => raise InvalidBox
              }
              let bytes_left = header
                .box_size()
                .map(fn(x) { x.reinterpret_as_int64() })
              inner.state = InCodestream(
                kind=Container,
                bytes_left~,
                pending_no_more_aux_box=bytes_left is None,
              )
            } else if tbox == ContainerBoxType::partial_codestream() {
              if header.box_size() is Some(box_size) && box_size < 4UL {
                raise InvalidBox
              }
              match inner.jxlp_index_state {
                Initial => inner.jxlp_index_state = Jxlp(0)
                Jxlp(index) => inner.jxlp_index_state = Jxlp(index + 1)
                SingleJxlc => raise InvalidBox
                JxlpFinished => raise InvalidBox
              }
              inner.state = WaitingJxlpIndex(header)
            } else {
              let bytes_left = header
                .box_size()
                .map(fn(x) { x.reinterpret_as_int64() })
              let ty = header.box_type()
              let brotli_compressed = ty ==
                ContainerBoxType::brotli_compressed()
              if brotli_compressed {
                if bytes_left is Some(n) && n >= 0L && n <= 3L {
                  raise InvalidBox
                }
              }
              inner.state = InAuxBox(header~, brotli_box_type=None, bytes_left~)
              if !brotli_compressed {
                return Some(
                  AuxBoxStart(
                    ty~,
                    brotli_compressed=false,
                    last_box=bytes_left is None,
                  ),
                )
              }
            }
          }
          NeedMoreData => return None
        }
      WaitingJxlpIndex(header) => {
        if buf.length() < 4 {
          return None
        }
        let index = be_u32(buf, 0)
        self.remaining_input = buf[4:]
        let is_last = (index & 0x80000000U) != 0U
        let index = index & 0x7fffffffU
        match inner.jxlp_index_state {
          Jxlp(expected_index) if expected_index == index =>
            if is_last {
              inner.jxlp_index_state = JxlpFinished
            }
          Jxlp(_) => raise InvalidBox
          _ => abort("invalid jxlp index state in WaitingJxlpIndex")
        }
        let bytes_left = header
          .box_size()
          .map(fn(x) { x.reinterpret_as_int64() - 4L })
        inner.state = InCodestream(
          kind=Container,
          bytes_left~,
          pending_no_more_aux_box=bytes_left is None,
        )
      }
      // JXL codestream box is the last box; emit "no more aux box" event.
      InCodestream(kind~, bytes_left~, pending_no_more_aux_box=true) => {
        inner.state = InCodestream(
          kind~,
          bytes_left~,
          pending_no_more_aux_box=false,
        )
        return Some(NoMoreAuxBox)
      }
      InCodestream(bytes_left=None, ..) => {
        self.remaining_input = buf[buf.length():]
        return Some(Codestream(buf))
      }
      InCodestream(kind~, bytes_left=Some(bytes_left), ..) => {
        let len = buf.length().to_int64()
        if len >= bytes_left {
          let n = bytes_left.to_int()
          inner.state = WaitingBoxHeader
          self.remaining_input = buf[n:]
          return Some(Codestream(buf[:n]))
        } else {
          inner.state = InCodestream(
            kind~,
            bytes_left=Some(bytes_left - len),
            pending_no_more_aux_box=false,
          )
          self.remaining_input = buf[buf.length():]
          return Some(Codestream(buf))
        }
      }
      // Read brob payload box type.
      InAuxBox(header~, brotli_box_type=None, bytes_left~) if header.ty ==
        ContainerBoxType::brotli_compressed() => {
        if buf.length() < 4 {
          return None
        }
        let ty = buf[0:4].to_owned()
        self.remaining_input = buf[4:]
        let bytes_left = bytes_left.map(fn(x) { x - 4L })
        let is_reserved_box_type = (
            ty[0] == b'j' && ty[1] == b'x' && ty[2] == b'l'
          ) ||
          ty == b"brob" ||
          ty == b"jbrd"
        if is_reserved_box_type {
          raise ValidationFailed(
            "brob box, jxl boxes and jbrd box cannot be Brotli-compressed",
          )
        }
        let ty = ContainerBoxType(ty)
        inner.state = InAuxBox(header~, brotli_box_type=Some(ty), bytes_left~)
        return Some(
          AuxBoxStart(ty~, brotli_compressed=true, last_box=bytes_left is None),
        )
      }
      InAuxBox(header~, brotli_box_type~, bytes_left~) => {
        let ty = match brotli_box_type {
          Some(ty) => ty
          None => header.ty
        }
        let payload = match bytes_left {
          Some(0L) => {
            inner.state = WaitingBoxHeader
            return Some(AuxBoxEnd(ty))
          }
          Some(left) => {
            let num_bytes_to_read = if left < buf.length().to_int64() {
              left.to_int()
            } else {
              buf.length()
            }
            inner.state = InAuxBox(
              header~,
              brotli_box_type~,
              bytes_left=Some(left - num_bytes_to_read.to_int64()),
            )
            self.remaining_input = buf[num_bytes_to_read:]
            buf[:num_bytes_to_read]
          }
          None => {
            self.remaining_input = buf[buf.length():]
            buf
          }
        }
        return Some(AuxBoxData(ty, payload))
      }
    }
  }
  None
}

///|
/// Returns the next parser event, or `None` when the parser needs more input
/// (or the input is exhausted).
pub fn ParseEvents::next(
  self : ParseEvents,
) -> ParseEvent? raise @bitstream.JxlError {
  if self.finished {
    return None
  }
  let initial_len = self.remaining_input.length()
  defer {
    self.inner.previous_consumed_bytes += initial_len -
      self.remaining_input.length()
  }
  errdefer {
    self.finished = true
  }
  let event = self.emit_single()
  event
}

///|
/// Parser event emitted by `ParseEvents`.
pub(all) enum ParseEvent {
  /// Bitstream structure is detected.
  BitstreamKind(BitstreamKind)
  /// Codestream data is read.
  ///
  /// Returned data may be partial. Complete codestream can be obtained by concatenating all data
  /// of `Codestream` events.
  Codestream(BytesView)
  /// No more auxiliary box will come after this event.
  NoMoreAuxBox
  /// New auxiliary box starts.
  AuxBoxStart(
    ty~ : ContainerBoxType,
    brotli_compressed~ : Bool,
    last_box~ : Bool,
  )
  /// Auxiliary box data is read.
  ///
  /// Returned data may be partial. Complete box payload can be obtained by concatenating all
  /// data between corresponding `AuxBoxStart` and `AuxBoxEnd` events.
  AuxBoxData(ContainerBoxType, BytesView)
  /// Current auxiliary box has ended.
  AuxBoxEnd(ContainerBoxType)
}

///|
pub impl Show for ParseEvent with fn output(self, logger) {
  match self {
    BitstreamKind(kind) => logger.write_string("BitstreamKind(\{kind})")
    Codestream(buf) =>
      logger.write_string("Codestream(\{buf.length()} byte(s))")
    NoMoreAuxBox => logger.write_string("NoMoreAuxBox")
    AuxBoxStart(ty~, brotli_compressed~, last_box~) =>
      logger.write_string(
        "AuxBoxStart { ty: \{ty}, brotli_compressed: \{brotli_compressed}, last_box: \{last_box} }",
      )
    AuxBoxData(ty, buf) =>
      logger.write_string("AuxBoxData(\{ty}, \{buf.length()} byte(s))")
    AuxBoxEnd(ty) => logger.write_string("AuxBoxEnd(\{ty})")
  }
}
