///|
/// The libjxl conformance `testcases` directory
/// (`@harness.conformance_testcases_dir()`).
fn conformance_dir() -> String raise Failure {
  @harness.fixture_dir(@harness.conformance_testcases_dir(), "cafe")
}

///|
fn extract_codestream(
  data : Bytes,
) -> (@container.BitstreamKind, Bytes, Array[String]) raise {
  let parser = @container.ContainerParser::new()
  let events = parser.feed_bytes(data)
  let cs = Buffer()
  let aux = []
  while events.next() is Some(ev) {
    match ev {
      Codestream(b) => cs.write_bytesview(b)
      AuxBoxStart(ty~, ..) => aux.push("\{ty}")
      _ => ()
    }
  }
  assert_eq(parser.previous_consumed_bytes(), data.length())
  (parser.kind(), cs.to_bytes(), aux)
}

///|
test "conformance container parsing" {
  let dir = conformance_dir()
  let cases = @fs.read_dir(dir).to_owned()
  cases.sort()
  let mut n = 0
  let summary = []
  for name in cases {
    let path = dir + "/" + name + "/input.jxl"
    if !@fs.path_exists(path) {
      continue
    }
    let data = @fs.read_file_to_bytes(path)
    let (kind, cs, aux) = extract_codestream(data)
    if !(cs.length() >= 2 && cs[0] == b'\xff' && cs[1] == b'\x0a') {
      fail("\{name}: codestream does not start with FF 0A")
    }
    match kind {
      BareCodestream => assert_eq(cs.length(), data.length())
      Container => ()
      _ => fail("\{name}: unexpected kind \{kind}")
    }
    // Byte-wise feeding (in chunks of 7) must give the same codestream.
    let parser = @container.ContainerParser::new()
    let out = Buffer()
    let mut pos = 0
    let mut pending : BytesView = data[0:0]
    while pos < data.length() || pending.length() > 0 {
      let end = if pos + 7 < data.length() { pos + 7 } else { data.length() }
      let chunk = Buffer()
      chunk.write_bytesview(pending)
      chunk.write_bytesview(data[pos:end])
      pos = end
      let buf = chunk.to_bytes()
      let events = parser.feed_bytes(buf)
      while events.next() is Some(ev) {
        if ev is Codestream(b) {
          out.write_bytesview(b)
        }
      }
      pending = buf[parser.previous_consumed_bytes():]
      if pos >= data.length() && pending.length() > 0 {
        // Trailing bytes the parser cannot use (should not happen).
        fail("\{name}: \{pending.length()} trailing bytes not consumed")
      }
    }
    assert_eq(out.to_bytes(), cs)
    summary.push("\{name}: \{kind} [\{aux.join(", ")}]")
    n += 1
  }
  println(summary.join("\n"))
  assert_true(n >= 40)
}
