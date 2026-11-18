// Interim until src/moxcms lands (see cms_wbtest.mbt.pending for upstream's
// test): the `Lcms2` render compared, as upstream compares it with moxcms's,
// with jxl-oxide's own moxcms render of the same image
// (`cmyk_layers.moxcms.npy`, from `scripts/fetch_fixtures.sh cms`).

///|
test "cms/cmyk_lcms2_moxcms" {
  let image = open_cmyk_layers()
  let width = image.width()
  let height = image.height()
  image.request_color_encoding(linear_srgb())
  image.set_cms(@jxl.Lcms2::{ })
  let lcms2_frame = render_frame_rgb(image)
  let npy = @harness.read_npy(
    @harness.download_url_with_cache(
      "(rendered by scripts/fetch_fixtures.sh cms)", "cmyk_layers.moxcms.npy",
    ),
  )
  let c = npy.shape[3]
  let moxcms_frame = FixedArray::makei(width * height * 3, fn(i) {
    npy.data[i / 3 * c + i % 3]
  })
  let score = @harness.compute_frame_ssimulacra2(
    lcms2_frame, moxcms_frame, width, height,
  )
  assert_true(
    score >= 90.0,
    msg="SSIMULACRA2 score too low (score < 90.0), score = \{score}",
  )
}
