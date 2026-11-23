# Bundle Renaming, Signing & Device Installation Guide

[简体中文](./SIGNING.md) | **English** | [日本語](./SIGNING.ja.md)

> [!IMPORTANT]
> **Why can't the unsigned HAP in GitHub Releases be directly re-signed and installed with a personal certificate?**
> - Inside a built `.hap` archive, `module.json`, `pack.info`, and desktop shortcut metadata hardcode the `bundleName` chosen at compile time (`com.ehviewer.next` by default in this repository).
> - HarmonyOS device installation (BMS) strictly enforces that **`bundleName` inside the HAP matches `bundle-name` in the `.p7b` provisioning profile**, and bundle names in Huawei AppGallery Connect (AGC) are globally unique across all developer accounts.
> - Therefore, **the unsigned HAP attached to GitHub Releases is intended for build archival, SHA-256 verification, and signing by the `com.ehviewer.next` holder only. All other developers wishing to install on a device should clone the source code, run the bundle-renaming script below, and compile & sign with their own certificate.**

---

## Step 1: Set Your Own Unique Bundle Name (Avoid Reserved Segments)

Huawei AGC enforces the following rules for HarmonyOS `bundleName` values:
1. Total length **7 to 128** characters in reverse-domain format (at least 3 dot-separated segments, e.g., `com.yourname.ehviewer`), using only lowercase letters, digits, `_`, and `.` (uppercase letters and `-` are rejected).
2. Globally unique in AGC (default `com.ehviewer.next` is already taken).
3. **Must NOT use any of Huawei's 6 reserved words as a standalone segment** (case-insensitive):
   - `oh`, `ohos`, `harmony`, `harmonyos`, `openharmony`, `system`
   - For example, `com.ehviewer.harmony` or `ohos.app.ehviewer` will be rejected during automatic signing or AGC app creation.

Use the bundled script to update all 4 project references in one step (compatible with both Windows PowerShell 5.1 and PowerShell 7):

```powershell
# Preview modified files without writing to disk
pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer -DryRun

# Apply the change (validates format & 6 reserved segments, writes UTF-8 without BOM + LF)
pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer
```

Files updated automatically:
- `harmony/AppScope/app.json5` (`app.bundleName`)
- `harmony/entry/src/main/resources/base/profile/shortcuts_config.json` (both `bundleName` entries)
- `harmony/entry/src/main/ets/hippo/ehviewer/download/DownloadService.ets` (`SLOT_ID` & fallback bundle name)
- `harmony/entry/src/main/ets/hippo/ehviewer/download/ArchiverDownloadService.ets` (`SLOT_ID` & fallback bundle name)

---

## Step 2: Choose a Signing Method to Build & Install

### Option A: DevEco Studio Automatic Signing (Recommended for Personal Device Testing)

1. Run `scripts/set_bundle_name.ps1` above to switch to your own unique bundle name.
2. On your phone/tablet, enable **Developer options -> USB debugging** (or **Wireless debugging**), connect via USB cable or `hdc tconn <IP>:<port>`, and confirm the device appears in `hdc list targets`.
3. Open the `harmony/` directory in **DevEco Studio** and wait for Sync to complete.
4. Go to **File -> Project Structure -> Project -> Signing Configs**, sign in to your Huawei Developer account, and enable **Automatically generate signature** to generate `.p12`, `.cer`, and `.p7b`.
5. Click **Run (`entry`)** to compile, sign, and install directly onto your device.

---

### Option B: Manual AGC Certificate + CLI Build & Sign (Stable Offline / Multi-Device Workflow)

If you prefer CLI packaging via `scripts/build_hap.ps1`:

#### 1. Generate a Local Keystore (`.p12`) and CSR (`.csr`)

Use `hap-sign-tool.jar` from your HarmonyOS SDK (`%LOCALAPPDATA%\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar`):

```powershell
New-Item -ItemType Directory -Force -Path harmony\signing | Out-Null

# 1) Generate ECC NIST-P-256 key pair
java -jar "$env:LOCALAPPDATA\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar" generate-keypair `
  -keyAlias "your_alias" `
  -keyPwd "YourStrongPassword" `
  -keyAlg ECC -keySize NIST-P-256 `
  -keystoreFile "harmony\signing\app.p12" `
  -keystorePwd "YourStrongPassword"

