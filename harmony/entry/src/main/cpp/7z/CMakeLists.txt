# 7-Zip LZMA SDK 24.09 —— 最小提取子集（D-004 方案 A）
#
# 来源：https://github.com/ip7z/7zip  tag 24.09 的 C/ 目录（逐文件原样下载，未改动一行）
# 许可：public domain（LZMA SDK）+ 个别文件混合许可，详见同目录 README.md
# 用途：只编译 7z 解压所需的最小闭包，不编译编码器、xz、ppmd 编码等无关部分
#
# 只在本子工程被 add_subdirectory 时才需要存在；顶层 CMake 用
#   -DEHVIEWER_7Z=ON 且 cpp/7z/7zTypes.h 存在 才进入这里

cmake_minimum_required(VERSION 3.18.1)
project(lzma7z C)

set(LZMA7Z_SOURCES
    7zArcIn.c     # 7z 归档解析（CSzArEx / SzArEx_Open / SzArEx_Extract）
    7zDec.c       # SzAr_DecodeFolder：实际解码 solid block（SzArEx_Extract 依赖）
    7zAlloc.c     # SzAlloc / SzFree
    7zBuf.c       # CBuf 辅助
    7zCrc.c       # CRC32 表
    7zCrcOpt.c    # CRC32 优化实现
    7zFile.c      # 文件流（FileInStream，备用：内存流不可用时）
    7zStream.c    # 通用流辅助
    Alloc.c       # 内存分配封装
    Bra.c         # x86 BCJ 过滤器
    Bra86.c       # x86 BCJ 具体实现
    Bcj2.c        # x86 BCJ2 过滤器
    CpuArch.c     # CPU 特性探测（NEON/CRC 加速）
    Delta.c       # Delta 过滤器
    Lzma2Dec.c    # LZMA2 解码器
    LzmaDec.c     # LZMA 解码器
    Ppmd7.c       # PPMd7 解码器核心
    Ppmd7Dec.c    # PPMd7 解码入口
    Sha256.c      # 7z 头校验
    Aes.c         # 加密归档支持（口令归档的解码路径）
)

add_library(lzma7z STATIC ${LZMA7Z_SOURCES})

target_include_directories(lzma7z PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# _7ZIP_ST：单线程构建（不引入 7-Zip 的 MT 调度器，鸿蒙侧由 NAPI 调用方控制线程）
target_compile_definitions(lzma7z PRIVATE _7ZIP_ST)

# 7-Zip 的 C 代码在 -Wextra 下有大量历史告警；只保留硬错误，避免污染本模块构建日志
target_compile_options(lzma7z PRIVATE -Wno-unused-parameter -Wno-sign-compare -Wno-implicit-fallthrough)

