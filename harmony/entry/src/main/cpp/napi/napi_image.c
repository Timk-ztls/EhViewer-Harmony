/*
 * NAPI 胶水层：libimage 解码子系统（鸿蒙侧新增，见 inventory/native-image.extra.txt）。
 *
 * 对应上游 jni/image/java_wrapper.c 的 1:1 语义移植：
 *   Image1.nativeDecode       → nativeImage.decode(buffer, partially)
 *   Image1.nativeCreate       → nativeImage.createPlain(width, height, pixels)
 *   Image1.nativeComplete     → image.complete()
 *   Image1.nativeIsCompleted  → image.isCompleted()
 *   Image1.nativeGetByteCount → image.byteCount
 *   Image1.nativeRender       → image.render(dst, dstW, dstH, ...)
 *   Image1.nativeAdvance      → image.advance()
 *   Image1.nativeGetDelay     → image.delay
 *   Image1.nativeFrameCount   → image.frameCount
 *   Image1.nativeIsOpaque     → image.isOpaque()
 *   Image1.nativeIsGray       → image.isGray(error)
 *   Image1.nativeClahe        → image.clahe(toGray)
 *   Image1.nativeRecycle      → image.recycle()
 *   Image.nativeGetSupportedFormats   → nativeImage.getSupportedFormats()
 *   Image.nativeGetDecoderDescription → nativeImage.getDecoderDescription(format)
 *
 * 与上游的两点差异（写入 MR）：
 *  1) 上游 Image1 是「裸指针 + 反射构造的 Java 对象」，鸿蒙侧改为带 finalizer 的
 *     NAPI 外部对象，裸指针不出 C 边界。
 *  2) 上游 Image1 没有「取像素首地址」的入口（Bitmap 由 Java 侧持有），
 *     这里补 getPixels()：按 byteCount 分配缓冲并调用 render() 拷出当前帧；
 *     需要零拷贝时用 render() 直接写调用方的 ArrayBuffer。
 */

#include <stdlib.h>
#include <string.h>

#include "napi_common.h"

#include "../jni/image/image.h"
#include "../jni/stream/input_stream.h"
#include "../jni/log.h"

typedef struct {
  void* image;
  int format;
} ImageHandle;

static napi_ref g_image_constructor = NULL;

/* getPixels() 分配的像素缓冲随 ArrayBuffer 回收，避免每次取帧泄漏 byteCount 字节 */
static void free_external_buffer(napi_env env, void* data, void* hint) {
  (void) env;
  (void) hint;
  free(data);
}

static void image_handle_finalize(napi_env env, void* data, void* hint) {
  ImageHandle* handle = (ImageHandle*) data;
  (void) env;
  (void) hint;
  if (handle == NULL) {
    return;
  }
  if (handle->image != NULL) {
    recycle(ehviewer_compat_env(), handle->image, handle->format);
    handle->image = NULL;
  }
  free(handle);
}

static bool unwrap_image(napi_env env, napi_callback_info info, ImageHandle** out,
                         size_t* argc, napi_value* argv) {
  napi_value thisValue = NULL;
  if (napi_get_cb_info(env, info, argc, argv, &thisValue, NULL) != napi_ok) {
    napi_throw_error(env, NULL, "can not get callback info");
    return false;
  }
  if (napi_unwrap(env, thisValue, (void**) out) != napi_ok || *out == NULL) {
    napi_throw_error(env, NULL, "invalid NativeImage handle");
    return false;
  }
  return true;
}

static napi_value ImageConstructor(napi_env env, napi_callback_info info) {
  (void) info;
  napi_throw_error(env, NULL, "NativeImage can not be constructed directly, use decode()");
  return NULL;
}

/* ---------------- 实例方法 ---------------- */

