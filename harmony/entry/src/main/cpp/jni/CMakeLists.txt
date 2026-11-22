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

# OHOS 差异（相对上游）：
#   1) 去掉 add_subdirectory(cpufeatures)：该子工程编译的是
#      ${ANDROID_NDK}/sources/android/cpufeatures/cpu-features.c，OH NDK 不提供；
#      arm64 上 NEON 恒定存在，libpng 不需要运行时探测（见 libpng/CMakeLists.txt 说明）。
#   2) 其余子工程顺序与上游一致，语义不变。

cmake_minimum_required(VERSION 3.18.1)
project(root)

add_subdirectory(stream)
add_subdirectory(libjpeg-turbo)
add_subdirectory(libpng)
add_subdirectory(giflib)
add_subdirectory(libwebp)
add_subdirectory(image)
