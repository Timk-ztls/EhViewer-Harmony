# パッケージ名変更・署名・実機インストールガイド

[简体中文](./SIGNING.md) | [English](./SIGNING.en.md) | **日本語**

> [!IMPORTANT]
> **GitHub Releases の未署名 HAP をそのまま自分の証明書で再署名・インストールできない理由**
> - ビルド済み `.hap` 内の `module.json`、`pack.info`、およびショートカット定義には、コンパイル時点で決定された `bundleName`（本リポジトリ既定値は `com.ehviewer.next`）が埋め込まれています。
> - HarmonyOS 実機インストーラー（BMS）は **HAP 内の `bundleName` と `.p7b` プロファイル内の `bundle-name` の完全一致**を必須としており、Huawei AppGallery Connect (AGC) 上のパッケージ名は全開発者間で一意である必要があります。
> - そのため、**GitHub Releases の未署名 HAP はビルド成果物の保管・SHA-256 検証・`com.ehviewer.next` 所有者による署名用途のみを対象としています。他の開発者が実機へ導入する場合は、ソースコードをクローン → スクリプトでパッケージ名を変更 → ご自身の証明書で再ビルド・署名してインストールしてください。**

---

## ステップ 1：独自のパッケージ名に変更する（予約セグメント回避必須）

Huawei AGC では HarmonyOS アプリの `bundleName` に以下の制約があります：
1. 長さ **7〜128** 文字の逆ドメイン形式（`.` で区切られた 3 セグメント以上、例：`com.yourname.ehviewer`）。使用可能文字は小文字英字・数字・`_`・`.` のみ（大文字・`-` は不可）。
2. AGC 上で他アカウントと重複しない一意な名前であること（既定値 `com.ehviewer.next` は登録済みです）。
3. **Huawei の 6 つの予約語を単独セグメントとして含めないこと**（大文字・小文字を問わず拒否）：
   - `oh`、`ohos`、`harmony`、`harmonyos`、`openharmony`、`system`
   - 例：`com.ehviewer.harmony` や `ohos.app.ehviewer` は自動署名および AGC 登録時に拒否されます。

リポジトリ同梱のスクリプトで 4 箇所のパッケージ名定義を一括更新できます（Windows PowerShell 5.1 / PowerShell 7 両対応）：

```powershell
# 変更対象をプレビュー（ファイルは書き換えない）
pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer -DryRun

# 実際に書き込み（形式と 6 予約セグメントを検証し、UTF-8 BOM なし＋LF で保存）
pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer
```

更新される 4 箇所：
- `harmony/AppScope/app.json5`（`app.bundleName`）
- `harmony/entry/src/main/resources/base/profile/shortcuts_config.json`（`bundleName` × 2）
- `harmony/entry/src/main/ets/hippo/ehviewer/download/DownloadService.ets`（`SLOT_ID` およびフォールバック値）
- `harmony/entry/src/main/ets/hippo/ehviewer/download/ArchiverDownloadService.ets`（`SLOT_ID` およびフォールバック値）

---

## ステップ 2：署名方式を選んでビルド・インストールする

### 方法 A：DevEco Studio 自動署名（個人向け実機デバッグに最適・推奨）

1. 先にステップ 1 の `scripts/set_bundle_name.ps1` を実行し、ご自身のユニークなパッケージ名へ変更します。
2. 端末の **設定 → システム → 開発者向けオプション** から **USB デバッグ**（または **ワイヤレスデバッグ**）を有効にし、USB ケーブルまたは `hdc tconn <IP>:<ポート>` で接続して `hdc list targets` に表示されることを確認します。
3. **DevEco Studio** でリポジトリの `harmony/` ディレクトリを開き、Sync 完了を待ちます。
4. **File → Project Structure → Project → Signing Configs** を開き、Huawei 開発者アカウントにログインして **Automatically generate signature** をオンにし、`.p12` / `.cer` / `.p7b` を自動生成させます。
5. 上部の **Run (`entry`)** をクリックしてビルド・署名・実機インストールを行います。

---

### 方法 B：AGC で証明書・プロファイルを取得し CLI で署名（オフライン・複数端末向け）

`scripts/build_hap.ps1` を使ってコマンドラインからビルド・署名する場合：

#### 1. ローカルキーストア（`.p12`）と CSR（`.csr`）を作成

HarmonyOS SDK 同梱の `hap-sign-tool.jar`（通常 `%LOCALAPPDATA%\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar`）を使用します：

