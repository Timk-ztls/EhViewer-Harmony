/*
 * GL NAPI 绑定（C-1 契约）：ArkTS 侧按 GLNativeBackend 接口调用，
 * 全部符号以 native 前缀注册在 libnative-lib.so 的同一个 module（native-lib）下。
 *
 * 返回码统一 GlErr（0..6），禁止裸 bool（C-1 §2）。
 * 线程：全部在 render 线程调用（C-1 §4）。
 */

#include <stdlib.h>
#include <string.h>

#include "napi_common.h"
#include "../gl/gl_engine.h"

static napi_value make_err(napi_env env, GlErr err) {
  return ehviewer_napi_int32(env, (int32_t) err);
}

/* ---- 生命周期 ---- */

static napi_value NativeInit(napi_env env, napi_callback_info info) {
  (void) info;
  return make_err(env, gl_engine_init());
}

static napi_value NativeSetSurface(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  int32_t width = 0;
  int32_t height = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_int32(env, argv[0], &width);
  napi_get_value_int32(env, argv[1], &height);
  return make_err(env, gl_engine_set_surface(width, height));
}

static napi_value NativeDestroySurface(napi_env env, napi_callback_info info) {
  (void) info;
  return make_err(env, gl_engine_destroy_surface());
}

static napi_value NativePresent(napi_env env, napi_callback_info info) {
  (void) info;
  return make_err(env, gl_engine_present());
}

/* ---- 命令流 ---- */

static napi_value NativeReplay(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  void* data = NULL;
  size_t length = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  if (!ehviewer_napi_get_bytes(env, argv[0], &data, &length)) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  if (length % sizeof(float) != 0) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  return make_err(env, gl_engine_replay((const float*) data, length / sizeof(float)));
}

/* ---- 纹理 ---- */

static napi_value NativeGenTexture(napi_env env, napi_callback_info info) {
  (void) info;
  return ehviewer_napi_int32(env, gl_engine_gen_texture());
}

static napi_value NativeDeleteTexture(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  uint32_t id = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  return make_err(env, gl_engine_delete_texture(id));
}

static napi_value NativeTexImage2D(napi_env env, napi_callback_info info) {
  size_t argc = 6;
  napi_value argv[6] = { NULL };
  uint32_t id = 0;
  int32_t width = 0;
  int32_t height = 0;
  uint32_t format = 0;
  uint32_t type = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 6) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  napi_get_value_int32(env, argv[1], &width);
  napi_get_value_int32(env, argv[2], &height);
  napi_get_value_uint32(env, argv[3], &format);
  napi_get_value_uint32(env, argv[4], &type);
  return make_err(env, gl_engine_tex_image_2d(id, width, height, format, type, env, argv[5]));
}

static napi_value NativeTexSubImage2D(napi_env env, napi_callback_info info) {
  size_t argc = 8;
  napi_value argv[8] = { NULL };
  uint32_t id = 0;
  int32_t xOffset = 0;
  int32_t yOffset = 0;
  int32_t width = 0;
  int32_t height = 0;
  uint32_t format = 0;
  uint32_t type = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 8) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  napi_get_value_int32(env, argv[1], &xOffset);
  napi_get_value_int32(env, argv[2], &yOffset);
  napi_get_value_int32(env, argv[3], &width);
  napi_get_value_int32(env, argv[4], &height);
  napi_get_value_uint32(env, argv[5], &format);
  napi_get_value_uint32(env, argv[6], &type);
  return make_err(env, gl_engine_tex_sub_image_2d(id, xOffset, yOffset, width, height,
      format, type, env, argv[7]));
}