# 2) Export CSR file
java -jar "$env:LOCALAPPDATA\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar" generate-csr `
  -keyAlias "your_alias" `
  -keyPwd "YourStrongPassword" `
  -subject "C=CN,O=Developer,OU=Developer,CN=your_alias" `
  -signAlg SHA256withECDSA `
  -keystoreFile "harmony\signing\app.p12" `
  -keystorePwd "YourStrongPassword" `
  -outFile "harmony\signing\app.csr"
```

#### 2. Apply for Debug Certificate (`.cer`) & Profile (`.p7b`) in Huawei AGC

1. Open **Huawei Developers -> AppGallery Connect -> Certificates, APP IDs, and Profiles**:
   - Under **Certificates**, create a **Debug** certificate using `app.csr` and place the downloaded `.cer` inside `harmony/signing/`.
   - Under **Devices**, register your device's UDID (`hdc shell bm get -u`).
   - Create a project and HarmonyOS app using your renamed `bundleName` from Step 1 (if already taken, choose another unique name and re-run `set_bundle_name.ps1`).
2. Under **Profiles**, create a **Debug Profile** for that app:
   - Select your Debug certificate and registered device UDID(s).
   - **Restricted ACL Permissions**: All 10 permissions declared by the current build are `normal` (see [README.en.md](../README.en.md#permissions-0-acl)), so **leave all restricted ACL permissions unchecked**.
   - Place the downloaded `.p7b` inside `harmony/signing/`.

#### 3. Package, Sign & Install via CLI

`harmony/signing/` is gitignored. Place a single set of `.cer`, `.p7b`, and `.p12` there and store the keystore password in `harmony/signing/keystore-password.txt` (or set `$env:HAP_SIGN_PASSWORD`):

```powershell
# Debug Profile matches default -Mode debug; Release Profile requires -Mode release
pwsh -File scripts/build_hap.ps1 -KeyAlias "your_alias" -Clean

# Install onto connected device
hdc install -r harmony/entry/build/default/outputs/default/entry-default-debug-signed.hap
```

> Without local signing files, `pwsh -File scripts/build_hap.ps1` still succeeds and outputs the unsigned HAP (`entry-default-unsigned.hap`).

---

## Troubleshooting FAQ

| Symptom / Error | Likely Cause | Resolution |
|---|---|---|
| `9568289 error: install failed due to grant request permissions failed` | `.p7b` lacks ACL permissions requested by older builds or restricted `system_basic` permissions were added | Ensure you are on `v2.0.2.7.1+` (`allowed-acls` should be empty, with only 10 `normal` permissions in `module.json5`) |
| AGC reports reserved keywords / invalid bundle name | Bundle name contains a standalone `oh`, `ohos`, `harmony`, `harmonyos`, `openharmony`, or `system` segment | Choose a reverse-domain name without reserved segments and run `scripts/set_bundle_name.ps1` |
| AGC / Auto-sign says bundle name is already occupied | `com.ehviewer.next` or short common names are already registered by others | Pick a unique personal name such as `com.<your_handle>.ehviewer` and re-run `scripts/set_bundle_name.ps1` |
| `install failed due to verify signature failed` / UDID mismatch | Target device UDID is missing in `.p7b`, or HAP `bundleName` differs from `.p7b` `bundle-name` | Check UDID with `hdc shell bm get -u`, add it to the `.p7b` in AGC, re-download `.p7b`, and verify `app.json5` matches |
| Signed `-Mode release` HAP fails to install with Debug `.p7b` | HarmonyOS strictly pairs Debug Profiles with `-Mode debug` and Release Profiles with `-Mode release` | Use `-Mode debug` for personal debug certificates; request a Release cert & profile for `-Mode release` |
| Overwrite install fails when the same `bundleName` was previously signed with a different cert | Existing app on device was signed with another certificate | Uninstall the existing app with that bundle name first (or install under a distinct `bundleName`) |
