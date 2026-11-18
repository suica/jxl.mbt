use jxl_oxide::JxlImage;
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let path = &args[1];
    jxl_coding::recorder::enable();
    let image = JxlImage::builder().open(path).expect("open");
    for i in 0..image.num_loaded_keyframes() {
        image.render_frame(i).expect("render");
    }
    print!("{}", jxl_coding::recorder::dump());
}