static napi_value ImageGetPixels(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  ImageHandle* handle = NULL;
  int byteCount;
  unsigned char* buffer = NULL;
  napi_value result = NULL;

  if (!unwrap_image(env, info, &handle, &argc, NULL)) {
    return NULL;
  }
  if (handle->image == NULL) {
    napi_throw_error(env, NULL, "image already recycled");
    return NULL;
  }

  byteCount = get_byte_count(handle->image, handle->format);
  if (byteCount <= 0) {
    napi_throw_error(env, NULL, "image has no pixel buffer yet, call complete() first");
    return NULL;
  }

  buffer = (unsigned char*) malloc((size_t) byteCount);
  if (buffer == NULL) {
    napi_throw_error(env, NULL, "out of memory");
    return NULL;
  }
  memset(buffer, 0, (size_t) byteCount);
  render(handle->image, handle->format, 0, 0, buffer,
      get_width(handle->image, handle->format), get_height(handle->image, handle->format),
      0, 0, get_width(handle->image, handle->format), get_height(handle->image, handle->format),
      false, 0);

  if (napi_create_external_arraybuffer(env, buffer, (size_t) byteCount,
          free_external_buffer, NULL, &result) != napi_ok) {
    free(buffer);
    napi_throw_error(env, NULL, "can not create ArrayBuffer");
    return NULL;
  }
  return result;
}

static napi_value ImageComplete(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  ImageHandle* handle = NULL;

  if (!unwrap_image(env, info, &handle, &argc, NULL)) {
    return NULL;
  }
  if (handle->image == NULL) {
    return ehviewer_napi_bool(env, false);
  }
  return ehviewer_napi_bool(env, complete(ehviewer_compat_env(), handle->image, handle->format));
}

static napi_value ImageIsCompleted(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  ImageHandle* handle = NULL;

  if (!unwrap_image(env, info, &handle, &argc, NULL)) {
    return NULL;
  }
  if (handle->image == NULL) {
    return ehviewer_napi_bool(env, false);
  }
  return ehviewer_napi_bool(env, is_completed(handle->image, handle->format));
}

static napi_value ImageRender(napi_env env, napi_callback_info info) {
  size_t argc = 11;
  napi_value argv[11] = { NULL };
  ImageHandle* handle = NULL;
  void* dst = NULL;
  size_t dstLength = 0;
  int32_t dstW = 0, dstH = 0, srcX = 0, srcY = 0, dstX = 0, dstY = 0;
  int32_t width = 0, height = 0, defaultColor = 0;
  bool fillBlank = false;

  if (!unwrap_image(env, info, &handle, &argc, argv)) {
    return NULL;
  }
  if (handle->image == NULL) {
    napi_throw_error(env, NULL, "image already recycled");
    return NULL;
  }
  if (argc < 11) {
    napi_throw_error(env, NULL, "render() needs 11 arguments");
    return NULL;
  }
  if (!ehviewer_napi_get_bytes(env, argv[0], &dst, &dstLength)) {
    napi_throw_error(env, NULL, "argument 0 must be an ArrayBuffer");
    return NULL;
  }
  napi_get_value_int32(env, argv[1], &dstW);
  napi_get_value_int32(env, argv[2], &dstH);
  napi_get_value_int32(env, argv[3], &srcX);
  napi_get_value_int32(env, argv[4], &srcY);
  napi_get_value_int32(env, argv[5], &dstX);
  napi_get_value_int32(env, argv[6], &dstY);
  napi_get_value_int32(env, argv[7], &width);
  napi_get_value_int32(env, argv[8], &height);
  napi_get_value_bool(env, argv[9], &fillBlank);
  napi_get_value_int32(env, argv[10], &defaultColor);

  if (dstW <= 0 || dstH <= 0 || dstLength < (size_t) dstW * (size_t) dstH * 4) {
    napi_throw_error(env, NULL, "destination buffer too small");
    return NULL;
  }

  render(handle->image, handle->format, srcX, srcY, dst, dstW, dstH, dstX, dstY,
      width, height, fillBlank, defaultColor);

  return NULL;
}

