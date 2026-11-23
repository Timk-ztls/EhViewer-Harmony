# 签名、改包名与真机安装指南

**简体中文** | [English](./SIGNING.en.md) | [日本語](./SIGNING.ja.md)

> [!IMPORTANT]
> **为什么 GitHub Releases 里的未签名 HAP 不能直接拿来用个人证书重签安装？**
> - HAP 包内的 `module.json`、`pack.info` 和桌面快捷方式在编译期就已经写死了 `bundleName`（本项目默认为 `com.ehviewer.next`）。
> - 鸿蒙真机安装（BMS）强制要求 **HAP 内 `bundleName` 与 `.p7b` Profile 中的 `bundle-name` 完全一致**；且华为 AGC 的包名全网唯一，已被占用的包名无法再由其他开发者签出 `.p7b`。
> - 因此：**GitHub Releases 附带的未签名 HAP 仅用于发布产物归档、SHA-256 校验及包名持有者自签；所有其他开发者想真机安装，请按本文档克隆源码 → 一键修改包名 → 重新签名编译安装。**

---

## 第一步：修改为自己的包名（必须避开华为保留段）

华为 AGC 对 HarmonyOS 应用包名有以下硬性约束：
1. 长度 **7 ~ 128** 个字符，采用反向域名格式（至少 3 段，如 `com.yourname.ehviewer`），仅允许小写字母、数字、`_` 和 `.`（不允许 `-` 或大写字母）。
2. 全网唯一，不能与 AGC 上其他开发者已注册的包名冲突（默认包名 `com.ehviewer.next` 已被占用，供参考对齐）。
3. **禁止将华为保留词作为独立包名段**（大小写均拦截）：
   - `oh`、`ohos`、`harmony`、`harmonyos`、`openharmony`、`system`
   - 例如 `com.ehviewer.harmony`、`ohos.app.ehviewer` 都会在自动签名/AGC 注册时直接被拒。

使用仓库内置脚本一键更新全部 4 处包名位置（兼容 Windows PowerShell 5.1 与 PowerShell 7）：

```powershell
# 预览将修改的文件（不写入磁盘）
pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer -DryRun

# 正式写入（会自动校验格式与 6 个保留段，并以 UTF-8 无 BOM + LF 写回）
pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer
```

脚本会同步更新以下 4 处：
- `harmony/AppScope/app.json5`（`app.bundleName`）
- `harmony/entry/src/main/resources/base/profile/shortcuts_config.json`（2 处 `bundleName`）
- `harmony/entry/src/main/ets/hippo/ehviewer/download/DownloadService.ets`（`SLOT_ID` 与默认回退 `bundleName`）
- `harmony/entry/src/main/ets/hippo/ehviewer/download/ArchiverDownloadService.ets`（`SLOT_ID` 与默认回退 `bundleName`）

---

## 第二步：选择一种签名方式编译安装

### 方式 A：DevEco Studio 自动签名（最推荐，适合真机调试）

1. 先执行上面的 `scripts/set_bundle_name.ps1` 将包名改为你自己的唯一包名。
2. 手机/平板进入 **设置 → 系统 → 开发者选项**，开启 **USB 调试** 或 **无线调试**，并用 USB 数据线或 `hdc tconn <IP>:<端口>` 连上电脑，确认设备列表可见。
3. 使用 **DevEco Studio** 打开仓库下的 `harmony/` 目录，等待 Sync 完成。
4. 打开 **File → Project Structure → Project → Signing Configs**，登录你的华为开发者账号并勾选 **Automatically generate signature**，等待自动签发 `.p12` / `.cer` / `.p7b`。
5. 点击顶部 **Run (`entry`)** 即可直接编译、自动签名并安装到真机。

---

### 方式 B：向华为 AGC 申请证书并命令行签名（离线/多设备稳定方案）

如果你偏好命令行打包，或需要用 `scripts/build_hap.ps1` 自动产出已签名 HAP：

#### 1. 生成本地密钥库（`.p12`）与签名请求（`.csr`）

使用 SDK 自带的 `hap-sign-tool.jar`（路径通常位于 `%LOCALAPPDATA%\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar`）：

```powershell
New-Item -ItemType Directory -Force -Path harmony\signing | Out-Null

# 1) 生成 ECC NIST-P-256 密钥对
java -jar "$env:LOCALAPPDATA\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar" generate-keypair `
  -keyAlias "your_alias" `
  -keyPwd "YourStrongPassword" `
  -keyAlg ECC -keySize NIST-P-256 `
  -keystoreFile "harmony\signing\app.p12" `
  -keystorePwd "YourStrongPassword"

