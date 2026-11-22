/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0496   上游: com/hippo/util/PackageUtils.kt（71 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/PackageUtils.ets
 *
 * 两个方法：
 *   · `getSignature(context, packageName)` —— 取第一个签名证书的原始字节，交给 `computeSHA1`
 *   · `computeSHA1(certRaw)` —— **纯逻辑**：SHA1 → `AA:BB:CC:…` 大写冒号分隔（59 字符）
 *
 * 平台差异：
 *  1. `PackageManager.GET_SIGNATURES` → 鸿蒙 `bundleManager.getBundleInfoForSelf(GET_SIGNATURE_INFO)`
 *     + `signatureInfo.fingerprint`（**注意：鸿蒙直接给的是指纹字符串，不是证书原始字节**）。
 *     故 `getSignature` 改为注入 `readCertBytes(packageName)`，返回 null 表示取不到；
 *     SHA1 计算本身仍由本文件的 `computeSHA1` 完成（保持与上游一致的输出格式）。
 *  2. `MessageDigest.getInstance("SHA1")` → 注入 `sha1(bytes)`（`@ohos.security.cryptoFramework`
 *     的 `cryptoFramework.createMd('SHA1')`），本类不直接依赖加密框架。
 *  3. **`uppercase(Locale.getDefault())` 照搬为 `toUpperCase()`**：上游用默认 Locale，
 *     而十六进制字符里没有 `i`（土耳其语 `i→İ` 的陷阱不影响 hex），故与 Locale.ROOT 结果相同。
 *     已注明：若将来格式里加入非 hex 字符，需要重新评估。
 *  4. `NoSuchAlgorithmException` → 注入函数抛错即视为取不到 → 返回 null。
 */

import hilog from '@ohos.hilog';

export class PackageUtils {

  static readonly TAG: string = 'PackageUtils';
  /** 上游 `StringBuilder(59)` 的容量提示：SHA1 是 20 字节 → 20*2 + 19 个冒号 = 59 */
  static readonly SHA1_FINGERPRINT_LENGTH: number = 59;

  /**
   * 对应上游 `getSignature(context, packageName)`：取第一个证书字节 → SHA1 串。
   * @param readCertBytes 取签名证书原始字节（取不到 → null）
   * @returns `A1:43:6B:34:…`（大写，20 段）或 null
   */
  static getSignature(packageName: string,
    readCertBytes: (packageName: string) => Uint8Array | null,
    sha1: (bytes: Uint8Array) => Uint8Array): string | null {
    try {
      const cert: Uint8Array | null = readCertBytes(packageName);
      if (cert !== null && cert.length >= 1) {
        return PackageUtils.computeSHA1(cert, sha1);
      }
      hilog.error(0x0001, PackageUtils.TAG, 'Can not find signature in package %{public}s', packageName);
    } catch (e) {
      hilog.error(0x0001, PackageUtils.TAG, 'Can not find package %{public}s: %{public}s',
        packageName, `${(e as Error).message}`);
    }
    return null;
  }

  /**
   * 对应上游 `computeSHA1(certRaw)`：
   * 逐字节 `b & 0xFF` 转两位小写十六进制、字节间补 `:`，最后整体大写。
   * @returns 形如 `A1:43:6B:34:…`；**算法抛错 → null**
   */
  static computeSHA1(certRaw: Uint8Array, sha1: (bytes: Uint8Array) => Uint8Array): string | null {
    try {
      const digest: Uint8Array = sha1(certRaw);
      const parts: string[] = [];
      for (let i = 0; i < digest.length; i++) {
        const b: number = digest[i] & 0xFF;
        let hex: string = b.toString(16);
        if (hex.length === 1) {
          hex = '0' + hex;
        }
        parts.push(hex);
      }
      // 上游：分隔符只在 i != 0 时补 → 等价 join(':')
      return parts.join(':').toUpperCase();
    } catch (e) {
      hilog.error(0x0001, PackageUtils.TAG, 'Can not final Algorithm SHA1: %{public}s',
        `${(e as Error).message}`);
      return null;
    }
  }
}