static napi_value ImageAdvance(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  ImageHandle* handle = NULL;

  if (!unwrap_image(env, info, &handle, &argc, NULL)) {
    return NULL;
  }
  if (handle->image != NULL) {
    advance(handle->image, handle->format);
  }
  return NULL;
}

static napi_value ImageIsOpaque(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  ImageHandle* handle = NULL;

  if (!unwrap_image(env, info, &handle, &argc, NULL)) {
    return NULL;
  }
  if (handle->image == NULL) {
    return ehviewer_napi_bool(env, false);
  }
  return ehviewer_napi_bool(env, is_opaque(handle->image, handle->format));
}

static napi_value ImageIsGray(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  ImageHandle* handle = NULL;
  int32_t error = 0;

  if (!unwrap_image(env, info, &handle, &argc, argv)) {
    return NULL;
  }
  if (handle->image == NULL) {
    return ehviewer_napi_bool(env, false);
  }
  if (argc >= 1) {
    napi_get_value_int32(env, argv[0], &error);
  }
  return ehviewer_napi_bool(env, is_gray(handle->image, handle->format, error));
}

static napi_value ImageClahe(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  ImageHandle* handle = NULL;
  bool toGray = false;

  if (!unwrap_image(env, info, &handle, &argc, argv)) {
    return NULL;
  }
  if (handle->image == NULL) {
    napi_throw_error(env, NULL, "image already recycled");
    return NULL;
  }
  if (argc >= 1) {
    napi_get_value_bool(env, argv[0], &toGray);
  }
  clahe(handle->image, handle->format, toGray);
  return NULL;
}

static napi_value ImageRecycle(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  ImageHandle* handle = NULL;

  if (!unwrap_image(env, info, &handle, &argc, NULL)) {
    return NULL;
  }
  if (handle->image != NULL) {
    recycle(ehviewer_compat_env(), handle->image, handle->format);
    handle->image = NULL;
  }
  return NULL;
}

/* ---------------- 只读属性 ---------------- */

#define IMAGE_GETTER(name, expr)                                          \
  static napi_value name(napi_env env, napi_callback_info info) {         \
    size_t argc = 0;                                                      \
    ImageHandle* handle = NULL;                                           \
    if (!unwrap_image(env, info, &handle, &argc, NULL)) {                  \
      return NULL;                                                        \
    }                                                                     \
    if (handle->image == NULL) {                                          \
      return ehviewer_napi_int32(env, 0);                                 \
    }                                                                     \
    return ehviewer_napi_int32(env, (int32_t) (expr));                     \
  }

IMAGE_GETTER(ImageGetWidth, get_width(handle->image, handle->format))
IMAGE_GETTER(ImageGetHeight, get_height(handle->image, handle->format))
IMAGE_GETTER(ImageGetByteCount, get_byte_count(handle->image, handle->format))
IMAGE_GETTER(ImageGetDelay, get_delay(handle->image, handle->format))
IMAGE_GETTER(ImageGetFrameCount, get_frame_count(handle->image, handle->format))
IMAGE_GETTER(ImageGetFormat, handle->format)

/* ---------------- 模块级函数 ---------------- */

static napi_value CreateImageObject(napi_env env, void* image, int format) {
  napi_value constructor = NULL;
  napi_value object = NULL;
  ImageHandle* handle = NULL;

  if (image == NULL) {
    return NULL;
  }

  handle = (ImageHandle*) malloc(sizeof(ImageHandle));
  if (handle == NULL) {
    recycle(ehviewer_compat_env(), image, format);
    napi_throw_error(env, NULL, "out of memory");
    return NULL;
  }
  handle->image = image;
  handle->format = format;

  if (g_image_constructor == NULL ||
      napi_get_reference_value(env, g_image_constructor, &constructor) != napi_ok ||
      constructor == NULL ||
      napi_new_instance(env, constructor, 0, NULL, &object) != napi_ok) {
    free(handle);
    recycle(ehviewer_compat_env(), image, format);
    napi_throw_error(env, NULL, "can not instantiate NativeImage");
    return NULL;
  }

  if (napi_wrap(env, object, handle, image_handle_finalize, NULL, NULL) != napi_ok) {
    free(handle);
    recycle(ehviewer_compat_env(), image, format);
    napi_throw_error(env, NULL, "can not wrap image handle");
    return NULL;
  }

  /* width/height/byteCount/delay/frameCount/format 走原型上的 getter：
   * 增量解码（partially=true）下这些值会随 complete()/advance() 变化，
   * 写成自有属性会把 getter 遮蔽掉、读到过期值。 */

  return object;
}

