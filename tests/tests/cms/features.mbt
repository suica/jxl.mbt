///|
/// jxl-oxide-tests depends on jxl-oxide with `features = ["lcms2", "moxcms"]`,
/// which makes `Lcms2` the default CMS of every image.
fn init {
  @jxl.enable_default_cms(Some(@jxl.Lcms2::{ }))
}
