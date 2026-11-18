///|
test "large box header" {
  let r = ContainerBoxHeader::parse(
    b"\x00\x00\x00\x01jxlc\x00\x00\x00\x00\x00\x00\x00\x20",
  )
  guard r is Done(header~, header_size~) else { fail("expected header") }
  inspect(header_size, content="16")
  assert_eq(header.box_size(), Some(16UL))
  inspect(header.box_type(), content="jxlc")
  inspect(header.is_last(), content="false")
}
