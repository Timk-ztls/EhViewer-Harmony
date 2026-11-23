# Changelog

All notable changes to **EhViewer for HarmonyOS** are documented in this file.

## [2.0.2.7.4] - 2026-11-24

### Added & Improved
- **Follow system dark mode (`theme_auto_switch` + `system_theme`)**:
  - Wired `EntryAbility.onConfigurationUpdate`, `ThemeAutoSwitchHelper`, and `ThemeSystemBar` to react live to system `Configuration.colorMode` changes (sets `COLOR_MODE_NOT_SET` when auto-switch is enabled so callbacks stay active, and restores in-app theme mode when disabled).
  - Synced cold-start window color mode via `readCachedThemeStartup`, exposed `Settings.KEY_THEME_DARK_VARIANT` / `settings_eh_system_theme` in `SettingsPage` supporting dark and pure-black variants, and wired `Settings.setDarkModeProvider`.
- **Gallery list read progress (`show_read_progress`)**:
  - Restored `settings_eh_list_show_read_progress` and introduced an async in-memory `ReadProgressCache` updated by `SpiderQueen` during reading and hydrated off the render path for `GalleryListSceneView`, `FavoritesSceneView`, `HistorySceneView`, and `GalleryListHostPage`.
- **E-Hentai event & daily reward dialog (`show_eh_events`)**:
  - Restored `settings_eh_show_eh_event` and wired `EhEventPaneBus` with `EhEventPaneDialog` (`customStyle: true`, 3-state `ThemeTokens`) inside `MainPageHostView`.
- **Smart cellular network warning (`cellular_network_warning`)**:
  - Restored `settings_eh_cellular_network_warning` and upgraded `CellularNetworkWarningGuard` on `OhosNetworkMonitor` so cellular warnings deduplicate across continuous mobile browsing (including brief offline dips) and automatically reset when Wi-Fi or Ethernet becomes active (`isWifiOrEthernetActive()`).
- **400ms debounced network / VPN switch auto-recovery**:
  - Added genuine network/VPN signature change detection with a `400ms` debounce (`OhosNetworkMonitor.NETWORK_RECOVERY_DEBOUNCE_MS`) wired through `AppWiring.refreshNetworkStateOnChange`, resetting OkHttp pools and skipping triggers while `'offline'`.
  - **Thumbnails**: `DefaultImageRequestHost.recoverOnNetworkChange` cancels hung HTTP `Call`s, increments `downloadGeneration` to prevent stale `.finally()` counter corruption, re-enqueues active mounted targets (visible viewport first), and triggers `LoadImageController.retryForNetworkRecovery` (including `RETRY_TYPE_NONE`, capped at once per epoch, cleaned up on `unload()` / `onDetached()` / `onGetValue()`).
  - **Reader**: `PageImageDownloaderImpl.cancelAllActiveCalls()` aborts hung page transfers; `ReaderNetworkRecoveryGuard` + `GalleryReaderPage` silently retry `initError` or failed `currentPage` (with a `3000ms` delayed-failure guard if recovery hits mid-load and `MAX_AUTO_RETRIES_PER_PAGE = 3`, skipping HTTP `509` and `Insufficient GP`).
- **Version metadata**:
  - Bumped `harmony/AppScope/app.json5` to `versionName: "2.0.2.7.4"` (`versionCode: 116`) and synced `harmony/oh-package.json5` / `harmony/entry/oh-package.json5` to `"2.0.2-7.4"`.

## [2.0.2.7.3] - 2026-11-23

### Added & Improved
- **In-app ArkWeb proxy, lightweight browser & `.torrent` workflow (`1A` + `1C`)**:
  - Added `ArkWebProxyManager` syncing in-app proxy settings to `@kit.ArkWeb` `webview.ProxyController` (`applyProxyOverride` / `removeProxyOverride`) across `WebViewSignInSceneView`, `GetProfileSceneView`, `UConfigPage`, `MyTagsPage`, `InAppBrowserPage`, and `SettingsPage` proxy changes.
  - Added `InAppBrowserPage` for in-app account registration (`SignInSceneView`) and Tag Wiki (`GalleryDetailSceneView` with `stripTagNamespace` in `GalleryDetailBind` to strip `namespace:` prefixes), keeping an "Open in system browser" overflow action. Restored in-app `GalleryDetailScene` navigation for parent gallery links and completed in-app `.torrent` download (`DownloadTorrentManager`) with `DocumentViewPicker.save` and system share/open handoff.