static napi_value DecodeInternal(napi_env env, napi_value buffer, bool partially, int expectFormat) {
  void* data = NULL;
  size_t length = 0;
  InputStream* inputStream = NULL;
  void* image = NULL;
  int format = IMAGE_FORMAT_UNKNOWN;

  if (!ehviewer_napi_get_bytes(env, buffer, &data, &length)) {
    napi_throw_error(env, NULL, "argument must be an ArrayBuffer");
    return NULL;
  }
  if (data == NULL || length == 0) {
    napi_throw_error(env, NULL, "empty buffer");
    return NULL;
  }

  inputStream = create_input_stream_from_memory(data, length);
  if (inputStream == NULL) {
    napi_throw_error(env, NULL, "can not create input stream");
    return NULL;
  }

  image = decode(ehviewer_compat_env(), inputStream, partially, &format);
  if (image == NULL) {
    napi_throw_error(env, NULL, "decode failed");
    return NULL;
  }
  if (expectFormat != IMAGE_FORMAT_UNKNOWN && format != expectFormat) {
    recycle(ehviewer_compat_env(), image, format);
    napi_throw_error(env, NULL, "decoded format does not match the requested decoder");
    return NULL;
  }

  return CreateImageObject(env, image, format);
}

static napi_value Decode(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  bool partially = false;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    napi_throw_error(env, NULL, "decode(buffer, partially?)");
    return NULL;
  }
  if (argc >= 2) {
    napi_get_value_bool(env, argv[1], &partially);
  }
  return DecodeInternal(env, argv[0], partially, IMAGE_FORMAT_UNKNOWN);
}

static napi_value DecodeAs(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = { NULL };
  int32_t format = IMAGE_FORMAT_UNKNOWN;
  bool partially = false;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    napi_throw_error(env, NULL, "decodeAs(buffer, format, partially?)");
    return NULL;
  }
  napi_get_value_int32(env, argv[1], &format);
  if (argc >= 3) {
    napi_get_value_bool(env, argv[2], &partially);
  }
  return DecodeInternal(env, argv[0], partially, format);
}

static napi_value CreatePlain(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = { NULL };
  int32_t width = 0, height = 0;
  void* data = NULL;
  size_t length = 0;
  void* image = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 3) {
    napi_throw_error(env, NULL, "createPlain(width, height, pixels)");
    return NULL;
  }
  napi_get_value_int32(env, argv[0], &width);
  napi_get_value_int32(env, argv[1], &height);
  if (!ehviewer_napi_get_bytes(env, argv[2], &data, &length)) {
    napi_throw_error(env, NULL, "pixels must be an ArrayBuffer");
    return NULL;
  }
  if (width <= 0 || height <= 0 || length < (size_t) width * (size_t) height * 4) {
    napi_throw_error(env, NULL, "invalid plain image size");
    return NULL;
  }

  image = create((unsigned int) width, (unsigned int) height, data);
  if (image == NULL) {
    napi_throw_error(env, NULL, "can not create plain image");
    return NULL;
  }
  return CreateImageObject(env, image, IMAGE_FORMAT_PLAIN);
}

