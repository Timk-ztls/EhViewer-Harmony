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
project(image C)

# OHOS 差异（相对上游）：
#   1) 去掉 java_wrapper.c：它是纯 JNI 入口（FindClass/NewObject/jnigraphics），
#      鸿蒙侧由 napi/napi_image.c 承接同一批函数语义；文件本体原样保留在树内作参照。
#   2) add_library 由 SHARED 改为 STATIC：鸿蒙侧只产出 libnative-lib.so，
#      内部子系统统一静态链接进单产物。
#   3) 去掉 log / jnigraphics / GLESv2：Android 专有；日志改由 compat/android/log.h
#      桥接 hilog，Bitmap 由 ArkTS PixelMap 侧承接。

set(IMAGE_SOURCES
        image.c
        image_utils.c
        image_plain.c
        image_jpeg.c
        image_png.c
        image_gif.c
        image_webp.c
        filter/clahe.c
        filter/gray.c
)
#set(IMAGE_INCLUDES
#    ${CMAKE_CURRENT_SOURCE_DIR}
#    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../javah
#)
set(IMAGE_LIBRARIES
        stream
        libjpeg-turbo
        libpng
        giflib
        libwebp
)

add_library(image STATIC ${IMAGE_SOURCES})
target_include_directories(image PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/../libwebp/src
        ${CMAKE_CURRENT_SOURCE_DIR}/../../compat
)

# 确保生成的 libimage.so 在 16KB 页大小设备上 LOAD 段按 16KB 对齐
target_link_options(image PRIVATE
        -Wl,-z,max-page-size=16384
)
target_link_libraries(image PRIVATE ${IMAGE_LIBRARIES})
