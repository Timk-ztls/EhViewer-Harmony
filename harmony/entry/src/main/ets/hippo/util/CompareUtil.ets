/*
 * 上游：无对应文件（ArkTS 工具类，用于**统一 Java 字符串比较语义**）
 *
 * 为什么必须单独一个文件（storage-db c7 的结论）：
 *   Java 的 `String.compareTo` / `compareToIgnoreCase` 是**逐 UTF-16 码元**比较，
 *   而 JS/ArkTS 的 `String.prototype.localeCompare` 走 **locale 规则**（不同设备/语言下结果不同），
 *   `Intl.Collator` 更是明确按语言排序。移植时若顺手写 `a.localeCompare(b)`，
 *   在中文/日文设备上会得到与上游**不同**的排序 —— 而且是"看起来差不多、偶尔不同"的那种错。
 *
 * 语义对照（严格照 Java）：
 *   `a.compareTo(b)`：
 *     ① 逐位比 `charAt(i)`：第一个不同处返回 `a_i - b_i`（**差值**，不保证 ±1）
 *     ② 前缀相同则返回 `a.length - b.length`（**长度差**，不是 ±1）
 *     ③ 空串与任意串比：`"" < "a"`；`"a" < "ab"`
 *   `a.compareToIgnoreCase(b)`：
 *     ① 逐位先取 `charAt(i)`，**相同则直接跳过**；不同才做**单码元大写折叠**再比
 *        （Java 实现用的是 `Character.toUpperCase(char)`，逐 char，**不做**全串 `toUpperCase`）
 *     ② 其余同 `compareTo`
 *
 * 本项目里这两条语义的真实调用点（已核对上游）：
 *   - `ArchiverDownloadCompleter.kt:129`：`file1.name.compareTo(file2.name)` —— **码元序**
 *     → 本仓 `ArchiverDownloadCompleter.planImportOrder` 原先误用 `localeCompare`，已改成本类
 *   - `DownloadListInfosExecutor.java:250/270`：`titleI.compareToIgnoreCase(titleJ)` —— **大小写无关码元序**
 *     → 本仓 `DownloadListInfosExecutor` 已自带等价实现（注释里写明不能用 localeCompare）
 *
 * 为什么不做成"全局替换 `localeCompare`"：`localeCompare` 在**用户可见的排序**里是合法选择
 * （例如按语言习惯排标签名）。只有"上游用 compareTo/compareToIgnoreCase"的地方才必须码元序。
 */

export class CompareUtil {
  /**
   * 等价 Java `String.compareTo`：逐 UTF-16 码元比较。
   * @returns 首个不同码元的差值；前缀相同则返回长度差；完全相等返回 0
   */
  static compareCodeUnits(a: string, b: string): number {
    const min: number = Math.min(a.length, b.length);
    for (let i = 0; i < min; i++) {
      const ca: number = a.charCodeAt(i);
      const cb: number = b.charCodeAt(i);
      if (ca !== cb) {
        return ca - cb;
      }
    }
    // 前缀相同：短的在前（Java 返回 a.length - b.length）
    return a.length - b.length;
  }

  /**
   * 等价 Java `String.compareToIgnoreCase`：逐码元比较，**仅在该位不同时**做单码元大写折叠。
   * 注意：Java 用 `Character.toUpperCase(char)`（单字符），不是整串 `toUpperCase()`。
   */
  static compareIgnoreCase(a: string, b: string): number {
    const min: number = Math.min(a.length, b.length);
    for (let i = 0; i < min; i++) {
      const ca: number = a.charCodeAt(i);
      const cb: number = b.charCodeAt(i);
      if (ca === cb) {
        continue;
      }
      const ua: number = CompareUtil.toUpperCaseCode(ca);
      const ub: number = CompareUtil.toUpperCaseCode(cb);
      if (ua !== ub) {
        return ua - ub;
      }
    }
    return a.length - b.length;
  }

  /**
   * 单码元大写折叠（等价 `Character.toUpperCase(char)`）。
   * 只处理 **BMP 单码元**：不处理需要代理对的字符（`Character.toUpperCase(char)` 同样不处理，
   * 它对代理对的两半分别返回自身），所以这里的 `String.fromCharCode` 做法与 Java 等价。
   */
  private static toUpperCaseCode(code: number): number {
    // ASCII 快路径（Java 的 CharacterData 对 ASCII 也是这条规则）
    if (code >= 97 && code <= 122) {
      return code - 32;
    }
    const s: string = String.fromCharCode(code).toUpperCase();
    // 折叠后可能变成 1 个码元（BMP）或 2 个（少数字符如 ß→SS）；Java 的 char 版只取单码元结果，
    // 这里同样只取首码元，保证与 `Character.toUpperCase(char)` 一致。
    return s.length > 0 ? s.charCodeAt(0) : code;
  }

  /**
   * 便捷：把 `compareCodeUnits` 包成 `sort()` 的比较器（避免各处重复写箭头函数）。
   */
  static codeUnitComparator(a: string, b: string): number {
    return CompareUtil.compareCodeUnits(a, b);
  }
}
