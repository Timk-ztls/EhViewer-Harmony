# EhViewer for HarmonyOS

[![CI](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml/badge.svg)](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml)

**简体中文** | [English](./README.en.md) | [日本語](./README.ja.md)

基于上游 **EhViewer**（[xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) / [seven332/EhViewer](https://github.com/seven332/EhViewer)）移植实现的 **HarmonyOS NEXT / OpenHarmony（API 20）** 原生客户端，使用 ArkTS + ArkUI 与 C++ NAPI 原生层开发。

## 主要特性

- **画廊浏览与筛选**：首页列表、热门、订阅（Subscription）、Toplist、快速搜索、收藏夹与本地标签筛选；搜索、切栏与跳页后自动回到列表顶部并保留详情返回位置，支持列表卡片显示阅读进度记忆（异步内存缓存，不阻塞滚动）及 E 站每日奖励/事件弹窗提醒。
- **首屏优先缩略图调度**：快滑时基于可视窗口优先出图，复用卡片自动清理过期请求并避开双重写盘缓存；支持切换网络/开关 VPN 后 400ms 防抖自动断开卡死连接并静默恢复失败封面。
- **搜索与标签系统**：高级搜索、图片以图搜图、EhTagDatabase 标签翻译自动更新与本地缓存。
- **画廊详情与站内浏览闭环**：完整详情展示、预览图、多标签组（标签百科自动剥离 `namespace:` 前缀）、评分/收藏、评论发表、内置轻量浏览器与 `.torrent` 种子应用内下载保存/分享。
- **原生阅读器与网络适配**：
  - 支持从左到右 / 从右到左（日漫）分页及纵向长图模式，1:1 跟手滑动与左/右点击翻页并存，双指/双击缩放与音量键翻页。
  - 统一走 `@ohos.net.http` 栈保留单页下载环形进度与劫持检测；支持原图 `/fullimg` 302 直链下载（GP 不足立即提示），以及切网 / VPN 切换后自动静默重试当前失败页。
  - 支持应用内代理统一接管 ArkWeb（登录 / UConfig / 我的标签 / 内置浏览器），系统 VPN 活跃且代理设为系统/直连时自动旁路内置 Hosts / Domain Fronting / DoH 以遵循 VPN 分流；支持移动网络智能提醒（切回 Wi-Fi/以太网自动重置状态）。
  - 支持阅读进度记忆与列表/详情页联动同步。
- **下载管理与本地归档阅读**：
  - 后台下载调度、下载标签管理、Wi-Fi 局域网传输。
  - 内置 C++ `zlib` 流式解压与 `@kit.BasicServicesKit` 回退，支持打开本地 `.zip` / `.cbz` / `.7z` 归档（RAR/CBR 暂不支持，见 `DEVIATIONS.md` D-079）。
- **隐私与外观**：
  - 隐私保护模式（通过 `ohos.permission.PRIVACY_WINDOW` 拦截截屏/录屏，冷启动首帧与切前台即时生效）。
  - Material 风格多主题配色与深色跟随系统（`theme_auto_switch` + `system_theme`，支持深色/纯黑变体、冷启动首帧同步与系统状态栏联动）。
  - 支持数据库与收藏/配置导入导出（RDB 存储）。

## 环境要求

- **DevEco Studio**（支持 HarmonyOS SDK API 20 / `6.0.0(20)`，已配置 `hvigorw` 与 Command Line Tools）
- **JDK**（Java 17+，用于 HAP 打包与可选签名）
- **Node.js**（随 DevEco Studio 或系统安装，用于 TypeScript / 单元测试）
- **PowerShell 7+** (`pwsh`)，用于运行辅助构建脚本、代码门禁检查及单元测试（`scripts/set_bundle_name.ps1` 亦兼容 Windows PowerShell 5.1）

## 应用权限说明

本应用当前版本**无需向华为 AGC 申请任何 ACL 受限权限（`0 ACL`）**。[module.json5](./harmony/entry/src/main/module.json5) 声明的 10 项权限全部属于 `availableLevel=normal`：

| 权限名 | 授权方式 | 用途 |
|---|---|---|
| `ohos.permission.INTERNET` | `system_grant` | 画廊列表、详情、图片与标签库网络请求 |
| `ohos.permission.GET_NETWORK_INFO` | `system_grant` | 网络连通性与状态变化检测 |
| `ohos.permission.PRIVACY_WINDOW` | `system_grant` | 隐私模式防截屏、防录屏与多任务预览隐藏 |
| `ohos.permission.GET_WIFI_INFO` | `system_grant` | 局域网 Wi-Fi 传书连接状态获取 |
| `ohos.permission.VIBRATE` | `system_grant` | 图案密码解锁与交互震动反馈 |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | `system_grant` | 画廊与归档后台下载长时任务保活 |
| `ohos.permission.RUNNING_LOCK` | `system_grant` | 后台持续下载唤醒锁保活 |
| `ohos.permission.ACCESS_BIOMETRIC` | `system_grant` | 应用锁生物识别（指纹 / 人脸）解锁 |
| `ohos.permission.ACCELEROMETER` | `system_grant` | 安全门页加速度传感器交互 |
| `ohos.permission.CAMERA` | `user_grant`（按需弹窗） | 个人资料页拍照更换头像 |

> 隐私最小化设计：未申请高权限 `ohos.permission.READ_PASTEBOARD`（剪贴板导入通过系统安全控件 `PasteButton` 完成，背景剪贴板读取安全回退为空），亦未申请全局媒体读写权限（本地文件与归档导出导入统一通过沙箱与 `DocumentViewPicker` 完成）。

## 构建、改包名与签名说明

> [!IMPORTANT]
> 本仓库刻意将 `harmony/build-profile.json5` 中的 `signingConfigs` 置空为 `[]`，且不包含任何开发者证书、私钥或 `.p7b` Profile。
> **GitHub Releases 附带的未签名 HAP（包名 `com.ehviewer.next`）已被注册占用，无法直接用其他账号重签安装；开发者真机自用请克隆源码并按下方步骤修改包名后编译安装。**
> 完整说明与报错排查见 **[签名与安装完整指南（docs/SIGNING.md）](./docs/SIGNING.md)**。

### 快速上手：DevEco Studio 自动签名（推荐）

1. **先改成你自己的唯一包名**（必须避开华为 6 个保留独立段 `oh` / `ohos` / `harmony` / `harmonyos` / `openharmony` / `system`）：
   ```powershell
   pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer
   ```
   （脚本会自动校验命名规范并以 UTF-8 无 BOM + LF 同步写入 `app.json5`、`shortcuts_config.json`、`DownloadService.ets` 与 `ArchiverDownloadService.ets`。）
2. 使用 DevEco Studio 打开仓库内的 `harmony/` 目录，等待 Sync 完成。
3. 打开 **File → Project Structure → Signing Configs**，登录华为账号并勾选 **Automatically generate signature**（自动生成调试签名）。
4. 连接真机，点击 **Run** 或 **Build → Build Hap(s)**。

### 命令行打包与离线签名

```powershell
# 设置 SDK 与 JDK 环境变量（未设置时 build_hap.ps1 会尝试自动探测常见路径）
$env:DEVECO_SDK_HOME = "$env:LOCALAPPDATA\Huawei\Sdk"
$env:JAVA_HOME = "C:\Program Files\Java\jdk-21"

# 1) 使用 hvigorw 直接构建未签名 debug 或 release HAP
cd harmony
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release --no-daemon

# 2) 或使用封装脚本（若 harmony/signing/ 下已有自己的 .cer/.p7b/.p12 与口令则自动签名，否则保留未签名 HAP）
pwsh -File scripts/build_hap.ps1 -KeyAlias <your_alias>
```

未签名产物默认位于：`harmony/entry/build/default/outputs/default/entry-default-unsigned.hap`。离线手动向 AGC 申请 `.cer` / `.p7b` 的详细命令见 [docs/SIGNING.md](./docs/SIGNING.md)。

## 单元测试与静态检查

```powershell
# 首次运行（或无 DevEco 环境时）先初始化 TypeScript 5.4.5 与 @ohos.* / @kit.* 测试桩
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

参与代码贡献与 PR 提交流程请查看 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## 目录结构

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/       # Bug 反馈与功能建议模板
│   └── workflows/ci.yml      # GitHub Actions 自动化门禁与单测流水线（windows-latest）
├── docs/
│   ├── SIGNING.md            # 包名修改、AGC/自动签名申请与装机排查指南（简体中文）
│   ├── SIGNING.en.md         # Signing & bundle-renaming guide (English)
│   └── SIGNING.ja.md         # パッケージ名変更・署名・インストールガイド（日本語）
├── harmony/                  # DevEco Studio / Hvigor 主工程（AppScope + entry 模块）
│   ├── AppScope/             # 全局 app.json5（默认包名 com.ehviewer.next）及应用图标/名称
│   └── entry/
│       ├── src/main/cpp/     # C++ NAPI 原生模块（zlib 归档按页流式解压、图像处理等）
│       ├── src/main/ets/     # ArkTS 源码（EntryAbility、Index、hippo 核心与 UI 组件）
│       ├── src/main/resources/
│       └── src/test/         # 模块化单元测试套件
├── scripts/                  # 构建、改包名（set_bundle_name.ps1）、测试与静态门禁脚本
├── CHANGELOG.md              # 版本更新日志
├── CONTRIBUTING.md           # 开源贡献与开发自检规范
├── DEVIATIONS.md             # 相对上游 Android 实现的平台差异适配说明与已知能力边界
├── LICENSE                   # GNU General Public License v3.0
├── README.md                 # 项目说明（简体中文）
├── README.en.md              # Project README (English)
└── README.ja.md              # プロジェクト説明書（日本語）
```

## 致谢

本项目的设计、架构与核心业务逻辑源自以下开源项目，特此致谢：

- [xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ)
- [seven332/EhViewer](https://github.com/seven332/EhViewer)

## 开源协议与免责声明

- 本项目遵循 **GNU General Public License v3.0 (`LICENSE`)** 开源。
- 本项目仅作为 HarmonyOS / ArkUI 与移动应用跨平台架构移植的技术学习与研究用途提供，不内置任何内容源数据或预配置账号；使用者需自行遵守所在地区法律法规及目标站点服务条款。