```powershell
New-Item -ItemType Directory -Force -Path harmony\signing | Out-Null

# 1) ECC NIST-P-256 鍵ペアを生成
java -jar "$env:LOCALAPPDATA\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar" generate-keypair `
  -keyAlias "your_alias" `
  -keyPwd "YourStrongPassword" `
  -keyAlg ECC -keySize NIST-P-256 `
  -keystoreFile "harmony\signing\app.p12" `
  -keystorePwd "YourStrongPassword"

# 2) CSR リクエストファイルを出力
java -jar "$env:LOCALAPPDATA\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar" generate-csr `
  -keyAlias "your_alias" `
  -keyPwd "YourStrongPassword" `
  -subject "C=CN,O=Developer,OU=Developer,CN=your_alias" `
  -signAlg SHA256withECDSA `
  -keystoreFile "harmony\signing\app.p12" `
  -keystorePwd "YourStrongPassword" `
  -outFile "harmony\signing\app.csr"
```

#### 2. Huawei AGC でデバッグ証明書（`.cer`）とプロファイル（`.p7b`）を発行

1. **Huawei Developers → AppGallery Connect → Certificates, APP IDs, and Profiles** を開きます：
   - **Certificates** から **Debug** 証明書を作成し、`app.csr` をアップロードして `.cer` をダウンロードし `harmony/signing/` に配置します。
   - **Devices** に実機の UDID（`hdc shell bm get -u` で取得）を登録します。
   - ステップ 1 で変更した `bundleName` を使ってプロジェクトおよび HarmonyOS アプリを作成します（重複エラー時は別名に変えて `set_bundle_name.ps1` を再実行）。
2. **Profiles** から対象アプリの **Debug Profile** を作成します：
   - 上記 Debug 証明書と実機 UDID を選択します。
   - **ACL 制限権限**：本アプリの 10 権限はすべて `normal` レベルのため（[README.ja.md](../README.ja.md#アプリ権限0-acl) 参照）、**ACL 制限権限は一切チェックせず空のまま申請してください**。
   - ダウンロードした `.p7b` を `harmony/signing/` に配置します。

#### 3. CLI でのビルド・署名・インストール

`harmony/signing/` は `.gitignore` 対象です。`.cer`・`.p7b`・`.p12` を 1 組配置し、パスワードを `harmony/signing/keystore-password.txt` に記載（または `$env:HAP_SIGN_PASSWORD` に設定）した上で実行します：

```powershell
# Debug Profile は既定の -Mode debug、Release Profile は -Mode release を指定
pwsh -File scripts/build_hap.ps1 -KeyAlias "your_alias" -Clean

# 接続中の実機へ上書きインストール
hdc install -r harmony/entry/build/default/outputs/default/entry-default-debug-signed.hap
```

> 署名資材を配置せずに `pwsh -File scripts/build_hap.ps1` を実行した場合は、未署名 HAP（`entry-default-unsigned.hap`）のみを出力して正常終了します。

---

## よくあるインストール／署名エラー対処表（FAQ）

| エラー現象・メッセージ | 主な原因 | 解決方法 |
|---|---|---|
| `9568289 error: install failed due to grant request permissions failed` | `.p7b` の ACL 権限不足、または古い `system_basic` 権限が残存 | `v2.0.2.7.1+` 以降のコードを使用しているか確認（`allowed-acls` は空、`module.json5` は 10 個の `normal` 権限のみ） |
| AGC で予約語または無効なパッケージ名と表示される | `oh` / `ohos` / `harmony` / `harmonyos` / `openharmony` / `system` が単独セグメントに含まれている | 予約セグメントを避けた逆ドメイン名に変更し `scripts/set_bundle_name.ps1` を再実行 |
| AGC／自動署名で「パッケージ名が既に使用中」と表示される | `com.ehviewer.next` や短い一般名が他者により取得済み | `com.<your_handle>.ehviewer` など一意の名前へ変更して `scripts/set_bundle_name.ps1` を再実行 |
| `install failed due to verify signature failed` / UDID 不一致 | 端末 UDID が `.p7b` に未登録、または HAP の `bundleName` と `.p7b` の `bundle-name` が不一致 | `hdc shell bm get -u` で UDID を確認し AGC で `.p7b` に追加・再取得、`app.json5` との一致を確認 |
| Debug `.p7b` で `-Mode release` を署名してインストール失敗 | HarmonyOS は **Debug Profile と `-Mode debug`、Release Profile と `-Mode release` の一致**を厳格に検証します | 個人検証用 Debug 証明書では `-Mode debug` を指定してください |
| 同パッケージ名の別署名アプリが端末にあり上書き失敗 | 端末上の既存アプリが異なる証明書で署名されている | 既存アプリをアンインストールしてから再インストールするか、別の `bundleName` で導入 |
