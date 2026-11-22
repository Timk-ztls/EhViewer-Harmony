/**
 * 迁移自 app/src/main/java/com/hippo/widget/lockpattern/LockPatternUtils.java（inventory S0529，上游 67 行）
 *
 * 逐条对应（无简化）：
 *   stringToPattern(String)       → LockPatternUtils.stringToPattern(str)
 *   patternToString(List<Cell>)   → LockPatternUtils.patternToString(pattern)
 *   isPatternVaild(String)        → LockPatternUtils.isPatternVaild(str)  ← 上游拼写即 "Vaild"，为保证调用点 1:1 保留，不改名
 *
 * 序列化协议差异（关键）：
 *   上游把每个 cell 编码成 **一个字节** (row*3+column)，再 new String(bytes) —— 依赖平台默认字符集
 *   （Android 上为 UTF-8），所得字符串是 0x00–0x08 的控制字符序列。
 *   鸿蒙侧若用 stringToPattern 的对称实现同样按「一字符 = 一字节」，则必须保证 charCode 0–8 一一对应。
 *   本实现显式按 charCodeAt 处理（不用 any 编码 API），从而与上游 UTF-8 编码在 0x00–0x08 区间**字节一致**：
 *   0x00–0x08 在 UTF-8 中都是单字节编码，故 "一个 char ↔ 一个 byte" 成立。
 *   持久化调用方（ui-scene 的 LockPattern 页面）如果把它写进 SharedPreferences/Preferences，
 *   写出的字节序列与 Android 端完全相同，可与旧数据互通。
 */
import { Cell } from './LockPatternCell';

export class LockPatternUtils {
  /**
   * Deserialize a pattern.
   * @param str 由 patternToString 序列化的字符串
   */
  static stringToPattern(str: string): Cell[] {
    const result: Cell[] = [];
    for (let i = 0; i < str.length; i++) {
      const b: number = str.charCodeAt(i);
      result.push(Cell.of(Math.floor(b / 3), b % 3));
    }
    return result;
  }

  /**
   * Serialize a pattern.
   * @param pattern 图案单元序列；null 视为空串（与上游一致）
   */
  static patternToString(pattern: Cell[] | null): string {
    if (pattern === null) {
      return '';
    }
    let res: string = '';
    for (let i = 0; i < pattern.length; i++) {
      const cell: Cell = pattern[i];
      res += String.fromCharCode(cell.getRow() * 3 + cell.getColumn());
    }
    return res;
  }

  /** 上游方法名拼写即 Vaild，保留以对齐调用点 */
  static isPatternVaild(pattern: string): boolean {
    const len: number = pattern.length;
    if (len <= 9 && len >= 2) {
      for (let i = 0; i < len; i++) {
        const b: number = pattern.charCodeAt(i);
        if (b >= 9 || b < 0) {
          return false;
        }
      }
      return true;
    }
    return false;
  }
}
