# Changelog

All notable changes to **EhViewer for HarmonyOS** are documented in this file.

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
