///|
test "jbrd/bench_oriented_brg" {
  run_jbrd(
    @harness.conformance_path("bench_oriented_brg"),
    "cad665c67d74e3e5cf775ef618c73b0e70dfece33db7dbe0130bc889f2214e1b",
  )
}

///|
test "jbrd/cafe" {
  run_jbrd(
    @harness.conformance_path("cafe"),
    "b6f6e4f820ac69234184434e5b77156401fb782bb46b96e26255ff51be1ec290",
  )
}

///|
test "jbrd/grayscale_jpeg" {
  run_jbrd(
    @harness.conformance_path("grayscale_jpeg"),
    "a170600cc02b2b029dc79c5ee72dbf9107e8de5a64f1d8b1732c759e09a3d41d",
  )
}

///|
test "jbrd/genshin_ycbcr_420" {
  run_jbrd(
    @harness.decode_testcases_dir() + "/genshin_ycbcr_420/input.jxl",
    "24e05ce200df019710eb56cad43e4349bd6edee05865b1eb0eee1581406535b5",
  )
}

///|
test "jbrd/issue_425" {
  run_jbrd(
    @harness.decode_testcases_dir() + "/issue_425/input.jxl",
    "c00df4d5b151556cfe92ac4b13d81e2a1ee20fa066cd5fddd3cdd1ae52f0fe00",
  )
}

///|
test "jbrd/starrail_jpegli_xyb" {
  run_jbrd(
    @harness.decode_testcases_dir() + "/starrail_jpegli_xyb/input.jxl",
    "21ddc2688c89ec279a2e9415bc2e82c4d4b56362316d1332131b6fb97b0d1ea0",
  )
}
