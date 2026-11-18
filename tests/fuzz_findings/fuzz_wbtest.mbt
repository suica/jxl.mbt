///|
test "fuzz_findings/large_output_size" {
  fuzz_decode("large_output_size")
}

///|
test "fuzz_findings/multiply_integer_overflow" {
  fuzz_decode("multiply_integer_overflow")
}

///|
test "fuzz_findings/dequant_matrix_encoding_mode" {
  fuzz_decode("dequant_matrix_encoding_mode")
}

///|
test "fuzz_findings/num_groups_overflow" {
  fuzz_decode("num_groups_overflow")
}

///|
test "fuzz_findings/extensions_overflow" {
  fuzz_decode("extensions_overflow")
}

///|
test "fuzz_findings/hybrid_integer_bits" {
  fuzz_decode("hybrid_integer_bits")
}

///|
test "fuzz_findings/icc_output_size_alloc_failed" {
  fuzz_decode("icc_output_size_alloc_failed")
}

///|
test "fuzz_findings/spline_starting_point_overflow" {
  fuzz_decode("spline_starting_point_overflow")
}

///|
test "fuzz_findings/noise_on_invisible_frame" {
  fuzz_decode("noise_on_invisible_frame")
}

///|
test "fuzz_findings/sharp_lut_oob" {
  fuzz_decode("sharp_lut_oob")
}

///|
test "fuzz_findings/modular_zero_width" {
  fuzz_decode("modular_zero_width")
}

///|
test "fuzz_findings/icc_tag_size" {
  fuzz_decode("icc_tag_size")
}

///|
test "fuzz_findings/hf_coeff_non_zeros" {
  fuzz_decode("hf_coeff_non_zeros")
}

///|
test "fuzz_findings/modular_wrong_palette" {
  fuzz_decode("modular_wrong_palette")
}

///|
test "fuzz_findings/permutation_lehmer_oob" {
  fuzz_decode("permutation_lehmer_oob")
}

///|
test "fuzz_findings/permutation_overflow" {
  fuzz_decode("permutation_overflow")
}

///|
test "fuzz_findings/patch_coord_overflow" {
  fuzz_decode("patch_coord_overflow")
}

///|
test "fuzz_findings/spline_add_one_overflow" {
  fuzz_decode("spline_add_one_overflow")
}

///|
test "fuzz_findings/patch_target_limit" {
  fuzz_decode("patch_target_limit")
}

///|
test "fuzz_findings/hf_coeff_out_of_zeros" {
  fuzz_decode("hf_coeff_out_of_zeros")
}

///|
test "fuzz_findings/dequant_matrix_band" {
  fuzz_decode("dequant_matrix_band")
}

///|
test "fuzz_findings/icc_parse_oob" {
  fuzz_decode("icc_parse_oob")
}

///|
test "fuzz_findings/hfmul_non_positive" {
  fuzz_decode("hfmul_non_positive")
}

///|
test "fuzz_findings/ma_tree_multiple_frames_0" {
  fuzz_decode("ma_tree_multiple_frames_0")
}

///|
test "fuzz_findings/ma_tree_multiple_frames_1" {
  fuzz_decode("ma_tree_multiple_frames_1")
}

///|
test "fuzz_findings/ma_tree_multiple_frames_2" {
  fuzz_decode("ma_tree_multiple_frames_2")
}

///|
test "fuzz_findings/ma_tree_multiple_frames_3" {
  fuzz_decode("ma_tree_multiple_frames_3")
}

///|
test "fuzz_findings/ma_tree_multiple_frames_4" {
  fuzz_decode("ma_tree_multiple_frames_4")
}

///|
test "fuzz_findings/ma_tree_multiple_frames_5" {
  fuzz_decode("ma_tree_multiple_frames_5")
}

///|
test "fuzz_findings/modular_jpeg_upsampling" {
  fuzz_decode("modular_jpeg_upsampling")
}

///|
test "fuzz_findings/container_small_jxlp" {
  fuzz_decode("container_small_jxlp")
}

///|
test "fuzz_findings/patchref_idx" {
  fuzz_decode("patchref_idx")
}

///|
test "fuzz_findings/modular_multiply_overflow" {
  fuzz_decode("modular_multiply_overflow")
}

///|
test "fuzz_findings/dequant_matrix_zero" {
  fuzz_decode("dequant_matrix_zero")
}

///|
test "fuzz_findings/spline_coordinate" {
  fuzz_decode("spline_coordinate")
}

///|
test "fuzz_findings/invalid_lz77" {
  fuzz_decode("invalid_lz77")
}

///|
test "fuzz_findings/noise_out_of_range" {
  fuzz_decode("noise_out_of_range")
}

///|
test "fuzz_findings/zero_sized_squeeze" {
  fuzz_decode("zero_sized_squeeze")
}

///|
test "fuzz_findings/lz77_distance_overflow" {
  fuzz_decode("lz77_distance_overflow")
}

///|
test "fuzz_findings/lz77_distance_overflow_2" {
  fuzz_decode("lz77_distance_overflow_2")
}

///|
test "fuzz_findings/icc_curve_overflow" {
  fuzz_decode("icc_curve_overflow")
}

///|
test "fuzz_findings/squeeze_tendency_overflow" {
  fuzz_decode("squeeze_tendency_overflow")
}

///|
test "fuzz_findings/timeout_dim_shift" {
  fuzz_decode("timeout_dim_shift")
}

///|
test "fuzz_findings/ec_upsampling" {
  fuzz_decode("ec_upsampling")
}

///|
test "fuzz_findings/too_many_squeezes" {
  fuzz_decode("too_many_squeezes")
}

///|
test "fuzz_findings/prop_abs_overflow" {
  fuzz_decode("prop_abs_overflow")
}

///|
test "fuzz_findings/squeeze_groups_off_by_one" {
  fuzz_decode("squeeze_groups_off_by_one")
}

///|
test "fuzz_findings/cluster_hole" {
  fuzz_decode("cluster_hole")
}

///|
test "fuzz_findings/invalid_alpha_ref" {
  fuzz_decode("invalid_alpha_ref")
}

///|
test "fuzz_findings/modular_jpeg_upsampling_2" {
  fuzz_decode("modular_jpeg_upsampling_2")
}

///|
test "fuzz_findings/grayscale_icc" {
  fuzz_decode("grayscale_icc")
}

///|
test "fuzz_findings/icc_large_stride" {
  fuzz_decode("icc_large_stride")
}

///|
test "fuzz_findings/upsample_separate_ec" {
  fuzz_decode("upsample_separate_ec")
}

///|
test "fuzz_findings/lz77_num_to_copy_overflow" {
  fuzz_decode("lz77_num_to_copy_overflow")
}

///|
test "fuzz_findings/bitstream_u32_overflow" {
  fuzz_decode("bitstream_u32_overflow")
}

///|
test "fuzz_findings/rct_zero_sized" {
  fuzz_decode("rct_zero_sized")
}

///|
test "fuzz_findings/ma_lookup_overflow" {
  fuzz_decode("ma_lookup_overflow")
}

///|
test "fuzz_findings/hf_preset_out_of_range" {
  fuzz_decode("hf_preset_out_of_range")
}

///|
test "fuzz_findings/hf_varblock_across_group" {
  fuzz_decode("hf_varblock_across_group")
}

///|
test "fuzz_findings/upsampling_sum_not_finite" {
  fuzz_decode("upsampling_sum_not_finite")
}

///|
test "fuzz_findings/ma_table_decode" {
  fuzz_decode("ma_table_decode")
}