/* 单色填充一块纹理区域（UploadedTexture 的非 2 次幂边框填充，替代上游全零 Bitmap） */
static napi_value NativeTexSubImage2DFill(napi_env env, napi_callback_info info) {
  size_t argc = 8;
  napi_value argv[8] = { NULL };
  uint32_t id = 0;
  int32_t xOffset = 0;
  int32_t yOffset = 0;
  int32_t width = 0;
  int32_t height = 0;
  uint32_t format = 0;
  uint32_t type = 0;
  uint32_t argb = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 8) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  napi_get_value_int32(env, argv[1], &xOffset);
  napi_get_value_int32(env, argv[2], &yOffset);
  napi_get_value_int32(env, argv[3], &width);
  napi_get_value_int32(env, argv[4], &height);
  napi_get_value_uint32(env, argv[5], &format);
  napi_get_value_uint32(env, argv[6], &type);
  /* JS 侧 argb 是 number，语义 0xAARRGGBB（与上游 Color.argb 一致）：0x11223344 → a=11,r=22,g=33,b=44 */
  {
    double value = 0;
    if (napi_get_value_double(env, argv[7], &value) == napi_ok) {
      argb = (uint32_t) (value);
    }
  }
  return make_err(env, gl_engine_tex_sub_image_2d_fill(id, xOffset, yOffset, width, height,
      format, type, argb));
}

/* 区域 blit（C-1 补充）：把 pixelMap 的 [srcX,srcY,srcW,srcH) 贴到纹理 (dstX,dstY)，
 * 允许 dst 为负（越界裁剪），1:1 不缩放。gl-render 的 ImageTexture 分块上传依赖它。 */
static napi_value NativeTexImageRegion(napi_env env, napi_callback_info info) {
  size_t argc = 11;
  napi_value argv[11] = { NULL };
  uint32_t id = 0;
  bool init = false;
  int32_t srcX = 0, srcY = 0, srcW = 0, srcH = 0;
  int32_t dstX = 0, dstY = 0, texW = 0, texH = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 11) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  napi_get_value_bool(env, argv[1], &init);
  napi_get_value_int32(env, argv[3], &srcX);
  napi_get_value_int32(env, argv[4], &srcY);
  napi_get_value_int32(env, argv[5], &srcW);
  napi_get_value_int32(env, argv[6], &srcH);
  napi_get_value_int32(env, argv[7], &dstX);
  napi_get_value_int32(env, argv[8], &dstY);
  napi_get_value_int32(env, argv[9], &texW);
  napi_get_value_int32(env, argv[10], &texH);
  return make_err(env, gl_engine_tex_image_region(id, init, env, argv[2],
      srcX, srcY, srcW, srcH, dstX, dstY, texW, texH));
}
/* ---- 缓冲 ---- */

static napi_value NativeGenBuffer(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  uint32_t target = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    return ehviewer_napi_int32(env, -1);
  }
  napi_get_value_uint32(env, argv[0], &target);
  return ehviewer_napi_int32(env, gl_engine_gen_buffer(target));
}

static napi_value NativeBufferDataF32(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  uint32_t id = 0;
  void* data = NULL;
  size_t length = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  if (!ehviewer_napi_get_bytes(env, argv[1], &data, &length) || length % sizeof(float) != 0) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  return make_err(env, gl_engine_buffer_data_f32(id, (const float*) data, length / sizeof(float)));
}

static napi_value NativeBufferDataU8(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  uint32_t id = 0;
  void* data = NULL;
  size_t length = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  if (!ehviewer_napi_get_bytes(env, argv[1], &data, &length)) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  return make_err(env, gl_engine_buffer_data_u8(id, (const unsigned char*) data, length));
}

static napi_value NativeDeleteBuffer(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  uint32_t id = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  return make_err(env, gl_engine_delete_buffer(id));
}

/* ---- 离屏渲染目标 ---- */

static napi_value NativeGenFramebuffer(napi_env env, napi_callback_info info) {
  (void) info;
  return ehviewer_napi_int32(env, gl_engine_gen_framebuffer());
}

static napi_value NativeBindFramebuffer(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  uint32_t id = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  return make_err(env, gl_engine_bind_framebuffer(id));
}

static napi_value NativeAttachTexture(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value argv[4] = { NULL };
  uint32_t target = 0;
  uint32_t attachment = 0;
  uint32_t texTarget = 0;
  uint32_t textureId = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 4) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &target);
  napi_get_value_uint32(env, argv[1], &attachment);
  napi_get_value_uint32(env, argv[2], &texTarget);
  napi_get_value_uint32(env, argv[3], &textureId);
  return make_err(env, gl_engine_attach_texture(target, attachment, texTarget, textureId));
}

