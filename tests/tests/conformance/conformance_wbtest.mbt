// Port of jxl-oxide-tests/tests/conformance/mod.rs (the `conformance_test!`
// invocations), generated from it: one test per case with upstream's hashes
// and tolerances (a single (peak_error, max_rmse) is written out per channel,
// as the macro expands it).

///|
test "conformance/alpha_nonpremultiplied" {
  conformance_test(
    @jxl.Lcms2::{  },
    "alpha_nonpremultiplied",
    npy_hash="cad070b944d8aff6b7865c211e44bc469b08addf5b4a19d11fdc4ef2f7494d1b",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=4,
    [
      (0.000061035, 0.000061035),
      (0.000061035, 0.000061035),
      (0.000061035, 0.000061035),
      (0.000061035, 0.000061035),
    ],
  )
}

///|
test "conformance/alpha_premultiplied" {
  conformance_test(
    @jxl.Lcms2::{  },
    "alpha_premultiplied",
    npy_hash="073c1d942ba408f94f6c0aed2fef3d442574899901c616afa060dbd8044bbdb9",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=4,
    [
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.000003815, 0.000003815),
    ],
  )
}

///|
test "conformance/alpha_triangles" {
  conformance_test(
    @jxl.Lcms2::{  },
    "alpha_triangles",
    npy_hash="1d8471e3b7f0768f408b5e5bf5fee0de49ad6886d846712b1aaa702379722e2b",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=4,
    [
      (0.001953125, 0.001953125),
      (0.001953125, 0.001953125),
      (0.001953125, 0.001953125),
      (0.001953125, 0.001953125),
    ],
  )
}

