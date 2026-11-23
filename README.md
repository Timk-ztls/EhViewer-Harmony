# EhViewer for HarmonyOS

[![CI](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml/badge.svg)](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml)

基于上游 **EhViewer**（[xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) / [seven332/EhViewer](https://github.com/seven332/EhViewer)）移植实现的 **HarmonyOS NEXT / OpenHarmony（API 20）** 原生客户端，使用 ArkTS + ArkUI 与 C++ NAPI 原生层开发。

## 主要特性

- **画廊浏览与筛选**：首页列表、热门、订阅（Subscription）、Toplist、快速搜索、收藏夹与本地标签筛选。
- **搜索与标签系统**：高级搜索、图片以图搜图、EhTagDatabase 标签翻译自动更新与本地缓存。
- **画廊详情与评论**：完整详情展示、预览图、多标签组、评分/收藏操作、评论列表与发表。
- **原生阅读器**：
  - 支持从左到右 / 从右到左（日漫）分页及纵向长图模式，1:1 跟手滑动与左/右点击翻页并存，双指/双击缩放与音量键翻页。
  - 支持单页下载环形进度与百分比显示，自动适配无 `Content-Length` 分块响应。
  - 支持阅读进度记忆与列表/详情页联动同步。
- **下载管理与本地归档阅读**：
  - 后台下载调度、下载标签管理、Wi-Fi 局域网传输。
  - 内置 C++ `zlib` 流式解压与 `@kit.BasicServicesKit` 回退，支持打开本地 `.zip` / `.cbz` / `.7z` 归档（RAR/CBR 暂不支持，见 `DEVIATIONS.md` D-079）。
- **隐私与外观**：
  - 隐私保护模式（通过 `ohos.permission.PRIVACY_WINDOW` 拦截截屏/录屏，冷启动首帧与切前台即时生效）。
  - Material 风格多主题配色与浅色/深色系统状态栏联动。
  - 支持数据库与收藏/配置导入导出（RDB 存储）。

## 环境要求

- **DevEco Studio**（支持 HarmonyOS SDK API 20 / `6.0.0(20)`，已配置 `hvigorw` 与 Command Line Tools）
- **JDK**（Java 17+，用于 HAP 打包与可选签名）
- **Node.js**（随 DevEco Studio 或系统安装，用于 TypeScript / 单元测试）
- **PowerShell 7+** (`pwsh`)，用于运行辅助构建脚本、代码门禁检查及单元测试

## 构建与签名说明

本仓库刻意将 `harmony/build-profile.json5` 中的 `signingConfigs` 置空为 `[]`，且不包含任何开发者证书、私钥或 `.p7b` Profile 文件。克隆后可直接完成**未签名构建**：

### 方式一：DevEco Studio（推荐真机运行）

1. 使用 DevEco Studio 打开仓库内的 `harmony/` 目录。
2. 等待 Sync 完成，通过 **File → Project Structure → Signing Configs** 勾选 **Automatically generate signature**（自动生成调试签名）。
3. （可选）如需修改包名（默认 `com.ehviewer.harmony`），请同步修改以下位置并重新生成签名 Profile：
   - `harmony/AppScope/app.json5`（`bundleName`）
   - `harmony/entry/src/main/resources/base/profile/shortcuts_config.json`（两处 `bundleName`）
   - `harmony/entry/src/main/ets/hippo/ehviewer/download/DownloadService.ets` 与 `ArchiverDownloadService.ets` 中的默认回退 `bundleName`
4. 点击 **Run** 或 **Build → Build Hap(s)/APP(s) → Build Hap(s)**。

### 方式二：命令行构建

```powershell
# 设置 SDK 与 JDK 环境变量（未设置时 build_hap.ps1 会尝试自动探测常见路径）
$env:DEVECO_SDK_HOME = "$env:LOCALAPPDATA\Huawei\Sdk"
$env:JAVA_HOME = "C:\Program Files\Java\jdk-21"

# 使用 hvigorw 直接构建未签名 debug 或 release HAP
cd harmony
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release --no-daemon

# 或使用封装脚本（若 harmony/signing/ 下未放置签名材料，会自动保留未签名 HAP）
pwsh -File scripts/build_hap.ps1
```

未签名产物默认位于：
`harmony/entry/build/default/outputs/default/entry-default-unsigned.hap`

如需通过脚本完成本地离线签名，可在本地自行创建被 `.gitignore` 忽略的 `harmony/signing/` 目录并放入 `.cer`、`.p7b`、`.p12` 及密钥口令（`keystore-password.txt` 或设置环境变量 `HAP_SIGN_PASSWORD`）后运行 `pwsh -File scripts/build_hap.ps1`。

## 单元测试与静态检查

```powershell
# 首次运行（或无 DevEco 环境时）先初始化 TypeScript 与 @ohos.* / @kit.* 测试桩
pwsh -File scripts/setup_tscheck.ps1

# 运行全量单元测试套件
pwsh -File scripts/run_all_tests.ps1

# 静态门禁检查
pwsh -File scripts/check_line_endings.ps1 -Gate
pwsh -File scripts/check_contrast.ps1 -Gate
pwsh -File scripts/check_contrast.ps1 -Path harmony/entry/src/main/ets/hippo/ehviewer/widget -Gate
pwsh -File scripts/check_silent_failures.ps1 -Gate
pwsh -File scripts/check_resource_keys.ps1 -Gate
```

## 目录结构

```text
.
├── .github/workflows/ci.yml  # GitHub Actions 自动化门禁与单测流水线（windows-latest）
├── harmony/                  # DevEco Studio / Hvigor 主工程（AppScope + entry 模块）
│   ├── AppScope/             # 全局 app.json5（默认包名 com.ehviewer.harmony）及应用图标/名称
│   └── entry/
│       ├── src/main/cpp/     # C++ NAPI 原生模块（zlib 归档按页流式解压、图像处理等）
│       ├── src/main/ets/     # ArkTS 源码（EntryAbility、Index、hippo 核心与 UI 组件）
│       ├── src/main/resources/
│       └── src/test/         # 模块化单元测试套件
├── scripts/                  # 构建、测试（含 setup_tscheck.ps1）与静态质量检查脚本
├── CHANGELOG.md              # 版本更新日志
├── DEVIATIONS.md             # 相对上游 Android 实现的平台差异适配说明与已知能力边界
├── LICENSE                   # GNU General Public License v3.0
└── README.md
```

## 致谢

本项目的设计、架构与核心业务逻辑源自以下开源项目，特此致谢：

- [xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ)
- [seven332/EhViewer](https://github.com/seven332/EhViewer)

## 开源协议与免责声明

- 本项目遵循 **GNU General Public License v3.0 (`LICENSE`)** 开源。
- 本项目仅作为 HarmonyOS / ArkUI 与移动应用跨平台架构移植的技术学习与研究用途提供，不内置任何内容源数据或预配置账号；使用者需自行遵守所在地区法律法规及目标站点服务条款。
