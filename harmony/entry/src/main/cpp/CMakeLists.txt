# EhViewer → HarmonyOS: native-image 顶层构建脚本
#
# 与上游 app/src/main/cpp/CMakeLists.txt 的对应关系（逐条差异见 MR）：
#   上游：project("ehviewer") + add_subdirectory(jni) + add_library(ehviewer SHARED ...)
#         链接 jnigraphics / GLESv2 / log（Android 专有）
#   鸿蒙：project("ehviewer") + add_subdirectory(jni) + add_library(native-lib SHARED ...)
#         链接 hilog（libhilog_ndk.z.so），产物固定为 libnative-lib.so
#
# 上游 libehviewer.so 的 5 个源文件在鸿蒙侧的去向：
#   gifutils.c      → napi/napi_gifutils.c（rewriteGifSource 语义等价）
#   fdutils.c       → 不再需要（ArkTS 侧可直接拿到文件 fd 并传给 NAPI）
#   image.c         → Android Bitmap/DataSpace/GLUtils 专有，由 napi/napi_image.c 承接
#   gif/native-lib.cpp → napi/napi_gif.c（GifDecoder 状态机，绘制逻辑逐行保留）
#   gif/dgif_lib.c, gif/gifalloc.c → 由 jni/giflib 的 vendored 实现统一提供

cmake_minimum_required(VERSION 3.18.1)

project("ehviewer" C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)

# OHOS NDK 的 ohos.toolchain.cmake 只定义 OHOS_ARCH，不定义 ANDROID_ABI。
# 上游各 vendored CMakeLists 用 ${ANDROID_ABI} 做 ABI 分支，这里统一折算成 EH_ABI，
# 使 vendored 库的 CMake 只需把 ANDROID_ABI 换成 EH_ABI（最小改动，逐文件记录）。
if(NOT DEFINED EH_ABI)
  if(OHOS_ARCH)
    set(EH_ABI "${OHOS_ARCH}")
  elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
    set(EH_ABI "arm64-v8a")
  elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "arm")
    set(EH_ABI "armeabi-v7a")
  elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
    set(EH_ABI "x86_64")
  else()
    set(EH_ABI "${CMAKE_SYSTEM_PROCESSOR}")
  endif()
endif()

message(STATUS "EhViewer native-image: EH_ABI=${EH_ABI} OHOS_ARCH=${OHOS_ARCH}")

# 本期只构建 arm64-v8a（其余 ABI 待 Lead 决定后开启）
if(NOT EH_ABI STREQUAL "arm64-v8a")
  message(WARNING "native-image 当前只验证 arm64-v8a，本次构建 EH_ABI=${EH_ABI}")
endif()

add_subdirectory(jni)

# ---- NAPI 胶水层 + 统一产物 ----
add_library(native-lib SHARED
    napi/napi_module.c
    napi/napi_image.c
    napi/napi_gif.c
    napi/napi_gifutils.c
    napi/napi_7z.c
    napi/napi_zip.c
    napi/napi_gl.c
    gl/gl_engine.c
)

target_include_directories(native-lib PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/compat
    ${CMAKE_CURRENT_SOURCE_DIR}/napi
    ${CMAKE_CURRENT_SOURCE_DIR}/jni
    ${CMAKE_CURRENT_SOURCE_DIR}/jni/image
    ${CMAKE_CURRENT_SOURCE_DIR}/jni/stream
)

# 16KB 页对齐（与上游一致的链接参数）
# --exclude-libs,ALL + -fvisibility=hidden：vendored 库的全局符号（DGifCloseFile、png_*、
# jpeg_* 等 800+ 个）不进动态符号表，避免与其它 .so 的同名符号互相干扰
target_link_options(native-lib PRIVATE
    -Wl,-z,max-page-size=16384
    -Wl,--exclude-libs,ALL
)
target_compile_options(native-lib PRIVATE -fvisibility=hidden)

target_link_libraries(native-lib PRIVATE
    image
    stream
    libpng
    libjpeg-turbo
    libwebp
    giflib
    hilog_ndk.z
    z
    # C-1 GL 边界：EGL/GLES3 由 NDK 提供；XComponent 回调在 libace_ndk.z.so；
    # PixelMap 的 napi↔native 转换在 libpixelmap_ndk.z.so，native window 在 libnative_window.so
    EGL
    GLESv3
    ace_ndk.z
    native_window
    pixelmap
    # NAPI 运行时（napi_module_register / napi_* 系列符号由系统提供）
    ace_napi.z
)

# 联调开关：把每条 replay 记录落到 hilog（格式 "GLTRACE op=<n> argc=<n> a=..."），
# 用于和 gl-render 的命令流录制器逐条对账。默认关，零运行时开销。
option(EHVIEWER_GL_TRACE "Log every GL replay command to hilog" OFF)
if(EHVIEWER_GL_TRACE)
  target_compile_definitions(native-lib PRIVATE EHVIEWER_GL_TRACE=1)
endif()

# 7z（D-004）：7-Zip 24.09 最小子集已 vendor 到 cpp/7z/，默认关闭；
option(EHVIEWER_7Z "Enable 7z extraction (D-004)" OFF)
if(EHVIEWER_7Z)
  target_compile_definitions(native-lib PRIVATE EHVIEWER_7Z=1)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/7z/7zTypes.h")
    add_subdirectory(7z)
    target_link_libraries(native-lib PRIVATE lzma7z)
  else()
    message(FATAL_ERROR "EHVIEWER_7Z=ON 但 ${CMAKE_CURRENT_SOURCE_DIR}/7z 不存在")
  endif()
endif()
