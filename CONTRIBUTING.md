# Contributing to EhViewer for HarmonyOS

感谢对 **EhViewer for HarmonyOS** 的关注与贡献！提交 Pull Request 或本地开发时请遵守以下约定，以保证 CI 门禁一次性通过。

## 开发前检查清单

1. **包名与本地签名材料隔离**：
   - 如需在真机运行，请先用 `pwsh -File scripts/set_bundle_name.ps1 -BundleName <你的包名>` 修改为自己的包名，**除非刻意变更默认包名，否则请勿把你个人测试包名提交进 PR**。
   - **严禁提交**任何 `.cer`、`.p12`、`.p7b`、`.csr`、`keystore-password.txt` 或 `harmony/signing/` 目录内容。
   - `harmony/build-profile.json5` 中的 `signingConfigs` 必须始终保持 `[]`。

2. **权限最小化原则**：
   - 严禁未经讨论在 `harmony/entry/src/main/module.json5` 中新增 `system_basic` / ACL 受限权限（例如 `ohos.permission.READ_PASTEBOARD`），避免导致社区开发者开启自动签名后无法安装 HAP。

3. **行尾与编码规范**：
   - 所有文本与源码文件须使用 **UTF-8 无 BOM + LF** 行尾。可运行以下命令自动规范并核验：
     ```powershell
     pwsh -File scripts/check_line_endings.ps1 -Fix
     pwsh -File scripts/check_line_endings.ps1 -Gate
     ```

4. **提交前必跑门禁与单元测试**：
   ```powershell
   # 首次初始化 TypeScript 5.4.5 与 @ohos.* / @kit.* 测试桩
   pwsh -File scripts/setup_tscheck.ps1

   # 静态门禁
   pwsh -File scripts/check_line_endings.ps1 -Gate
   pwsh -File scripts/check_contrast.ps1 -Gate
   pwsh -File scripts/check_contrast.ps1 -Path harmony/entry/src/main/ets/hippo/ehviewer/widget -Gate
   pwsh -File scripts/check_silent_failures.ps1 -Gate
   pwsh -File scripts/check_resource_keys.ps1 -Gate

   # 全量单元测试（不得出现 assertions-n/a 或 failed > 0）
   pwsh -File scripts/run_all_tests.ps1
   ```

5. **平台差异登记**：
   - 涉及与上游 Android 行为存在平台差异的设计取舍，请同步在 [DEVIATIONS.md](./DEVIATIONS.md) 记录原因与影响范围。
