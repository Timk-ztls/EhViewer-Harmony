/**
 * 迁移自 app/src/main/java/com/hippo/widget/DateUtils.java（inventory S0517，上游 63 行）
 *
 * 纯逻辑，逐行搬（本类无 Android 依赖，可整段照抄）：
 *   QUOTE / SECONDS 常量
 *   hasSeconds(CharSequence)
 *   hasDesignator(CharSequence, char)
 *   skipQuotedText(CharSequence, i, len)
 *
 * 用途：TextClock 判断时间格式串里是否含秒位（'s'），需正确跳过 '' 引号内的字面量，
 *     以及 ''（两个单引号）本身表示一个单引号字符。
 * 差异：上游 CharSequence 空判断用 null；ArkTS 里 string 无 null，故用可选参数 + undefined 判断，
 *      null/undefined 都返回 false（与上游一致）。
 */
export class DateUtils {
  static readonly QUOTE: string = '\'';
  static readonly SECONDS: string = 's';

  static hasSeconds(inFormat: string | undefined | null): boolean {
    return DateUtils.hasDesignator(inFormat, DateUtils.SECONDS);
  }

  static hasDesignator(inFormat: string | undefined | null, designator: string): boolean {
    if (inFormat === undefined || inFormat === null) {
      return false;
    }
    const length: number = inFormat.length;
    let i: number = 0;
    while (i < length) {
      let count: number = 1;
      const c: string = inFormat.charAt(i);
      if (c === DateUtils.QUOTE) {
        count = DateUtils.skipQuotedText(inFormat, i, length);
      } else if (c === designator) {
        return true;
      }
      i += count;
    }
    return false;
  }

  private static skipQuotedText(s: string, i: number, len: number): number {
    if (i + 1 < len && s.charAt(i + 1) === DateUtils.QUOTE) {
      return 2;
    }
    let count: number = 1;
    // skip leading quote
    i++;
    while (i < len) {
      const c: string = s.charAt(i);
      if (c === DateUtils.QUOTE) {
        count++;
        // QUOTEQUOTE -> QUOTE
        if (i + 1 < len && s.charAt(i + 1) === DateUtils.QUOTE) {
          i++;
        } else {
          break;
        }
      } else {
        i++;
        count++;
      }
    }
    return count;
  }
}
