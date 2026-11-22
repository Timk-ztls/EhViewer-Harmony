/*
 * NAPI 胶水层：gifutils（鸿蒙侧新增，见 inventory/native-image.extra.txt）。
 *
 * 对应上游 cpp/gifutils.c：
 *   ImageKt.rewriteGifSource(DirectByteBuffer) → rewriteGifSource(buffer)
 *   ImageKt.rewriteGifSource2(fd)              → rewriteGifSourceFd(fd)
 *
 * doRewrite 的扫描/改写逻辑逐行保留（把首帧过短的帧延迟改成 DEFAULT_FRAME_DELAY）。
 * 差异：上游用 GetDirectBufferAddress / mmap64 拿到可写地址，鸿蒙侧
 *   - 缓冲区版：直接写 napi ArrayBuffer 的底层内存（调用方保证可写、非共享只读）；
 *   - fd 版：mmap + MAP_SHARED 写回文件，与上游 rewriteGifSource2 语义一致。
 */

#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "napi_common.h"
#include "../jni/log.h"

#define GIF_HEADER_87A "GIF87a"
#define GIF_HEADER_89A "GIF89a"

#define FRAME_DELAY_START_MARKER_VALUE 0x0021F904
#define MINIMUM_FRAME_DELAY 2
#define DEFAULT_FRAME_DELAY 10

typedef signed char gif_byte;

static const gif_byte* frame_delay_start_marker(void) {
  static const int value = FRAME_DELAY_START_MARKER_VALUE;
  return (const gif_byte*) &value;
}

static inline bool isGif(const void* addr) {
  return !memcmp(addr, GIF_HEADER_87A, 6) || !memcmp(addr, GIF_HEADER_89A, 6);
}

static void doRewrite(gif_byte* addr, size_t size) {
  const gif_byte* marker = frame_delay_start_marker();

  if (addr == NULL || size < 7 || !isGif(addr)) {
    return;
  }
  for (size_t i = 0; i < size - 8; i++) {
    if (addr[i] == marker[3] && addr[i + 1] == marker[2] &&
        addr[i + 2] == marker[1] && addr[i + 3] == marker[0]) {
      gif_byte* end = addr + i + 4;
      int frameDelay;
      if (end[4] != 0) {
        continue;
      }
      frameDelay = end[2] << 8 | end[1];
      if (frameDelay > MINIMUM_FRAME_DELAY) {
        break; /* Quit if the first block looks normal, for performance */
      }
      end[1] = DEFAULT_FRAME_DELAY;
      end[2] = 0;
    }
  }
}

static napi_value RewriteGifSource(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  void* data = NULL;
  size_t length = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    napi_throw_error(env, NULL, "rewriteGifSource(buffer)");
    return NULL;
  }
  if (!ehviewer_napi_get_bytes(env, argv[0], &data, &length)) {
    napi_throw_error(env, NULL, "argument must be an ArrayBuffer");
    return NULL;
  }

  doRewrite((gif_byte*) data, length);

  return NULL;
}

static napi_value RewriteGifSourceFd(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  int32_t fd = -1;
  struct stat st;
  size_t size;
  gif_byte* addr = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    napi_throw_error(env, NULL, "rewriteGifSourceFd(fd)");
    return NULL;
  }
  napi_get_value_int32(env, argv[0], &fd);
  if (fd < 0) {
    napi_throw_error(env, NULL, "invalid file descriptor");
    return NULL;
  }
  if (fstat(fd, &st) != 0 || st.st_size <= 0) {
    napi_throw_error(env, NULL, "can not stat file descriptor");
    return NULL;
  }
  size = (size_t) st.st_size;
  addr = (gif_byte*) mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (addr == MAP_FAILED) {
    napi_throw_error(env, NULL, "mmap failed");
    return NULL;
  }
  doRewrite(addr, size);
  munmap(addr, size);

  return NULL;
}

napi_value napi_gifutils_init(napi_env env, napi_value exports) {
  napi_property_descriptor functions[] = {
      { "rewriteGifSource", NULL, RewriteGifSource, NULL, NULL, NULL, napi_default, NULL },
      { "rewriteGifSourceFd", NULL, RewriteGifSourceFd, NULL, NULL, NULL, napi_default, NULL },
  };

  napi_define_properties(env, exports, sizeof(functions) / sizeof(functions[0]), functions);

  return exports;
}
