/*
 * NAPI 胶水层公共工具（鸿蒙侧新增，见 inventory/native-image.extra.txt）。
 */
#ifndef EHVIEWER_NAPI_COMMON_H
#define EHVIEWER_NAPI_COMMON_H

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

#include <napi/native_api.h>

#include "jni.h"

/* 兼容层：解码层需要透传一个 JNIEnv*，鸿蒙侧用常量 token 代替真实 JVM 环境 */
JNIEnv* ehviewer_compat_env(void);

#define EHVIEWER_NAPI_CALL(env, call, ret)                       \
  do {                                                           \
    napi_status status_ = (call);                                \
    if (status_ != napi_ok) {                                    \
      const napi_extended_error_info* info_ = NULL;              \
      napi_get_last_error_info((env), &info_);                   \
      napi_throw_error((env), NULL,                              \
          info_ != NULL && info_->error_message != NULL          \
              ? info_->error_message                             \
              : "napi call failed");                             \
      return ret;                                                \
    }                                                            \
  } while (0)

/* 读取 ArrayBuffer / TypedArray 的底层字节 */
static inline bool ehviewer_napi_get_bytes(napi_env env, napi_value value,
                                           void** data, size_t* length) {
  bool isArrayBuffer = false;
  napi_status status = napi_is_arraybuffer(env, value, &isArrayBuffer);
  if (status == napi_ok && isArrayBuffer) {
    return napi_get_arraybuffer_info(env, value, data, length) == napi_ok;
  }

  napi_typedarray_type type;
  size_t elements = 0;
  napi_value arrayBuffer = NULL;
  size_t offset = 0;
  status = napi_get_typedarray_info(env, value, &type, &elements, data, &arrayBuffer, &offset);
  if (status != napi_ok) {
    return false;
  }

  size_t bytesPerElement = 1;
  switch (type) {
    case napi_int16_array:
    case napi_uint16_array:
      bytesPerElement = 2;
      break;
    case napi_int32_array:
    case napi_uint32_array:
    case napi_float32_array:
      bytesPerElement = 4;
      break;
    case napi_float64_array:
    case napi_bigint64_array:
    case napi_biguint64_array:
      bytesPerElement = 8;
      break;
    default:
      bytesPerElement = 1;
      break;
  }

  size_t rawLength = elements * bytesPerElement;
  napi_value byteLenProp = NULL;
  uint32_t jsByteLen = 0;
  if (napi_get_named_property(env, value, "byteLength", &byteLenProp) == napi_ok &&
      napi_get_value_uint32(env, byteLenProp, &jsByteLen) == napi_ok) {
    rawLength = (size_t)jsByteLen;
  }
  size_t abLength = 0;
  void* abData = NULL;
  if (arrayBuffer != NULL &&
      napi_get_arraybuffer_info(env, arrayBuffer, &abData, &abLength) == napi_ok) {
    if (offset > abLength) {
      return false;
    }
    size_t maxAvail = abLength - offset;
    if (rawLength > maxAvail) {
      rawLength = maxAvail;
    }
  }
  *length = rawLength;
  return true;
}

/* 生成零拷贝的外部 ArrayBuffer（生命周期由 finalize 回调管理，此处不接管） */
static inline napi_value ehviewer_napi_external_buffer(napi_env env, void* data, size_t length) {
  napi_value result = NULL;
  if (napi_create_external_arraybuffer(env, data, length, NULL, NULL, &result) != napi_ok) {
    return NULL;
  }
  return result;
}

static inline napi_value ehviewer_napi_uint32(napi_env env, uint32_t value) {
  napi_value result = NULL;
  napi_create_uint32(env, value, &result);
  return result;
}

static inline napi_value ehviewer_napi_int32(napi_env env, int32_t value) {
  napi_value result = NULL;
  napi_create_int32(env, value, &result);
  return result;
}

static inline napi_value ehviewer_napi_bool(napi_env env, bool value) {
  napi_value result = NULL;
  napi_get_boolean(env, value, &result);
  return result;
}

#endif /* EHVIEWER_NAPI_COMMON_H */
