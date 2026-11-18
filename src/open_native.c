// File access for `JxlImageBuilder::open` on the native target
// (`std::fs::File`): fopen/fread/fclose and errno messages.

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "moonbit.h"

MOONBIT_FFI_EXPORT void *suica_jxl_fopen(moonbit_bytes_t path) {
  errno = 0;
  return (void *)fopen((const char *)path, "rb");
}

MOONBIT_FFI_EXPORT int suica_jxl_is_null(void *ptr) { return ptr == NULL; }

MOONBIT_FFI_EXPORT int suica_jxl_fread(moonbit_bytes_t buf, int start, int len,
                                       void *file) {
  errno = 0;
  size_t n = fread(buf + start, 1, (size_t)len, (FILE *)file);
  if (n == 0 && ferror((FILE *)file)) {
    return -1;
  }
  return (int)n;
}

MOONBIT_FFI_EXPORT int suica_jxl_fclose(void *file) {
  return fclose((FILE *)file);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t suica_jxl_last_error(void) {
  const char *msg = strerror(errno);
  size_t len = strlen(msg);
  moonbit_bytes_t out = moonbit_make_bytes(len, 0);
  memcpy(out, msg, len);
  return out;
}
