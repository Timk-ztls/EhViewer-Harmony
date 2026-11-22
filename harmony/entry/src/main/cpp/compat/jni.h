/*
 * OHOS compat: <jni.h> 最小替身。
 *
 * 上游 cpp/jni/{image,stream} 的自研解码层沿用了 JNI 时代的签名（到处透传 JNIEnv*），
 * 实际只在 java_wrapper.c 里真正调用 JVM。鸿蒙侧没有 JVM，这里提供最小类型集合，
 * 让解码层源码保持零改动编译；JNIEnv 只是一个不透明占位指针，
 * obtain_env()/release_env() 在 napi/napi_module.c 中实现为常量 token。
 *
 * 本文件为鸿蒙侧新增（见 inventory/native-image.extra.txt），不属于 vendored 库。
 */
#ifndef EHVIEWER_COMPAT_JNI_H
#define EHVIEWER_COMPAT_JNI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int8_t   jbyte;
typedef int32_t  jint;
typedef int64_t  jlong;
typedef uint8_t  jboolean;
typedef uint16_t jchar;
typedef int16_t  jshort;
typedef float    jfloat;
typedef double   jdouble;

typedef void* jobject;
typedef void* jclass;
typedef void* jstring;
typedef void* jarray;
typedef void* jbyteArray;
typedef void* jmethodID;
typedef void* jfieldID;

typedef struct ehviewer_compat_jnienv {
  int unused;
} *JNIEnv;

#ifndef JNIEXPORT
#define JNIEXPORT
#endif
#ifndef JNICALL
#define JNICALL
#endif

#define JNI_TRUE  1
#define JNI_FALSE 0

#define JNI_OK          0
#define JNI_EDETACHED (-2)
#define JNI_EVERSION  (-3)
#define JNI_VERSION_1_6 0x00010006

#ifdef __cplusplus
}
#endif

#endif /* EHVIEWER_COMPAT_JNI_H */