static napi_value NativeDeleteFramebuffer(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  uint32_t id = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    return make_err(env, GL_BAD_ARGUMENT);
  }
  napi_get_value_uint32(env, argv[0], &id);
  return make_err(env, gl_engine_delete_framebuffer(id));
}

static napi_value NativeUnbindFramebuffer(napi_env env, napi_callback_info info) {
  (void) info;
  return make_err(env, gl_engine_unbind_framebuffer());
}

/* ---- 查询 ---- */

static napi_value NativeGlGetError(napi_env env, napi_callback_info info) {
  (void) info;
  return ehviewer_napi_int32(env, gl_engine_get_error());
}

static napi_value NativeGetString(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  uint32_t what = 0;
  napi_value result = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    napi_create_string_utf8(env, "", 0, &result);
    return result;
  }
  napi_get_value_uint32(env, argv[0], &what);
  napi_create_string_utf8(env, gl_engine_get_string(what), NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value napi_gl_init(napi_env env, napi_value exports) {
  napi_property_descriptor functions[] = {
      { "nativeInit", NULL, NativeInit, NULL, NULL, NULL, napi_default, NULL },
      { "nativeSetSurface", NULL, NativeSetSurface, NULL, NULL, NULL, napi_default, NULL },
      { "nativeDestroySurface", NULL, NativeDestroySurface, NULL, NULL, NULL, napi_default, NULL },
      { "nativePresent", NULL, NativePresent, NULL, NULL, NULL, napi_default, NULL },
      { "nativeReplay", NULL, NativeReplay, NULL, NULL, NULL, napi_default, NULL },
      { "nativeGenTexture", NULL, NativeGenTexture, NULL, NULL, NULL, napi_default, NULL },
      { "nativeDeleteTexture", NULL, NativeDeleteTexture, NULL, NULL, NULL, napi_default, NULL },
      { "nativeTexImage2D", NULL, NativeTexImage2D, NULL, NULL, NULL, napi_default, NULL },
      { "nativeTexSubImage2D", NULL, NativeTexSubImage2D, NULL, NULL, NULL, napi_default, NULL },
      { "nativeTexSubImage2DFill", NULL, NativeTexSubImage2DFill, NULL, NULL, NULL, napi_default, NULL },
      { "nativeTexImageRegion", NULL, NativeTexImageRegion, NULL, NULL, NULL, napi_default, NULL },
      { "nativeGenBuffer", NULL, NativeGenBuffer, NULL, NULL, NULL, napi_default, NULL },
      { "nativeBufferDataF32", NULL, NativeBufferDataF32, NULL, NULL, NULL, napi_default, NULL },
      { "nativeBufferDataU8", NULL, NativeBufferDataU8, NULL, NULL, NULL, napi_default, NULL },
      { "nativeDeleteBuffer", NULL, NativeDeleteBuffer, NULL, NULL, NULL, napi_default, NULL },
      { "nativeGenFramebuffer", NULL, NativeGenFramebuffer, NULL, NULL, NULL, napi_default, NULL },
      { "nativeBindFramebuffer", NULL, NativeBindFramebuffer, NULL, NULL, NULL, napi_default, NULL },
      { "nativeAttachTexture", NULL, NativeAttachTexture, NULL, NULL, NULL, napi_default, NULL },
      { "nativeDeleteFramebuffer", NULL, NativeDeleteFramebuffer, NULL, NULL, NULL, napi_default, NULL },
      { "nativeUnbindFramebuffer", NULL, NativeUnbindFramebuffer, NULL, NULL, NULL, napi_default, NULL },
      { "nativeGlGetError", NULL, NativeGlGetError, NULL, NULL, NULL, napi_default, NULL },
      { "nativeGetString", NULL, NativeGetString, NULL, NULL, NULL, napi_default, NULL },
  };

  napi_define_properties(env, exports, sizeof(functions) / sizeof(functions[0]), functions);

  /* XComponent 回调：页面挂载时会带 __NATIVE_XCOMPONENT_OBJ__ 过来，未挂载返回 NOT_READY 不致命 */
  gl_engine_register_xcomponent(env, exports);

  return exports;
}



