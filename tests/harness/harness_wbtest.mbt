///|
test "sha256/empty" {
  assert_eq(
    sha256_hex(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
}

///|
test "sha256/abc" {
  assert_eq(
    sha256_hex(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "sha256/two blocks" {
  assert_eq(
    sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
test "sha256/lengths around padding boundary" {
  // sha256 of 'a' * n, from Python hashlib
  let expected = {
    55: "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
    56: "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
    63: "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
    64: "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
    1000: "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",
  }
  for n, hex in expected {
    assert_eq(sha256_hex(Bytes::make(n, b'a')), hex)
  }
}

///|
test "npy/roundtrip" {
  let data : FixedArray[Float] = [1.0, -2.5, 0.125, 3.0, 4.0, 5.0]
  let npy = read_npy(write_npy_bytes([1, 2, 1, 3], data))
  assert_eq(npy.shape, [1, 2, 1, 3])
  assert_eq(npy.data, data)
  assert_eq(npy.frame_len(), 6)
  let frames = read_npy(write_npy_bytes([2, 3], data)).frames(2)
  assert_eq(frames.length(), 2)
  assert_eq(frames[1], ([3.0, 4.0, 5.0] : FixedArray[Float]))
}

///|
test "npy/rejects bad input" {
  assert_true(
    (try read_npy(b"\x93NUMPX\x01\x00\x00\x00") |> ignore |> Ok catch {
      e => Err(e)
    })
    is Err(_),
  )
  let bad = write_npy_bytes([4], [1.0, 2.0, 3.0, 4.0])
  assert_true(
    (try read_npy(bad[0:bad.length() - 1].to_owned()) |> ignore |> Ok catch {
      e => Err(e)
    })
    is Err(_),
  )
}

///|
test "tolerance/test.json" {
  let text =
    #|{"frames": [{"name": "", "rms_error": 0.0001, "peak_error": 0.007},
    #| {"name": "b", "rms_error": 0.02, "peak_error": 0.06}], "sha256sums": {}}
  let t = test_json_frame_tolerances(text)
  assert_eq(t, [
    { peak: Float::from_double(0.007), rmse: Float::from_double(0.0001), },
    { peak: Float::from_double(0.06), rmse: Float::from_double(0.02), },
  ])
}

///|
test "compare/errors" {
  let expected : FixedArray[Float] = [0.0, 0.0, 0.5, 0.5]
  let actual : FixedArray[Float] = [0.25, 0.0, 0.5, 0.0]
  // 2 pixels x 2 channels
  let e = channel_errors(expected, 0, actual, 2, 1, 2)
  assert_eq(e.peak, [0.25, 0.5])
  assert_eq(e.rmse, [(0.03125 : Float).sqrt(), (0.125 : Float).sqrt()])
  let tol : Array[Tolerance] = [
    { peak: 0.25, rmse: 0.2, },
    { peak: 0.6, rmse: 0.4, },
  ]
  assert_eq(check_errors(e, tol), [])
  let strict : Array[Tolerance] = [
    { peak: 0.1, rmse: 0.2, },
    { peak: 0.6, rmse: 0.1, },
  ]
  assert_eq(check_errors(e, strict).length(), 2)
  let nan : FixedArray[Float] = [(0.0 : Float) / (0.0 : Float), 0, 0.5, 0.5]
  let e = channel_errors(expected, 0, nan, 2, 1, 2)
  // NaN is ignored by the peak (f32::max) but poisons the RMSE
  assert_eq(check_errors(e, tol).length(), 1)
}

///|
test "fixture_buf/synthetic" {
  let b = Buffer()
  for v in [2, 1, 1] {
    b.write_int_le(v)
  }
  b.write_byte(0)
  b.write_bytes(b"\x01\x00\xff\xff")
  let r = FixtureReader::new(b.to_bytes())
  assert_eq(r.header(), { width: 2, height: 1, channels: 1, })
  assert_eq(r.marker(), 0)
  assert_eq(r.plane(2), ([1, 65535] : FixedArray[Int32]))
  assert_true(r.at_end())
}

///|
test "io/committed data readable" {
  // works on both native and wasm-gc (moonrun): cwd is the module root
  let fuzz = read_file(
    manifest_dir() + "/tests/fuzz_findings/bitstream_u32_overflow.fuzz",
  )
  assert_true(fuzz.length() > 0)
  let jxl = read_file(manifest_dir() + "/tests/cms/cmyk_layers.jxl")
  // container signature
  assert_eq(jxl[0:12].to_owned(), b"\x00\x00\x00\x0cJXL \x0d\x0a\x87\x0a")
  let icc = read_file(manifest_dir() + "/tests/image/grayscale.icc")
  assert_eq(icc[36:40].to_owned(), b"acsp")
}

///|
test "io/conformance fixture npy" {
  let buf = read_fixture(
    conformance_case_dir("mul_no_extra_channels") + "/reference_image.npy",
  )
  let npy = read_npy(buf)
  assert_eq(npy.shape.length(), 4)
  assert_eq(npy.data.length(), npy.shape[0] * npy.frame_len())
  let json = read_text(conformance_case_dir("bike_5") + "/test.json")
  assert_eq(test_json_frame_tolerances(json), [
    { peak: Float::from_double(0.06), rmse: Float::from_double(0.02), },
  ])
}

///|
test "io/decode fixture buf" {
  let buf = download_url_with_cache(
    "(decompressed by scripts/fetch_fixtures.sh)", "grayalpha.buf",
  )
  let r = FixtureReader::new(buf)
  let h = r.header()
  assert_eq(h.channels, 2)
  assert_eq(r.marker(), 0)
  for _ in 0..<h.channels {
    r.plane(h.width * h.height) |> ignore
  }
  // a 0xff marker ends the keyframe list
  assert_eq(r.marker(), 0xff)
  assert_true(r.at_end())
}

///|
/// The synthetic image of the reference run of the Rust `ssimulacra2` crate
/// (gradients, optionally with LCG noise).
fn synth_rgb(w : Int32, h : Int32, noise : Bool) -> FixedArray[Float] {
  let out = FixedArray::make(w * h * 3, (0.0 : Float))
  let mut s : UInt32 = 12345
  for y in 0..<h {
    for x in 0..<w {
      let px : FixedArray[Float] = [
        Float::from_int(x) / Float::from_int(w),
        Float::from_int(y) / Float::from_int(h),
        Float::from_int(x * y % 17) / 16.0,
      ]
      if noise {
        for k in 0..<3 {
          s = s * 1103515245 + 12345
          let n = Float::from_int(((s >> 16) & 0x7fff).reinterpret_as_int()) /
            32767.0 -
            0.5
          let v = px[k] + n * 0.05
          px[k] = if v < 0.0 { 0.0 } else if v > 1.0 { 1.0 } else { v }
        }
      }
      for k in 0..<3 {
        out[(y * w + x) * 3 + k] = px[k]
      }
    }
  }
  out
}

///|
test "ssimulacra2/matches the Rust crate" {
  // `ssimulacra2` 0.5.1 gives 85.3363634154 for this pair
  let (w, h) = (77, 53)
  let score = compute_frame_ssimulacra2(
    synth_rgb(w, h, false),
    synth_rgb(w, h, true),
    w,
    h,
  )
  assert_true((score - 85.3363634154).abs() < 1.0e-6)
  let same = compute_frame_ssimulacra2(
    synth_rgb(w, h, true),
    synth_rgb(w, h, true),
    w,
    h,
  )
  assert_true((same - 100.0).abs() < 1.0e-6)
}

///|
test "ssimulacra2/lcms2 vs moxcms fixture" {
  // the cms fixtures: `ssimulacra2` 0.5.1 gives 92.8602575593
  let a = download_url_with_cache(
    "(scripts/fetch_fixtures.sh cms)", "cmyk_layers.lcms2.npy",
  )
  let b = download_url_with_cache(
    "(scripts/fetch_fixtures.sh cms)", "cmyk_layers.moxcms.npy",
  )
  let a = read_npy(a)
  let b = read_npy(b)
  let rgb = fn(n : Npy) {
    let (h, w, c) = (n.shape[1], n.shape[2], n.shape[3])
    FixedArray::makei(w * h * 3, fn(i) { n.data[i / 3 * c + i % 3] })
  }
  let score = compute_frame_ssimulacra2(rgb(a), rgb(b), a.shape[2], a.shape[1])
  assert_true((score - 92.8602575593).abs() < 1.0e-6)
}