static napi_value GetSupportedFormats(napi_env env, napi_callback_info info) {
  int formats[IMAGE_MAX_SUPPORTED_FORMAT_COUNT];
  napi_value array = NULL;
  int count;

  (void) info;

  count = get_supported_formats(formats);
  if (count < 0) {
    count = 0;
  }
  if (count > IMAGE_MAX_SUPPORTED_FORMAT_COUNT) {
    count = IMAGE_MAX_SUPPORTED_FORMAT_COUNT;
  }

  napi_create_array_with_length(env, (size_t) count, &array);
  for (int i = 0; i < count; i++) {
    napi_set_element(env, array, (uint32_t) i, ehviewer_napi_int32(env, formats[i]));
  }
  return array;
}

static napi_value GetDecoderDescription(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  int32_t format = 0;
  const char* description = NULL;
  napi_value result = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    napi_throw_error(env, NULL, "getDecoderDescription(format)");
    return NULL;
  }
  napi_get_value_int32(env, argv[0], &format);
  description = get_decoder_description(format);
  napi_create_string_utf8(env, description == NULL ? "" : description, NAPI_AUTO_LENGTH, &result);
  return result;
}

/* ---------------- 类注册 ---------------- */

napi_value napi_image_init(napi_env env, napi_value exports) {
  napi_property_descriptor methods[] = {
      { "complete", NULL, ImageComplete, NULL, NULL, NULL, napi_default_method, NULL },
      { "isCompleted", NULL, ImageIsCompleted, NULL, NULL, NULL, napi_default_method, NULL },
      { "render", NULL, ImageRender, NULL, NULL, NULL, napi_default_method, NULL },
      { "advance", NULL, ImageAdvance, NULL, NULL, NULL, napi_default_method, NULL },
      { "isOpaque", NULL, ImageIsOpaque, NULL, NULL, NULL, napi_default_method, NULL },
      { "isGray", NULL, ImageIsGray, NULL, NULL, NULL, napi_default_method, NULL },
      { "clahe", NULL, ImageClahe, NULL, NULL, NULL, napi_default_method, NULL },
      { "recycle", NULL, ImageRecycle, NULL, NULL, NULL, napi_default_method, NULL },
      { "getPixels", NULL, ImageGetPixels, NULL, NULL, NULL, napi_default_method, NULL },
      { "width", NULL, NULL, ImageGetWidth, NULL, NULL, napi_default, NULL },
      { "height", NULL, NULL, ImageGetHeight, NULL, NULL, napi_default, NULL },
      { "byteCount", NULL, NULL, ImageGetByteCount, NULL, NULL, napi_default, NULL },
      { "delay", NULL, NULL, ImageGetDelay, NULL, NULL, napi_default, NULL },
      { "frameCount", NULL, NULL, ImageGetFrameCount, NULL, NULL, napi_default, NULL },
      { "format", NULL, NULL, ImageGetFormat, NULL, NULL, napi_default, NULL },
  };
  napi_property_descriptor functions[] = {
      { "decode", NULL, Decode, NULL, NULL, NULL, napi_default, NULL },
      { "decodeAs", NULL, DecodeAs, NULL, NULL, NULL, napi_default, NULL },
      { "createPlain", NULL, CreatePlain, NULL, NULL, NULL, napi_default, NULL },
      { "getSupportedFormats", NULL, GetSupportedFormats, NULL, NULL, NULL, napi_default, NULL },
      { "getDecoderDescription", NULL, GetDecoderDescription, NULL, NULL, NULL, napi_default, NULL },
  };
  napi_value constructor = NULL;

  napi_define_class(env, "NativeImage", NAPI_AUTO_LENGTH, ImageConstructor, NULL,
      sizeof(methods) / sizeof(methods[0]), methods, &constructor);
  napi_create_reference(env, constructor, 1, &g_image_constructor);
  napi_set_named_property(env, exports, "NativeImage", constructor);

  napi_define_properties(env, exports, sizeof(functions) / sizeof(functions[0]), functions);

  return exports;
}