- **Reader `@ohos.net.http` unification, system VPN bypass & proxy hot-refresh (`2ABC`)**:
  - Switched normal reader page downloads in `PageImageDownloaderImpl` / `GalleryReaderPage` to `followRedirects(true)` so traffic routes via `SystemHttpTransport` (`@ohos.net.http`) while preserving circular byte progress (`dataReceiveProgress`) and 30x hijack detection (`headersReceive` + `redirectTiming`); added `resolveRedirectUrl()` using `followRedirects(false)` for `/fullimg` probing.
  - Added `OhosNetworkMonitor` (`@ohos.net.connection`) to automatically bypass built-in hosts, Domain Fronting, and DoH when system VPN (`BEARER_VPN`) is active under `SYSTEM` / `DIRECT` proxy mode, and to reset HTTP pools & re-sync ArkWeb proxy on foreground/network transitions.
  - Added `SystemProxyHelper` fallback in `ConnectInterceptor` / `Http1SocketTransport`, prioritized IPv4 before IPv6 in `OkHttpEhHosts`, enabled `usingProxy: true` in `HttpDohResolver`, and added per-host in-memory caching with write/delete invalidation in `Hosts`.
- **Settings restoration, sign-out cleanup & real switch wiring (`3AB`)**:
  - Restored `identity_cookie` dialog/copy, `launch_page`, `history_info_size` (`EhDB.MAX_HISTORY_COUNT`), `fix_thumb_url`, `show_gallery_rating`, and `show_eh_limits` in `SettingsPage`; cleared display name, avatar, limits, and cookies cleanly on `sign_out`; fixed `show_gallery_pages` visibility in gallery lists and `export_download_items` UI copy.
  - Wired `download_origin_image` (supporting `/fullimg` 302 resolution and immediate `GP不足 / Insufficient GP` failure without bogus retries in `SpiderQueen` / `GalleryReaderPage`), `download_timeout`, `download_list_pagination` (`DownloadsSceneView` pagination bar), and `app_language` (`AdvancedSettingsHelpers.applyAppLanguage`).
- **Home thumbnail fast-scroll scheduler (`4ABC`)**:
  - Updated `DefaultImageRequestHost`, `LoadImageView`, `item_gallery_list`, `item_gallery_grid`, and `GalleryListSceneView` to prioritize the active visible viewport (`visibleQueue` LIFO over `prefetchQueue` driven by `onScrollIndex`, `.cachedCount(2)`), cancel orphaned URLs when targets reuse/switch URLs, bypass `http_cache` (`Cache-Control: no-store`), and tighten concurrency (`6`) / thumbnail timeout (`15s`).
- **Scroll-to-top after search & full list reload**:
  - Added `listResetSeq` and preemption in `GalleryListScene` / `FavoritesScene` (`MainPageHostView`, `GalleryListSceneView`, `FavoritesSceneView`) so searching, switching drawer sections, jumping pages, or filtering scrolls cleanly back to the top (preserving the 64vp search bar offset) while keeping existing scroll position when returning from gallery details.
- **Version metadata**:
  - Bumped `AppScope/app.json5` to `versionName: "2.0.2.7.3"` (`versionCode: 115`) and synced `oh-package.json5` / `entry/oh-package.json5` to `"2.0.2-7.3"`.

## [2.0.2.7.2] - 2026-11-23

### Fixed & Changed
- **Permanently disabled deprecated `AnalyticsScene` across the startup chain**:
  - Updated `Settings.DEFAULT_ASK_ANALYTICS` (`false`), `UnwiredSolidSceneSettings.getAskAnalytics()` (`false`), `SettingsSolidSceneAdapter.getAskAnalytics()` (`false`), `SolidScene.startSceneForCheckStep` (`CHECK_STEP_WARNING` falls through directly without starting `AnalyticsScene`), `MainActivity` (`launchAnnouncerFor`, `processAnnouncer`, `buildStartupGates`), and `GalleryActivity.runStartupChecks`. Fresh installs now proceed directly from `WarningScene` to `SignInScene` / `SelectSiteScene` / `GalleryListScene`.
  - Added fresh-install & `WarningScene.onAccept()` regression assertions in `settings-accessors.test.js`, `main-activity-part3.test.ets`, and `b3-routes-and-security-gate.test.ets`.
- **Bundle name updated to avoid Huawei AGC reserved segments**:
  - Updated default `bundleName` across `app.json5`, `shortcuts_config.json`, `DownloadService.ets`, `ArchiverDownloadService.ets`, `scripts/build_hap.ps1` (`-KeyAlias ehviewer_next`), and `DEVIATIONS.md` to `com.ehviewer.next` (`versionName: "2.0.2.7.2"`, `versionCode: 114`).
  - Added reserved-segment check (`oh`, `ohos`, `harmony`, `harmonyos`, `openharmony`, `system`) and legacy bundle guard to `.github/workflows/ci.yml`.
- **Developer onboarding, signing docs & community templates**:
  - Added `scripts/set_bundle_name.ps1` (PS 5.1 & pwsh 7 compatible, UTF-8 without BOM + LF) to rename `bundleName` across all 4 project files with format and reserved-segment validation.
  - Added `docs/SIGNING.md`, `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/{bug_report,feature_request}.yml`, and updated `README.md` with the 10-permission `0 ACL` reference table.

