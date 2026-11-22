/*
 * NAPI 模块入口（鸿蒙侧新增，见 inventory/native-image.extra.txt）。
 *
 * 上游以两个 JNI .so 暴露能力：
 *   libimage.so   (jni/image/java_wrapper.c)  → com.hippo.lib.image.Image / Image1
 *   libehviewer.so(cpp/image.c, gifutils.c, fdutils.c, gif/native-lib.cpp)
 *                                              → ImageDecoder_wrapper / GifHandler / Native.getFd
 * 鸿蒙侧统一为单产物 libnative-lib.so，模块名 native_image，
 * 由 napi_module_register 注册（ArkTS 侧 import nativeImage from 'libnative-lib.so'）。
 *
 * 同时提供 obtain_env()/release_env() 的鸿蒙实现：解码层源码保持 JNI 时代的签名，
 * 这两个符号在上游由 java_wrapper.c 提供，鸿蒙侧没有 JVM，返回常量 token 即可
 * （解码层从不解引用 env，仅透传）。
 */

#include <stdbool.h>

#include "napi_common.h"
#include "../jni/image/java_wrapper.h"

/*
 * 模块名必须是 .so 文件名去掉 "lib" 前缀与 ".so" 后缀（OHOS NAPI 加载器按此匹配）：
 *   ArkTS: import nativeImage from 'libnative-lib.so'  ←→  nm_modname = "native-lib"
 * 用 "native_image" 会在 import 时报 module not registered。
 * C-1 契约要求 GL 符号注册在同一个 module 下，后续 cpp/gl/ 的 native* 函数
 * 由同一份 Init() 挂到同一个 exports 对象上。
 */
#define EHVIEWER_NAPI_MODULE_NAME "native-lib"

napi_value napi_image_init(napi_env env, napi_value exports);
napi_value napi_gif_init(napi_env env, napi_value exports);
napi_value napi_gifutils_init(napi_env env, napi_value exports);
napi_value napi_7z_init(napi_env env, napi_value exports);
napi_value napi_zip_init(napi_env env, napi_value exports);
napi_value napi_gl_init(napi_env env, napi_value exports);

/* 解码层透传用的 JNIEnv 占位 token（永不解引用） */
static struct ehviewer_compat_jnienv g_compat_env;

JNIEnv* ehviewer_compat_env(void) {
  return &g_compat_env;
}

JNIEnv* obtain_env(bool* attach) {
  if (attach != NULL) {
    *attach = false; /* 鸿蒙侧无「附加到 JVM」概念，恒定 false */
  }
  return ehviewer_compat_env();
}

void release_env() {
  /* no-op：无 JVM 线程需要 detach */
}

static napi_value Init(napi_env env, napi_value exports) {
  napi_image_init(env, exports);
  napi_gif_init(env, exports);
  napi_gifutils_init(env, exports);
  napi_7z_init(env, exports);
  napi_zip_init(env, exports);
  /* C-1 契约：GL 的 native* 符号与图片解码共用同一个 module（native-lib） */
  napi_gl_init(env, exports);

  return exports;
}

static napi_module g_native_image_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = NULL,
    .nm_register_func = Init,
    .nm_modname = EHVIEWER_NAPI_MODULE_NAME,
    .nm_priv = NULL,
    .reserved = { 0 },
};

extern __attribute__((constructor)) void RegisterNativeImageModule(void) {
  napi_module_register(&g_native_image_module);
}
