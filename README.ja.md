# EhViewer for HarmonyOS

[![CI](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml/badge.svg)](https://github.com/Timk-ztls/EhViewer-Harmony/actions/workflows/ci.yml)

[简体中文](./README.md) | [English](./README.en.md) | **日本語**

**EhViewer**（[xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ) / [seven332/EhViewer](https://github.com/seven332/EhViewer)）をベースに ArkTS + ArkUI および C++ NAPI ネイティブ層で実装した **HarmonyOS NEXT / OpenHarmony（API 20）** ネイティブクライアントです。

## 主な機能

- **ギャラリー閲覧・フィルタリング**：ホーム一覧、人気（What's Hot）、購読（Subscription）、ランキング、クイック検索、ローカル／クラウドお気に入り、ローカルタグフィルタに対応。検索・カテゴリ切替・ページジャンプ後は自動でリスト先頭へ戻り、詳細画面から戻った際は元のスクロール位置を保持します。
- **表示領域優先のサムネイルスケジューリング**：高速スクロール時に現在表示中のサムネイルを最優先（可視 LIFO キュー）で読み込み、カード再利用時の古いリクエスト取消と HTTP キャッシュの二重書き込み回避を行います。
- **検索・タグシステム**：詳細検索、画像検索、`EhTagDatabase` タグ翻訳の自動更新とローカルキャッシュに対応。
- **ギャラリー詳細・アプリ内ブラウザ**：詳細情報、プレビュー、タググループ（Tag Wiki 検索時に `namespace:` プレフィックスを自動除去）、評価・お気に入り登録、コメント投稿、軽量アプリ内ブラウザ（アカウント登録 / Tag Wiki 用 `InAppBrowserPage`）、`.torrent` のアプリ内ダウンロードとシステム保存（`DocumentViewPicker`）／共有に対応。
- **ネイティブリーダー・ネットワーク最適化**：
  - 左→右、右→左（縦読み／見開き相当の漫画送り）、縦スクロールモードに対応し、スワイプ・左右タップ・ピンチ／ダブルタップ拡大・音量キーでのページ送りをサポート。
  - 画像取得を `@ohos.net.http` 経路に統一し、円形バイト進捗表示（`dataReceiveProgress`）、30x ハイジャック検知、`/fullimg` 原図 302 解決（`download_origin_image`、GP 不足時は即座に通知）を実装。
  - アプリ内プロキシ設定を `@kit.ArkWeb`（`ProxyController`）へ自動同期。また `SYSTEM` / `DIRECT` モードかつシステム VPN（`BEARER_VPN`）有効時は内蔵 Hosts / Domain Fronting / DoH を自動バイパスし、VPN のルーティング規則に従います。
- **ダウンロード・ローカルアーカイブ**：
  - バックグラウンドダウンロード、ダウンロードラベル管理、ページネーション表示、Wi-Fi LAN 転送に対応。
  - C++ `zlib` ストリーミング解凍＋`@kit.BasicServicesKit` フォールバックにより `.zip` / `.cbz` / `.7z` を直接閲覧可能（RAR/CBR 非対応、詳細は `DEVIATIONS.md` D-079 参照）。
- **プライバシー・外観**：
  - `ohos.permission.PRIVACY_WINDOW` によるプライバシーモード（コールドスタート初フレームおよびフォアグラウンド復帰時にスクリーンショット・画面録画・マルチタスクプレビューを遮断）。
  - Material テーマ配色、システムステータスバー連携、RDB データベースのバックアップ・エクスポート／インポートに対応。

## 動作・ビルド環境

- **DevEco Studio**（HarmonyOS SDK API 20 / `6.0.0(20)` 対応、`hvigorw` および Command Line Tools 設定済み）
- **JDK**（Java 17 以上、HAP パッケージングおよびローカル署名用）
- **Node.js**（DevEco Studio 同梱またはシステム導入済み、TypeScript チェック・単体テスト実行用）
- **PowerShell 7+** (`pwsh`)（ビルドスクリプト、静的ゲート、単体テスト実行用。`scripts/set_bundle_name.ps1` は Windows PowerShell 5.1 にも対応）

## アプリ権限（`0 ACL`）

本アプリは Huawei AppGallery Connect (AGC) での **ACL 制限権限申請不要（`0 ACL`）** で動作します。[module.json5](./harmony/entry/src/main/module.json5) に宣言されている 10 個の権限はすべて `availableLevel=normal` です：

| 権限名 | 付与方式 | 用途 |
|---|---|---|
| `ohos.permission.INTERNET` | `system_grant` | ギャラリー一覧・詳細・画像・タグ翻訳データベースの通信 |
| `ohos.permission.GET_NETWORK_INFO` | `system_grant` | ネットワーク接続状態・VPN 有効状態・回線切替の検知 |
| `ohos.permission.PRIVACY_WINDOW` | `system_grant` | プライバシーモード時のスクショ／録画禁止とタスク一覧非表示 |
| `ohos.permission.GET_WIFI_INFO` | `system_grant` | Wi-Fi LAN 転送機能の接続状態取得 |
| `ohos.permission.VIBRATE` | `system_grant` | パターンロック解除および操作時の振動フィードバック |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | `system_grant` | ダウンロードバックグラウンド長時間タスク維持 |
| `ohos.permission.RUNNING_LOCK` | `system_grant` | ダウンロード継続中の WakeLock 維持 |
| `ohos.permission.ACCESS_BIOMETRIC` | `system_grant` | 生体認証（指紋・顔）によるアプリロック解除 |
| `ohos.permission.ACCELEROMETER` | `system_grant` | セキュリティ画面での加速度センサー連携 |
| `ohos.permission.CAMERA` | `user_grant`（必要時に許可ダイアログ） | プロフィール画面でのアバター撮影・変更 |

> プライバシー最小化方針：高権限の `ohos.permission.READ_PASTEBOARD` は宣言せず（クリップボード取り込みには ArkUI `PasteButton` を使用）、広範なメディア読み書き権限の代わりにアプリサンドボックスおよび `DocumentViewPicker` を利用しています。

## ビルド・パッケージ名変更・署名について

> [!IMPORTANT]
> 本リポジトリは `harmony/build-profile.json5` の `signingConfigs` を意図的に空（`[]`）にしており、署名証明書・秘密鍵・`.p7b` プロファイルを一切含みません。
> **GitHub Releases で配布している未署名 HAP（`com.ehviewer.next`）はすでに登録済みのパッケージ名を使用しているため、他アカウントの証明書でそのまま再署名・インストールすることはできません。ご自身の端末へインストールする場合はソースをクローンし、下記手順でパッケージ名を変更してからビルド・署名してください。**
> 詳細手順とエラー対処法は **[署名・インストールガイド（docs/SIGNING.ja.md）](./docs/SIGNING.ja.md)** を参照してください。

### クイックスタート：DevEco Studio 自動署名（推奨）

1. **最初に一意のパッケージ名へ変更する**（Huawei の 6 つの予約セグメント `oh` / `ohos` / `harmony` / `harmonyos` / `openharmony` / `system` を単独セグメントとして含めないでください）：
   ```powershell
   pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer
   ```
   （命名規則と予約語を検証し、`app.json5`、`shortcuts_config.json`、`DownloadService.ets`、`ArchiverDownloadService.ets` を UTF-8 BOM なし＋LF で一括更新します。）
2. DevEco Studio でリポジトリ内の `harmony/` ディレクトリを開き、Sync 完了を待ちます。
3. **File → Project Structure → Signing Configs** で Huawei 開発者アカウントにログインし、**Automatically generate signature** を有効化します。
4. 実機を接続し、**Run** または **Build → Build Hap(s)** を実行します。

### コマンドラインビルド・手動署名

```powershell
# SDK と JDK の環境変数を指定（未設定時は build_hap.ps1 が一般的なパスを自動検出）
$env:DEVECO_SDK_HOME = "$env:LOCALAPPDATA\Huawei\Sdk"
$env:JAVA_HOME = "C:\Program Files\Java\jdk-21"

# 1) hvigorw で未署名 debug / release HAP を直接ビルド
cd harmony
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
.\hvigorw.bat assembleHap --mode module -p product=default -p buildMode=release --no-daemon

# 2) ラッパースクリプトを使用（harmony/signing/ に .cer/.p7b/.p12 とパスワードがある場合は自動署名）
pwsh -File scripts/build_hap.ps1 -KeyAlias <your_alias>
```

未署名 HAP の既定出力先は `harmony/entry/build/default/outputs/default/entry-default-unsigned.hap` です。AGC での `.cer` / `.p7b` 手動発行手順は [docs/SIGNING.ja.md](./docs/SIGNING.ja.md) をご覧ください。

## 単体テスト・静的チェック

```powershell
# 初回実行時（DevEco Studio 不要）に TypeScript 5.4.5 と @ohos.* / @kit.* スタブをセットアップ
pwsh -File scripts/setup_tscheck.ps1

# 全モジュール単体テスト実行
pwsh -File scripts/run_all_tests.ps1

# 静的品質ゲート
pwsh -File scripts/check_line_endings.ps1 -Gate
pwsh -File scripts/check_contrast.ps1 -Gate
pwsh -File scripts/check_contrast.ps1 -Path harmony/entry/src/main/ets/hippo/ehviewer/widget -Gate
pwsh -File scripts/check_silent_failures.ps1 -Gate
pwsh -File scripts/check_resource_keys.ps1 -Gate
```

コントリビューション手順や PR チェック基準は [CONTRIBUTING.md](./CONTRIBUTING.md) をご参照ください。

## ディレクトリ構成

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/       # Bug 報告・機能要望テンプレート
│   └── workflows/ci.yml      # GitHub Actions 静的チェック＆単体テスト（windows-latest）
├── docs/
│   ├── SIGNING.md            # 署名・パッケージ名変更ガイド（簡体字中国語）
│   ├── SIGNING.en.md         # Signing & bundle-renaming guide (English)
│   └── SIGNING.ja.md         # パッケージ名変更・署名・インストールガイド（日本語）
├── harmony/                  # DevEco Studio / Hvigor メインプロジェクト（AppScope + entry）
│   ├── AppScope/             # アプリ設定 app.json5（既定 bundleName: com.ehviewer.next）およびアイコン・アプリ名
│   └── entry/
│       ├── src/main/cpp/     # C++ NAPI ネイティブモジュール（zlib アーカイブ展開・画像処理等）
│       ├── src/main/ets/     # ArkTS ソースコード（EntryAbility, Index, hippo コア／UI）
│       ├── src/main/resources/
│       └── src/test/         # モジュール別単体テストスイート
├── scripts/                  # ビルド・パッケージ名変更（set_bundle_name.ps1）・テスト・静的検証スクリプト
├── CHANGELOG.md              # 変更履歴
├── CONTRIBUTING.md           # 開発・PR ガイドライン
├── DEVIATIONS.md             # Android 版とのプラットフォーム差異・仕様境界一覧
├── LICENSE                   # GNU General Public License v3.0
├── README.md                 # README（簡体字中国語）
├── README.en.md              # README (English)
└── README.ja.md              # README（日本語）
```

## 謝辞

本プロジェクトの設計・アーキテクチャおよびコア実装は以下のオープンソースプロジェクトをベースとしています：

- [xiaojieonly/Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ)
- [seven332/EhViewer](https://github.com/seven332/EhViewer)

## ライセンス・免責事項

- 本プロジェクトは **GNU General Public License v3.0 (`LICENSE`)** のもとで公開されています。
- HarmonyOS / ArkUI におけるクロスプラットフォーム移植技術の学習・研究を目的としており、コンテンツソースやアカウント情報は同梱していません。利用者は居住地域の法令および対象サイトの利用規約を遵守の上ご利用ください。
