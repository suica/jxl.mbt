///|
fn collect(
  parser : @container.ContainerParser,
  input : Bytes,
) -> (Array[String], Bytes) raise @bitstream.JxlError {
  let events = parser.feed_bytes(input)
  let log = []
  let cs = Buffer()
  while events.next() is Some(ev) {
    log.push("\{ev}")
    if ev is Codestream(b) {
      cs.write_bytesview(b)
    }
  }
  (log, cs.to_bytes())
}

///|
fn box_(ty : Bytes, payload : Bytes) -> Bytes {
  let buf = Buffer()
  let size = payload.length() + 8
  buf.write_byte((size >> 24).to_byte())
  buf.write_byte((size >> 16).to_byte())
  buf.write_byte((size >> 8).to_byte())
  buf.write_byte(size.to_byte())
  buf.write_bytes(ty)
  buf.write_bytes(payload)
  buf.to_bytes()
}

///|
fn concat(parts : Array[Bytes]) -> Bytes {
  let buf = Buffer()
  for p in parts {
    buf.write_bytes(p)
  }
  buf.to_bytes()
}

///|
test "bare codestream" {
  let p = @container.ContainerParser::new()
  let (log, cs) = collect(p, b"\xff\x0a\x01\x02")
  inspect(
    log.join("\n"),
    content=(
      #|BitstreamKind(BareCodestream)
      #|NoMoreAuxBox
      #|Codestream(4 byte(s))
    ),
  )
  inspect(cs, content="b\"\\xff\\x0a\\x01\\x02\"")
  inspect(p.kind(), content="BareCodestream")
  inspect(p.previous_consumed_bytes(), content="4")
}

///|
test "invalid signature" {
  let p = @container.ContainerParser::new()
  let (log, _) = collect(p, b"\x89PNG")
  inspect(log[0], content="BitstreamKind(Invalid)")
  inspect(p.kind(), content="Invalid")
}

///|
test "partial signature needs more data" {
  let p = @container.ContainerParser::new()
  let (log, _) = collect(p, b"\x00\x00\x00\x0cJX")
  assert_eq(log.length(), 0)
  inspect(p.kind(), content="Unknown")
  inspect(p.previous_consumed_bytes(), content="0")
}

///|
test "container with jxlp and aux boxes" {
  let input = concat([
    @container.container_sig,
    box_(b"ftyp", b"jxl \x00\x00\x00\x00jxl "),
    box_(b"Exif", b"\x00\x00\x00\x00MM"),
    box_(b"jxlp", b"\x00\x00\x00\x00\xff\x0a\x01"),
    box_(b"brob", b"xml abc"),
    box_(b"jxlp", b"\x80\x00\x00\x01\x02\x03"),
  ])
  let p = @container.ContainerParser::new()
  let (log, cs) = collect(p, input)
  inspect(
    log.join("\n"),
    content=(
      #|BitstreamKind(Container)
      #|AuxBoxStart { ty: ftyp, brotli_compressed: false, last_box: false }
      #|AuxBoxData(ftyp, 12 byte(s))
      #|AuxBoxEnd(ftyp)
      #|AuxBoxStart { ty: Exif, brotli_compressed: false, last_box: false }
      #|AuxBoxData(Exif, 6 byte(s))
      #|AuxBoxEnd(Exif)
      #|Codestream(3 byte(s))
      #|AuxBoxStart { ty: xml , brotli_compressed: true, last_box: false }
      #|AuxBoxData(xml , 3 byte(s))
      #|AuxBoxEnd(xml )
      #|Codestream(2 byte(s))
    ),
  )
  inspect(cs, content="b\"\\xff\\x0a\\x01\\x02\\x03\"")

  // Feed one byte at a time, re-feeding unconsumed bytes.
  let p = @container.ContainerParser::new()
  let out = Buffer()
  let pending = Buffer()
  let mut n_events = 0
  for b in input {
    pending.write_byte(b)
    let buf = pending.to_bytes()
    let (log, cs) = collect(p, buf)
    n_events += log.length()
    out.write_bytes(cs)
    pending.reset()
    pending.write_bytesview(buf[p.previous_consumed_bytes():])
  }
  inspect(out.to_bytes(), content="b\"\\xff\\x0a\\x01\\x02\\x03\"")
  inspect(n_events > 0, content="true")
}

///|
test "last jxlc box without size" {
  let input = concat([
    @container.container_sig, b"\x00\x00\x00\x00jxlc\xff\x0a\x05",
  ])
  let p = @container.ContainerParser::new()
  let (log, cs) = collect(p, input)
  inspect(
    log.join("\n"),
    content=(
      #|BitstreamKind(Container)
      #|NoMoreAuxBox
      #|Codestream(3 byte(s))
    ),
  )
  inspect(cs.length(), content="3")
}

///|
test "box errors" {
  // Duplicate jxlc.
  let input = concat([
    @container.container_sig,
    box_(b"jxlc", b"\xff\x0a"),
    box_(b"jxlc", b"\xff\x0a"),
  ])
  let r = err_of(input)
  inspect(r is Some(@bitstream.InvalidBox), content="true")
  // Out-of-order jxlp.
  let input = concat([
    @container.container_sig,
    box_(b"jxlp", b"\x00\x00\x00\x01\xff\x0a"),
  ])
  let r = err_of(input)
  inspect(r is Some(@bitstream.InvalidBox), content="true")
  // jxlc after jxlp.
  let input = concat([
    @container.container_sig,
    box_(b"jxlp", b"\x00\x00\x00\x00\xff\x0a"),
    box_(b"jxlc", b"\x00"),
  ])
  let r = err_of(input)
  inspect(r is Some(@bitstream.InvalidBox), content="true")
  // Reserved brob payload type.
  let input = concat([@container.container_sig, box_(b"brob", b"jxlc1234")])
  let r = err_of(input)
  inspect(r is Some(@bitstream.ValidationFailed(_)), content="true")
  // Box size smaller than header.
  let input = concat([@container.container_sig, b"\x00\x00\x00\x04abcd"])
  let r = err_of(input)
  inspect(r is Some(@bitstream.InvalidBox), content="true")
}

///|
fn err_of(input : Bytes) -> @bitstream.JxlError? {
  try {
    collect(@container.ContainerParser::new(), input) |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
test "default parser" {
  let p : @container.ContainerParser = Default::default()
  inspect(p.kind(), content="Unknown")
}

///|
test "parse events iterator" {
  let p = @container.ContainerParser::new()
  let input = Buffer()
  input.write_bytes(@container.container_sig)
  input.write_bytes(b"\x00\x00\x00\x0ajxlc\xff\x0a")
  input.write_bytes(b"\x00\x00\x00\x0ajxlc\xff\x0a")
  let log = p
    .feed_bytes(input.to_bytes())
    .iter()
    .map(r => {
      match r {
        Ok(ev) => "\{ev}"
        Err(e) => "Err(\{@debug.to_string(e)})"
      }
    })
    .to_array()
  inspect(
    log.join("\n"),
    content=(
      #|BitstreamKind(Container)
      #|Codestream(2 byte(s))
      #|Err(InvalidBox)
    ),
  )
}