# 2) 导出 CSR 请求文件
java -jar "$env:LOCALAPPDATA\Huawei\Sdk\20\toolchains\lib\hap-sign-tool.jar" generate-csr `
  -keyAlias "your_alias" `
  -keyPwd "YourStrongPassword" `
  -subject "C=CN,O=Developer,OU=Developer,CN=your_alias" `
  -signAlg SHA256withECDSA `
  -keystoreFile "harmony\signing\app.p12" `
  -keystorePwd "YourStrongPassword" `
  -outFile "harmony\signing\app.csr"
```

#### 2. 在华为 AppGallery Connect（AGC）申请 `.cer` 与 `.p7b`

1. 进入 **华为开发者联盟 → AppGallery Connect → 证书、APP ID 和 Profile**：
   - 在 **证书管理** 新增 **调试证书**，上传上一步生成的 `app.csr`，下载签发的 `.cer` 放到 `harmony/signing/`。
   - 若尚未注册设备，连接真机执行 `hdc shell bm get -u` 获取 **UDID** 并登记到 **设备管理**。
   - 用你修改后的包名（与第一步一致）创建项目及应用；如提示包名已被占用，换一个你自己的包名再重新跑一次 `set_bundle_name.ps1`。
2. 在 **Profile 管理** 为该应用申请 **调试（Debug）Profile**：
   - 勾选刚才的调试证书与测试设备 UDID；
   - **受限 ACL 权限说明**：当前版本声明的 10 项权限全部为 `normal` 等级（详见 [README.md](../README.md#应用权限说明)），**申请 Profile 时 ACL 受限权限列表保持全部不勾选 / 留空即可**；
   - 下载签发的 `.p7b` 放到 `harmony/signing/`。

#### 3. 命令行打包、签名与安装

`harmony/signing/` 已被 `.gitignore` 忽略。放入仅有的 1 套 `.cer`、`.p7b`、`.p12` 并写入密钥口令（或在环境变量设置 `$env:HAP_SIGN_PASSWORD`）后：

```powershell
# 推荐把口令放在 harmony/signing/keystore-password.txt（或设置 $env:HAP_SIGN_PASSWORD）
# 调试 Profile 对应默认 -Mode debug；若申请了发布证书与发布 Profile，则传 -Mode release
pwsh -File scripts/build_hap.ps1 -KeyAlias "your_alias" -Clean

# 安装到已连接的设备
hdc install -r harmony/entry/build/default/outputs/default/entry-default-debug-signed.hap
```

> 若在无签名材料的环境下直接执行 `pwsh -File scripts/build_hap.ps1`，脚本会自动只输出未签名 HAP（`entry-default-unsigned.hap`）并正常退出。

---

## 常见装机与签名报错排查（FAQ）

| 报错现象 / 关键字 | 常见原因 | 解决方法 |
|---|---|---|
| `9568289 error: install failed due to grant request permissions failed` | `.p7b` 缺少高权限 ACL，或误加了 `system_basic` 权限（如旧版 `READ_PASTEBOARD` / `NOTIFICATION_CONTROLLER`） | 确认使用最新仓库代码（`v2.0.2.7.1+` 已去除所有高权限依赖，`allowed-acls` 需为空即可通过）；检查 `module.json5` 无多余受限权限 |
| AGC 提示包名包含保留字或不可用 | 包名中出现了 `oh` / `ohos` / `harmony` / `harmonyos` / `openharmony` / `system` 任一独立段 | 更换为不含保留段的反向域名包名，运行 `scripts/set_bundle_name.ps1` 重写工程 |
| AGC / 自动签名提示包名已被占用 | 默认包名 `com.ehviewer.next` 或常见短包名已被他人注册 | 改为带个人标识的唯一包名（例如 `com.<github_handle>.ehviewer`）并重跑 `scripts/set_bundle_name.ps1` |
| `install failed due to verify signature failed` / UDID 不匹配 | 当前真机 UDID 未加入 `.p7b`，或 HAP 内 `bundleName` 与 `.p7b` 的 `bundle-name` 不一致 | 用 `hdc shell bm get -u` 核对设备 UDID，确认已在 AGC 勾选该设备并重新下载 `.p7b`；核对 `app.json5` 与 `.p7b` 包名一致 |
| 使用 Debug `.p7b` 给 `-Mode release` 签名装机失败 | 华为鸿蒙严格校验 **Debug Profile 只能配 Debug 构建，Release Profile 只能配 Release 构建** | 自己真机调试请使用 `-Mode debug`；需要分发/上架时再向 AGC 申请正式发布证书与 Release Profile 并传 `-Mode release` |
| 设备上已装过同包名但签名不同导致覆盖安装失败 | 旧包使用另一套证书签名（例如早期本地开发签名包或他人重签名包） | 需先卸载设备上原同包名应用后再安装（或使用不同 `bundleName` 共存） |