## [2.0.2.7.1] - 2026-11-23

### Changed & Fixed
- **Permission & SysCap hardening**:
  - Declared `ohos.permission.ACCELEROMETER` (`normal`) in `harmony/entry/src/main/module.json5` and wrapped `SecuritySceneView` sensor `start()` / `stop()` calls inside `canIUse('SystemCapability.Sensors.Sensor')` guards.
  - Kept restricted `ohos.permission.READ_PASTEBOARD` out of `module.json5`: background pasteboard reads in `AppWiring` safely fall back to `''`, and `WiFiClientPage` clipboard import uses ArkUI `PasteButton` for user-initiated authorization.
- **ArkTS warnings & deprecated API cleanup**:
  - Replaced `this._client.constructor === OkHttpClient` with `this._client instanceof OkHttpClient` in `PageImageDownloaderImpl` (`arkts-no-classes-as-obj`).
  - Migrated `animateTo` to `this.getUIContext().animateTo`, `promptAction.showToast` to window `UIContext.getPromptAction().showToast` (wired via `EntryAbility` + `ArchiverDownloadCompleter.setUiContext`), `i18n.System.getSystemLocale()` to `getSystemLocaleInstance().toString()`, `getPluralStringByNameSync` to `getIntPluralStringByNameSync`, and `TextEncoder.encode` / `TextDecoder.decode` to `encodeInto` / `decodeToString`.
  - Prefixed colliding `.id(...)` attributes across shared layout components and removed `export` from `@Entry @Component struct` page declarations.
- **Build metadata & package size hygiene**:
  - Updated `harmony/AppScope/app.json5` to `versionName: "2.0.2.7.1"` (`versionCode: 113`).
  - Updated `harmony/oh-package.json5` and `harmony/entry/oh-package.json5` `version` to SemVer-compliant `"2.0.2"` to satisfy hvigor validation.
  - Raised `cmake_minimum_required` in `harmony/entry/src/main/cpp/jni/stream/CMakeLists.txt` to `3.10`.
  - Removed 7 unused upstream image assets (`zhifubao.jpg`, `weixin.png`, `sb_anthor.png`, `shadow_2dp.png`, `shadow_8dp.png`) to eliminate `restool` warnings and reduce package size.

### Testing, CI & Docs
- **Unified unit test assertion reporting**:
  - Added `scripts/lib/test_assert.ps1` and standardized `ASSERT_SUMMARY` output across `scripts/run_all_tests.ps1` and multi-file test runners (`net-parse`, `storage-db`, `ui-scene`, `download-sync`, `gl-render`) so all 6 tested modules (49 units) report exact assertion counts without `assertions-n/a`.
- **Standalone CI & documentation**:
  - Added `scripts/setup_tscheck.ps1` to bootstrap `typescript` and `@ohos.*` / `@kit.*` CJS stubs without DevEco Studio dependencies.
  - Added GitHub Actions workflow `.github/workflows/ci.yml` (`windows-latest`), added `CHANGELOG.md`, and updated `README.md` with CI status badge and unsigned `release` build instructions.

## [2.0.2.7] - 2026-11-23

### Added & Changed (Upstream v2.0.2.7 Alignment)
- Updated `harmony/AppScope/app.json5` to `versionName: "2.0.2.7"` (`versionCode: 112`).
- Added fault-tolerant gallery API metadata recovery (`GalleryApiParser` skipping `"error"` / `"title": null` entries, `EhEngine.fillGalleryListByApiBestEffort` batching 25 galleries per call).
- Added 3-tier restore download compatibility supporting text `.ehviewer`, CBOR `.ehviewer` (`CborSpiderHeader` with `MAX_DEPTH=16` and `MAX_BYTES=32MB`), and `ComicInfo.xml` (`ComicInfoParser`), unified `gid < 0` guards, and offline fallback naming (`apiTitle -> dirname -> gid`).
- Added safe torrent filename generation (`DownloadTorrentManager.createTorrentFileName`, `TorrentDownloadController.buildTorrentFileName`) with invalid-character sanitization, UTF-8 `255 - 8` byte truncation preserving surrogate pairs, and URL tail fallback.
- Added standard comment-only `harmony/entry/obfuscation-rules.txt` so `release` unsigned HAP builds work out of the box (`obfuscation.ruleOptions.enable: false`).
- Added corresponding unit tests in `net-parse`, `storage-db`, `core-runtime`, `download-sync`, and `ui-scene`.

## [2.0.2.6] - 2026-11-22

### Added
- Initial public release of EhViewer for HarmonyOS NEXT / OpenHarmony (API 20).
