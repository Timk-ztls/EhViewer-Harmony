# EhViewer for HarmonyOS

[![CI](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml/badge.svg)](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml)

[简体中文](./README.md) | **English** | [日本語](./README.ja.md)

A native **HarmonyOS NEXT / OpenHarmony (API 20)** port of **EhViewer** ([xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) / [seven332/EhViewer](https://github.com/seven332/EhViewer)), built with ArkTS + ArkUI and a C++ NAPI native layer.

## Key Features

- **Gallery Browsing & Filtering**: Home feed, What's Hot, Subscriptions, Toplists, Quick Search, local & cloud Favorites, and local tag filtering; automatically scrolls back to the top after search/section changes/page jumps while preserving detail-return position, displays async in-memory reading progress on gallery cards (`show_read_progress`), and presents E-Hentai event/daily-reward dialogs (`show_eh_events`).
- **Viewport-First Thumbnail Scheduling**: Prioritizes currently visible thumbnails (LIFO visible queue over prefetch queue) during fast scrolling, cancels orphaned URLs on card reuse, bypasses duplicate HTTP cache writes, and recovers hung/failed visible thumbnails via 400ms debounced network/VPN switch recovery.
- **Search & Tag System**: Advanced search filters, image reverse search, and auto-updating `EhTagDatabase` tag translation cache.
- **Gallery Details & In-App Browser Closure**: Complete gallery metadata, preview grids, grouped tags (Tag Wiki strips `namespace:` prefixes automatically), rating/favoriting, comment posting, built-in lightweight browser (`InAppBrowserPage`) for account sign-up / Tag Wiki, and in-app `.torrent` downloads with system Save (`DocumentViewPicker`) and Share/Open handoff.
- **Native Reader & Network Adaptations**:
  - Left-to-right, right-to-left (manga), and vertical continuous reading modes; 1:1 swipe tracking, tap-zone navigation, pinch/double-tap zoom, and volume-key page turning.
  - Routes image downloads through `@ohos.net.http` with circular byte-level progress (`dataReceiveProgress`), 30x hijack detection, `/fullimg` original-image resolution (`download_origin_image`, aborting immediately on insufficient GP), and 400ms debounced silent recovery when switching networks or toggling a VPN.
  - Syncs in-app proxy settings into `@kit.ArkWeb` (`ProxyController`) for WebView sign-in, UConfig, My Tags, and the built-in browser; detects active system VPNs via `@ohos.net.connection` to automatically bypass built-in hosts, Domain Fronting, and DoH when using `SYSTEM` / `DIRECT` mode, and provides smart cellular data warnings (`cellular_network_warning`) that auto-reset on Wi-Fi or Ethernet.
- **Downloads & Local Archives**:
  - Background download service, download labels, pagination controls, and Wi-Fi LAN transfer.
  - Streaming C++ `zlib` decompression with `@kit.BasicServicesKit` fallback for `.zip` / `.cbz` / `.7z` archives (RAR/CBR is not supported; see `DEVIATIONS.md` D-079).
- **Privacy & Appearance**:
  - Privacy mode via `ohos.permission.PRIVACY_WINDOW` (blocks screenshots, screen recording, and recents preview from cold start and foreground resume).
  - Material-aligned themes with system dark mode auto-switch (`theme_auto_switch` + `system_theme`, supporting dark/pure-black variants, cold-start window sync, and system status bar tinting) plus RDB backup/import/export.

## Requirements

- **DevEco Studio** supporting HarmonyOS SDK API 20 (`6.0.0(20)`), with `hvigorw` and Command Line Tools configured
- **JDK** (Java 17+) for HAP packaging and optional local signing
- **Node.js** (bundled with DevEco Studio or installed on system) for TypeScript compilation & unit tests
- **PowerShell 7+** (`pwsh`) to run build helpers, static quality gates, and unit tests (`scripts/set_bundle_name.ps1` also supports Windows PowerShell 5.1)

## Permissions (`0 ACL`)

This release requires **no restricted ACL permissions (`0 ACL`)** in Huawei AppGallery Connect (AGC). All 10 permissions declared in [module.json5](./harmony/entry/src/main/module.json5) have `availableLevel=normal`:

| Permission | Grant Type | Purpose |
|---|---|---|
| `ohos.permission.INTERNET` | `system_grant` | Network requests for gallery lists, details, images, and tag translations |
| `ohos.permission.GET_NETWORK_INFO` | `system_grant` | Network connectivity, VPN state, and change monitoring |
| `ohos.permission.PRIVACY_WINDOW` | `system_grant` | Screenshot/screen-recording block and recents blur in privacy mode |
| `ohos.permission.GET_WIFI_INFO` | `system_grant` | Wi-Fi LAN transfer connection status |
| `ohos.permission.VIBRATE` | `system_grant` | Pattern-lock and UI haptic feedback |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | `system_grant` | Background continuous-task keep-alive for gallery/archive downloads |
| `ohos.permission.RUNNING_LOCK` | `system_grant` | Wake-lock keep-alive during active downloads |
| `ohos.permission.ACCESS_BIOMETRIC` | `system_grant` | Biometric (fingerprint / face) app-lock authentication |
| `ohos.permission.ACCELEROMETER` | `system_grant` | Security-gate sensor interaction |
| `ohos.permission.CAMERA` | `user_grant` (on-demand prompt) | Taking an avatar photo in Profile settings |

> Privacy minimization: `ohos.permission.READ_PASTEBOARD` is intentionally omitted (clipboard import uses ArkUI `PasteButton` security component with safe empty fallback), and broad media read/write permissions are replaced with app sandbox storage plus `DocumentViewPicker`.

## Building, Bundle Renaming & Signing

> [!IMPORTANT]
> This repository intentionally keeps `signingConfigs` empty (`[]`) in `harmony/build-profile.json5` and includes no developer certificates, private keys, or `.p7b` profiles.
> **The unsigned HAP attached to GitHub Releases uses bundle name `com.ehviewer.next`, which is already registered and cannot be re-signed by another developer account. To install on your own device, clone the source, rename the bundle ID, and build with your own signature.**
> Full instructions and error troubleshooting are available in **[Signing & Installation Guide (docs/SIGNING.en.md)](./docs/SIGNING.en.md)**.

### Quick Start: DevEco Studio Automatic Signing (Recommended)

1. **Change to your own unique bundle name first** (must avoid Huawei's 6 reserved standalone segments: `oh`, `ohos`, `harmony`, `harmonyos`, `openharmony`, `system`):
   ```powershell
   pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer
   ```
   (Validates reverse-domain format and reserved segments, updating `app.json5`, `shortcuts_config.json`, `DownloadService.ets`, and `ArchiverDownloadService.ets` in UTF-8 without BOM + LF.)
2. Open the `harmony/` directory in DevEco Studio and wait for project Sync to finish.
3. Open **File -> Project Structure -> Signing Configs**, sign in with your Huawei Developer account, and check **Automatically generate signature**.
4. Connect your HarmonyOS device and click **Run** or **Build -> Build Hap(s)**.

### CLI Packaging & Offline Signing

```powershell
# Configure SDK and JDK paths (build_hap.ps1 auto-detects default paths if omitted)
$env:DEVECO_SDK_HOME = "$env:LOCALAPPDATA\Huawei\Sdk"
$env:JAVA_HOME = "C:\Program Files\Java\jdk-21"

# 1) Build unsigned debug or release HAP directly via hvigorw
cd harmony
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release --no-daemon

# 2) Or use the wrapper script (auto-signs if harmony/signing/ has your .cer/.p7b/.p12 + password)
pwsh -File scripts/build_hap.ps1 -KeyAlias <your_alias>
```

Default unsigned output: `harmony/entry/build/default/outputs/default/entry-default-unsigned.hap`. See [docs/SIGNING.en.md](./docs/SIGNING.en.md) for manual AGC `.cer` / `.p7b` generation steps.

## Unit Tests & Static Quality Gates

```powershell
# Bootstrap TypeScript 5.4.5 and @ohos.* / @kit.* stubs on first run (no DevEco Studio needed)
pwsh -File scripts/setup_tscheck.ps1

# Run full unit test suite across all tested modules
pwsh -File scripts/run_all_tests.ps1

# Static quality gates
pwsh -File scripts/check_line_endings.ps1 -Gate
pwsh -File scripts/check_contrast.ps1 -Gate
pwsh -File scripts/check_contrast.ps1 -Path harmony/entry/src/main/ets/hippo/ehviewer/widget -Gate
pwsh -File scripts/check_silent_failures.ps1 -Gate
pwsh -File scripts/check_resource_keys.ps1 -Gate
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for contribution guidelines and PR verification rules.

## Project Structure

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/       # Bug report & feature request templates
│   └── workflows/ci.yml      # GitHub Actions static gates & unit-test pipeline (windows-latest)
├── docs/
│   ├── SIGNING.md            # Bundle renaming & AGC/auto-signing guide (Simplified Chinese)
│   ├── SIGNING.en.md         # Signing & bundle-renaming guide (English)
│   └── SIGNING.ja.md         # パッケージ名変更・署名・インストールガイド（日本語）
├── harmony/                  # Main DevEco Studio / Hvigor project (AppScope + entry module)
│   ├── AppScope/             # Global app.json5 (default bundleName: com.ehviewer.next) & app icon/name
│   └── entry/
│       ├── src/main/cpp/     # C++ NAPI native module (zlib streaming archive extraction, image processing, etc.)
│       ├── src/main/ets/     # ArkTS source code (EntryAbility, Index, hippo core & UI views)
│       ├── src/main/resources/
│       └── src/test/         # Modular unit test suites
├── scripts/                  # Build, bundle-renaming (set_bundle_name.ps1), testing & static gate scripts
├── CHANGELOG.md              # Release changelog
├── CONTRIBUTING.md           # Contributor & self-check guidelines
├── DEVIATIONS.md             # Platform-adaptation deviations & known boundaries vs. upstream Android
├── LICENSE                   # GNU General Public License v3.0
├── README.md                 # Project README (Simplified Chinese)
├── README.en.md              # Project README (English)
└── README.ja.md              # プロジェクト説明書（日本語）
```

## Acknowledgements

Architecture, design, and core client logic originate from:

- [xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ)
- [seven332/EhViewer](https://github.com/seven332/EhViewer)

## License & Disclaimer

- Licensed under the **GNU General Public License v3.0 (`LICENSE`)**.
- Provided strictly for cross-platform HarmonyOS / ArkUI technical study and research. No bundled content sources or preconfigured accounts are included; users are responsible for complying with local laws and target site terms of service.
