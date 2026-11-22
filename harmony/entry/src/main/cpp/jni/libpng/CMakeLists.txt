# Copyright 2018 Hippo Seven
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

cmake_minimum_required(VERSION 3.14)
project(libpng C)

set(LIBPNG_SOURCES
    libpng/png.c
    libpng/pngerror.c
    libpng/pngget.c
    libpng/pngmem.c
    libpng/pngpread.c
    libpng/pngread.c
    libpng/pngrio.c
    libpng/pngrtran.c
    libpng/pngrutil.c
    libpng/pngset.c
    libpng/pngtrans.c
)
set(LIBPNG_INCLUDES
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/libpng
)
set(LIBPNG_DEFINITIONS)
# OHOS 差异：pnglibconf.h 里 PNG_CONSOLE_IO_SUPPORTED 打开、PNG_STDIO_SUPPORTED 关闭，
# 于是 pngerror.c 的 fprintf(stderr, ...) 拿不到 <stdio.h>（OH NDK clang 15 直接报
# "use of undeclared identifier 'stderr'"）。补上 PNG_STDIO_SUPPORTED 让 pngconf.h 引入
# <stdio.h>；它只额外暴露 png_init_io/png_set_read_fn 等 FILE* 入口，不影响解码路径。
set(LIBPNG_DEFINITIONS -DPNG_STDIO_SUPPORTED)
set(LIBPNG_LIBRARIES z)

if (EH_ABI STREQUAL "armeabi-v7a")

  # OHOS 说明：v7a 分支本轮不构建、未验证（cpufeatures 子工程未纳入）。
  # 仅把 ABI 变量名换成 EH_ABI 以保持脚本可解析。

  enable_language(ASM)

  set(LIBPNG_SOURCES
      ${LIBPNG_SOURCES}
      libpng/arm/arm_init.c
      libpng/arm/filter_neon.S
  )
  set(LIBPNG_INCLUDES
      ${LIBPNG_INCLUDES}
      ${ANDROID_NDK}/sources/android/cpufeatures
  )
  set(LIBPNG_DEFINITIONS
      ${LIBPNG_DEFINITIONS}
      -DPNG_ARM_NEON_API_SUPPORTED
      -DPNG_ARM_NEON_CHECK_SUPPORTED
      -DPNG_ARM_NEON_OPT=1
      -DPNG_ARM_NEON_IMPLEMENTATION=2
      -DPNG_ARM_NEON_FILE=\"contrib/arm-neon/android-ndk.c\"
  )
  set(LIBPNG_LIBRARIES
      ${LIBPNG_LIBRARIES}
      cpufeatures
  )

elseif (EH_ABI STREQUAL "arm64-v8a")

  # OHOS 差异：arm64 恒有 NEON，去掉 PNG_ARM_NEON_CHECK_SUPPORTED（运行时探测）
  # 与 PNG_ARM_NEON_FILE（android-ndk.c 依赖 NDK 的 cpu-features.h），
  # 因而也不再链接 cpufeatures。NEON 实现固定走 intrinsics（IMPLEMENTATION=1），
  # 与上游 arm64 分支的滤镜实现完全一致。
  enable_language(ASM)

  set(LIBPNG_SOURCES
      ${LIBPNG_SOURCES}
      libpng/arm/arm_init.c
      libpng/arm/filter_neon_intrinsics.c
      libpng/arm/palette_neon_intrinsics.c
  )
  set(LIBPNG_DEFINITIONS
      ${LIBPNG_DEFINITIONS}
      -DPNG_ARM_NEON_OPT=1
      -DPNG_ARM_NEON_IMPLEMENTATION=1
  )

endif ()

add_library(libpng STATIC ${LIBPNG_SOURCES})
target_include_directories(libpng PUBLIC ${LIBPNG_INCLUDES})
target_compile_definitions(libpng PRIVATE ${LIBPNG_DEFINITIONS})
target_link_libraries(libpng PRIVATE ${LIBPNG_LIBRARIES})
