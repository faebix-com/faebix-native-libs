// Copyright 2026 faebix
// SPDX-License-Identifier: Apache-2.0
//
// Link check: a shared library that uses both static libraries the way an app
// would (a small JPEG written with an ICC profile, then piex on the result).
// The build fails if a symbol is missing; scripts/check-16k.sh then checks
// the page alignment of the result and reports its size.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" {
#include "jpeglib.h"
}
#include "src/piex.h"

namespace {

class MemoryStream : public piex::StreamInterface {
 public:
  MemoryStream(const std::uint8_t* data, size_t size) : data_(data), size_(size) {}
  piex::Error GetData(const size_t offset, const size_t length, std::uint8_t* out) override {
    if (offset > size_ || length > size_ - offset) return piex::kFail;
    std::memcpy(out, data_ + offset, length);
    return piex::kOk;
  }

 private:
  const std::uint8_t* data_;
  size_t size_;
};

}  // namespace

// Returns 0 when a JPEG was written and piex did not mistake it for a RAW file.
extern "C" __attribute__((visibility("default"))) int faebix_linkcheck(void) {
  const int width = 16, height = 16;
  unsigned char row[16 * 3];
  for (int i = 0; i < width * 3; i++) row[i] = static_cast<unsigned char>(i * 5);
  const JOCTET icc[] = {0, 0, 0, 0};

  jpeg_compress_struct cinfo;
  jpeg_error_mgr jerr;
  cinfo.err = jpeg_std_error(&jerr);
  jpeg_create_compress(&cinfo);
  unsigned char* out = nullptr;
  unsigned long out_size = 0;
  jpeg_mem_dest(&cinfo, &out, &out_size);
  cinfo.image_width = width;
  cinfo.image_height = height;
  cinfo.input_components = 3;
  cinfo.in_color_space = JCS_RGB;
  jpeg_set_defaults(&cinfo);
  jpeg_set_quality(&cinfo, 95, TRUE);
  jpeg_start_compress(&cinfo, TRUE);
  jpeg_write_icc_profile(&cinfo, icc, sizeof(icc));
  while (cinfo.next_scanline < cinfo.image_height) {
    JSAMPROW rows[1] = {row};
    jpeg_write_scanlines(&cinfo, rows, 1);
  }
  jpeg_finish_compress(&cinfo);
  jpeg_destroy_compress(&cinfo);

  int result = (out_size > 2 && out[0] == 0xFF && out[1] == 0xD8) ? 0 : 1;
  MemoryStream stream(out, out_size);
  if (piex::IsRaw(&stream)) result |= 2;
  piex::PreviewImageData preview;
  if (piex::GetPreviewImageData(&stream, &preview) == piex::kOk) result |= 4;
  std::free(out);
  return result;
}