///|
test "conformance/animation_icos4d" {
  conformance_test(
    @jxl.Lcms2::{  },
    "animation_icos4d",
    npy_hash="77a060cfa0d4df183255424e13e4f41a90b3edcea1248e3f22a3b7fcafe89e49",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=48,
    channels=4,
    [
      (0.005, 0.0001),
      (0.005, 0.0001),
      (0.005, 0.0001),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/animation_newtons_cradle" {
  conformance_test(
    @jxl.Lcms2::{  },
    "animation_newtons_cradle",
    npy_hash="4309286cd22fa4008db3dcceee6a72a806c9291bd7e035cf555f3b470d0693d8",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=36,
    channels=4,
    [
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/animation_spline" {
  conformance_test(
    @jxl.Lcms2::{  },
    "animation_spline",
    npy_hash="a571c5cbba58affeeb43c44c13f81e2b1962727eb9d4e017e4f25d95c7388f10",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=60,
    channels=3,
    [
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
    ],
  )
}

///|
test "conformance/bench_oriented_brg" {
  conformance_test(
    @jxl.Lcms2::{  },
    "bench_oriented_brg",
    npy_hash="eac8c30907e41e53a73a0c002bc39e998e0ceb021bd523f5bff4580b455579e6",
    icc_hash="6603ae12a4ac1ac742cacd887e9b35552a12c354ff25a00cae069ad4b932e6cc",
    frames=1,
    channels=3,
    [
      (0.004, 0.00001),
      (0.004, 0.00001),
      (0.004, 0.00001),
    ],
  )
}

///|
test "conformance/bicycles" {
  conformance_test(
    @jxl.Lcms2::{  },
    "bicycles",
    npy_hash="6f71d8ca122872e7d850b672e7fb46b818c2dfddacd00b3934fe70aa8e0b327e",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=3,
    [
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/bike" {
  conformance_test(
    @jxl.Lcms2::{  },
    "bike",
    npy_hash="815c89d1fe0bf67b6a1c8139d0af86b6e3f11d55c5a0ed9396256fb05744469e",
    icc_hash="809e189d1bf1fadb66f130ed0463d0de374b46497d299997e7c84619cbd35ed3",
    frames=1,
    channels=3,
    [
      (0.007, 0.0001),
      (0.007, 0.0001),
      (0.007, 0.0001),
    ],
  )
}

///|
test "conformance/blendmodes" {
  conformance_test(
    @jxl.Lcms2::{  },
    "blendmodes",
    npy_hash="6ef265631818f313a70cb23788d1185408ce07243db8d5940553e7ea7467b786",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=4,
    [
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
    ],
  )
}

///|
test "conformance/cafe" {
  conformance_test(
    @jxl.Lcms2::{  },
    "cafe",
    npy_hash="4aaea4e1bda3771e62643fcdf2003ffe6048ee2870c93f67d34d6cc16cb7da4b",
    icc_hash="bef95ce5cdb139325f2a299b943158e00e39a7ca3cf597ab3dfa3098e42fc707",
    frames=1,
    channels=3,
    [
      (0.004, 0.00001),
      (0.004, 0.00001),
      (0.004, 0.00001),
    ],
  )
}

///|
test "conformance/cmyk_layers" {
  conformance_test(
    @jxl.Lcms2::{  },
    "cmyk_layers",
    npy_hash="a01913d4e4b1a89bd96e5de82a5dfb9925c7827ee6380ad60c0b1c4becb53880",
    icc_hash="4855b8fabb96bdc6495d45d089bb8c8efb1ae18389e0dc9e75a5f701a9c0b662",
    frames=1,
    channels=5,
    [
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/delta_palette" {
  conformance_test(
    @jxl.Lcms2::{  },
    "delta_palette",
    npy_hash="952b9e16aa0ae23df38c6b358cb4835b5f9479838f6855b96845ea54b0528c1f",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=3,
    [
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/grayscale_jpeg" {
  conformance_test(
    @jxl.Lcms2::{  },
    "grayscale_jpeg",
    npy_hash="c0b86989e287649b944f1734ce182d1c1ac0caebf12cec7d487d9793f51f5b8f",
    icc_hash="78001f4bf342ecf417b8dac5e3c7cf8da3ee25701951bc2a7e0868bc6dc81cac",
    frames=1,
    channels=1,
    [
      (0.004, 0.00001),
    ],
  )
}

///|
test "conformance/grayscale" {
  conformance_test(
    @jxl.Lcms2::{  },
    "grayscale",
    npy_hash="59162e158e042dc44710eb4d334cea78135399613461079582d963fe79251b68",
    icc_hash="57363d9ec00043fe6e3f40b1c3e0cc4676773011fd0818710fb26545002ac27d",
    frames=1,
    channels=1,
    [
      (0.004, 0.0001),
    ],
  )
}

///|
test "conformance/grayscale_public_university" {
  conformance_test(
    @jxl.Lcms2::{  },
    "grayscale_public_university",
    npy_hash="851abd36b93948cfaeabeb65c8bb8727ebca4bb1d2697bce73461e05ccf24c1e",
    icc_hash="48d006762d583f6e354a3223c0a5aeaff7f45a324e229d237d69630bcc170241",
    frames=1,
    channels=1,
    [
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/lossless_pfm" {
  conformance_test(
    @jxl.Lcms2::{  },
    "lossless_pfm",
    npy_hash="1eac3ced5c60ef8a3a602f54c6a9d28162dfee51cd85b8dd7e52f6e3212bbb52",
    icc_hash="d7f9e32ac2a06a7e3865a828e865dafb7cf1947584d3c06ec97a660c59786b51",
    frames=1,
    channels=3,
    [
      (0.0, 0.0),
      (0.0, 0.0),
      (0.0, 0.0),
    ],
  )
}

///|
test "conformance/lz77_flower" {
  conformance_test(
    @jxl.Lcms2::{  },
    "lz77_flower",
    npy_hash="953d3ada476e3218653834c9addc9c16bb6f9f03b18be1be8a85c07a596ea32d",
    icc_hash="793cb9df4e4ce93ce8fe827fde34e7fb925b7079fcb68fba1e56fc4b35508ccb",
    frames=1,
    channels=3,
    [
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/noise" {
  conformance_test(
    @jxl.Lcms2::{  },
    "noise",
    npy_hash="b7bb25b911ab5f4b9a6a6da9c220c9ea738de685f9df25eb860e6bbe1302237d",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=3,
    [
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
    ],
  )
}

///|
test "conformance/opsin_inverse" {
  conformance_test(
    @jxl.Lcms2::{  },
    "opsin_inverse",
    npy_hash="a3142a144c112160b8e5a12eb17723fa5fe0cfeb00577e4fb59a5f6cea126a9b",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=3,
    [
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
    ],
  )
}

///|
test "conformance/patches" {
  conformance_test(
    @jxl.Lcms2::{  },
    "patches",
    npy_hash="7f1309014d9c30efe4342a0e0a46767967b756fdfdc393e2e702edea4b1fd0bd",
    icc_hash="956c9b6ecfef8ef1420e8e93e30a89d3c1d4f7ce5c2f3e2612f95c05a7097064",
    frames=1,
    channels=4,
    [
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/patches_lossless" {
  conformance_test(
    @jxl.Lcms2::{  },
    "patches_lossless",
    npy_hash="806201a2c99d27a54c400134b3db7bfc57476f9bc0775e59eea802d28aba75de",
    icc_hash="3a10bcd8e4c39d12053ebf66d18075c7ded4fd6cf78d26d9c47bdc0cde215115",
    frames=1,
    channels=4,
    [
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
      (0.000976562, 0.000976562),
    ],
  )
}

///|
test "conformance/progressive" {
  conformance_test(
    @jxl.Lcms2::{  },
    "progressive",
    npy_hash="5a9d25412e2393ee11632942b4b683cda3f838dd72ab2550cfffc8f34d69c852",
    icc_hash="956c9b6ecfef8ef1420e8e93e30a89d3c1d4f7ce5c2f3e2612f95c05a7097064",
    frames=1,
    channels=3,
    [
      (0.02, 0.0001),
      (0.02, 0.0001),
      (0.02, 0.0001),
    ],
  )
}

///|
test "conformance/spot" {
  conformance_test(
    @jxl.Lcms2::{  },
    "spot",
    npy_hash="82de72e756db992792b8e3eb5eac5194ef83e9ab4dc03e846492fbedde7b58da",
    icc_hash="ce0caee9506116ea94d7367d646f7fd6d0b7e82feb8d1f3de4edb3ba57bae07e",
    frames=1,
    channels=6,
    [
      (0.000003815, 0.000003815),
      (0.000003815, 0.000003815),
      (0.000003815, 0.000003815),
      (0.000003815, 0.000003815),
      (0.000003815, 0.000003815),
      (0.000003815, 0.000003815),
    ],
  )
}

///|
test "conformance/sunset_logo" {
  conformance_test(
    @jxl.Lcms2::{  },
    "sunset_logo",
    npy_hash="bf1c1d5626ced3746df867cf3e3a25f3d17512c2e837b5e3a04743660e42ad81",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=4,
    [
      (0.000244141, 0.000244141),
      (0.000244141, 0.000244141),
      (0.000244141, 0.000244141),
      (0.000244141, 0.000244141),
    ],
  )
}

///|
test "conformance/upsampling" {
  conformance_test(
    @jxl.Lcms2::{  },
    "upsampling",
    npy_hash="9b83952c4bba9dc93fd5c5c49e27eab29301e848bf70dceccfec96b48d3ab975",
    icc_hash="80a1d9ea2892c89ab10a05fcbd1d752069557768fac3159ecd91c33be0d74a19",
    frames=1,
    channels=4,
    [
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
      (0.004, 0.0001),
    ],
  )
}
