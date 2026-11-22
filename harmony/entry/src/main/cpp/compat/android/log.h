/*
 * OHOS compat: <android/log.h> → hilog。
 *
 * 上游自研解码层通过 log.h 调用 __android_log_print。鸿蒙侧把它桥接到
 * OH_LOG_VPrint（libhilog_ndk.z.so），优先级映射保持 Android 语义，
 * 日志内容与格式字符串原样透传，便于和上游日志逐行对照。
 *
 * 本文件为鸿蒙侧新增（见 inventory/native-image.extra.txt）。
 */
#ifndef EHVIEWER_COMPAT_ANDROID_LOG_H
#define EHVIEWER_COMPAT_ANDROID_LOG_H

#include <stdarg.h>

#include <hilog/log.h>

/* Android 日志优先级常量（与 android/log.h 取值一致） */
typedef enum android_LogPriority {
  ANDROID_LOG_UNKNOWN = 0,
  ANDROID_LOG_DEFAULT,
  ANDROID_LOG_VERBOSE,
  ANDROID_LOG_DEBUG,
  ANDROID_LOG_INFO,
  ANDROID_LOG_WARN,
  ANDROID_LOG_ERROR,
  ANDROID_LOG_FATAL,
  ANDROID_LOG_SILENT
} android_LogPriority;

/* hilog 域号：0x0000~0xFFFF 为可用范围，取 0xE001 作为本模块专用域 */
#ifndef EHVIEWER_LOG_DOMAIN
#define EHVIEWER_LOG_DOMAIN 0xE001
#endif

static inline LogLevel ehviewer_log_level(int prio) {
  switch (prio) {
    case ANDROID_LOG_VERBOSE:
    case ANDROID_LOG_DEBUG:
      return LOG_DEBUG;
    case ANDROID_LOG_INFO:
      return LOG_INFO;
    case ANDROID_LOG_WARN:
      return LOG_WARN;
    case ANDROID_LOG_FATAL:
      return LOG_FATAL;
    case ANDROID_LOG_SILENT:
      return LOG_FATAL;
    default:
      return LOG_ERROR;
  }
}

static inline int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  OH_LOG_VPrint(LOG_APP, ehviewer_log_level(prio), EHVIEWER_LOG_DOMAIN, tag, fmt, ap);
  va_end(ap);
  return 0;
}

#define __android_log_vprint(prio, tag, fmt, ap) \
  OH_LOG_VPrint(LOG_APP, ehviewer_log_level(prio), EHVIEWER_LOG_DOMAIN, (tag), (fmt), (ap))

#endif /* EHVIEWER_COMPAT_ANDROID_LOG_H */
