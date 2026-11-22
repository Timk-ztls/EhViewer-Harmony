# cpp/7z —— 7-Zip LZMA SDK 24.09 最小提取子集

D-004 裁决（Lead 2026-10-24）：**方案 A = NDK 编译 7-Zip C 源码 + NAPI 封装，与 `cpp/` 同构建体系**。
本目录即该裁决的 vendored 依赖。

## 来源与版本（可审计）

| 项 | 值 |
|---|---|
| 上游 | https://github.com/ip7z/7zip |
| 版本 | **24.09**（tag） |
| 路径 | `C/` 目录下的最小闭包（见下表） |
| 获取方式 | 逐文件 `https://raw.githubusercontent.com/ip7z/7zip/24.09/C/<name>` |
| 改动 | **零**。35 个 .c/.h 原样放入，未修改任何一行；唯一的"配置"在同目录 `CMakeLists.txt` 里（`-D_7ZIP_ST` + 告警抑制） |
| 校验 | 每个文件 `SHA-256` 见文末；重新拉取后可逐行比对 |

## 为什么是最小子集

只覆盖 **7z 解压**所需闭包：归档解析（`7zArcIn.c`）+ LZMA/LZMA2/PPMd7 解码 + BCJ/BCJ2/Delta 过滤器 +
CRC32/SHA-256/AES + 内存分配与 CPU 特性探测。
**不含**：编码器（`LzmaEnc.c`/`Lzma2Enc.c`/`Ppmd7Enc.c`）、xz（`Xz*.c`）、7z 写出（`7zDec.c` 之外的写出路径）、
`7zMain.c` 示例、`Util/` 命令行工具、`Asm/` 汇编优化（arm64 走 `CpuArch.c` 的通用路径）。

## 文件清单（35 + Precomp.h + 5 个补头 = 41）

```
7zTypes.h 7z.h 7zArcIn.c 7zAlloc.c 7zAlloc.h 7zBuf.c 7zBuf.h
7zCrc.c 7zCrc.h 7zCrcOpt.c 7zCrcEmu.h(仅调试分支引用，见注) 7zStream.c 7zFile.c 7zFile.h
7zWindows.h Precomp.h Compiler.h RotateDefs.h
Alloc.c Alloc.h Bra.c Bra.h Bra86.c Bcj2.c Bcj2.h
CpuArch.c CpuArch.h Delta.c Delta.h
Lzma2Dec.c Lzma2Dec.h LzmaDec.c LzmaDec.h
Ppmd.h Ppmd7.c Ppmd7.h Ppmd7Dec.c
Sha256.c Sha256.h Aes.c Aes.h
```

注：`7zCrc.c` 里 `#include "7zCrcEmu.h"` 只在 `#ifdef Z7_CRC_HW_USE`（调试用宏）下生效，
24.09 未随包提供该头文件，正常构建不会引用；因此**不需要**补它。

## 许可

- LZMA SDK 主体（`LzmaDec.*`、`Lzma2Dec.*`、`7z*.c`、`Alloc.*`、`CpuArch.*` 等）：**public domain**
- 部分过滤器/加密实现沿用 7-Zip 的混合许可（public domain + GNU LGPL 条款），以各文件头注释为准
- 结论：可随本工程分发；**许可证说明条目由 Lead 写进 `DEVIATIONS.md`**（D-004）

## 集成方式

顶层 `harmony/entry/src/main/cpp/CMakeLists.txt`：

```cmake
option(EHVIEWER_7Z "Enable 7z extraction (D-004)" OFF)
if(EHVIEWER_7Z)
  target_compile_definitions(native-lib PRIVATE EHVIEWER_7Z=1)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/7z/7zTypes.h")
    add_subdirectory(7z)                 # 产出静态库 lzma7z
    target_link_libraries(native-lib PRIVATE lzma7z)
  else()
    message(FATAL_ERROR "EHVIEWER_7Z=ON 但 cpp/7z 不存在")
  endif()
endif()
```

开关关闭时（默认）：`napi/napi_7z.c` 不引用任何 7z 头文件，`extract7z()` 抛 `7001`（未编译），
**不存在纯 JS 假实现**。

## NAPI 接口（`ets/native/index.d.ts`）

```ts
extract7z(archive: ArrayBuffer, outDir: string, password?: string): number   // 返回解压出的文件数
```

错误码：`7001` 未编译 · `7002` 参数非法 · `7003` 解压失败（7z 的 SRes 一并带在 message 里）·
`7004` 口令错误/需要口令（24.09 的 `SzArEx` 简化 API 不支持口令，带口令归档一律走 7004 并在 message 说明）

## SHA-256（下载校验用）

见 `SHA256SUMS`（同目录）。
