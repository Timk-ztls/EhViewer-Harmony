/**
 * 迁移自 app/src/main/java/com/hippo/widget/TextClock.java（inventory S0547，上游 213 行）
 *
 * 上游：
 *   DEFAULT_FORMAT_12_HOUR = "hh:mm a"；DEFAULT_FORMAT_24_HOUR = "HH:mm"
 *   chooseFormat()：按系统 12/24 小时制在 mFormat12/mFormat24 间选
 *   mHasSeconds = DateUtils.hasSeconds(mFormat)
 *   onTimeChanged()：按 mFormat 格式化当前时间；没有秒位时只在分钟变化时刷新
 *
 * ArkUI 对位：
 *   组件名 TextClock → HippoTextClock（ArkUI 内置标签 `TextClock` 占用该名字）。
 *   保留 ClockFormat 纯逻辑类供单测与外部直接调用。
 */
import { ThemeElevation } from '../../common/theme/ThemeTokens';
import { DateUtils } from './DateUtils';

export class ClockFormat {
  static readonly DEFAULT_12: string = 'hh:mm a';
  static readonly DEFAULT_24: string = 'HH:mm';

  /** 上游 DateUtils.hasSeconds 的对位（供外部提前判断是否需要秒级刷新） */
  static hasSeconds(format: string): boolean {
    return DateUtils.hasSeconds(format);
  }

  private static pad2(v: number): string {
    return v < 10 ? `0${v}` : `${v}`;
  }

  /**
   * 按 token 格式化（子集：HH/H/hh/h/mm/ss/a）。
   * 上游用 ICU DateFormat：本实现对未知字符原样输出
   */
  static format(date: Date, pattern: string, is24Hour: boolean): string {
    const h24: number = date.getHours();
    const isPm: boolean = h24 >= 12;
    let h12: number = h24 % 12;
    if (h12 === 0) {
      h12 = 12;
    }
    let out: string = '';
    let i: number = 0;
    while (i < pattern.length) {
      const two: string = i + 1 < pattern.length ? pattern.substring(i, i + 2) : '';
      if (two === 'HH') {
        out += ClockFormat.pad2(is24Hour ? h24 : h24);
        i += 2;
      } else if (two === 'hh') {
        out += ClockFormat.pad2(h12);
        i += 2;
      } else if (two === 'mm') {
        out += ClockFormat.pad2(date.getMinutes());
        i += 2;
      } else if (two === 'ss') {
        out += ClockFormat.pad2(date.getSeconds());
        i += 2;
      } else if (pattern.charAt(i) === 'H') {
        out += `${h24}`;
        i += 1;
      } else if (pattern.charAt(i) === 'h') {
        out += `${h12}`;
        i += 1;
      } else if (pattern.charAt(i) === 'a') {
        out += isPm ? 'PM' : 'AM';
        i += 1;
      } else {
        out += pattern.charAt(i);
        i += 1;
      }
    }
    return out;
  }
}

/**
 * 组件名 TextClock → **HippoTextClock**：ArkUI 内置标签 `TextClock` 占用了该名字
 * （编译报 reserved tag name）；文件路径仍是契约的 hippo/widget/TextClock.ets，逻辑类 ClockFormat 不变。
 */
@Component
export struct HippoTextClock {
  /** 上游 DEFAULT_FORMAT_12_HOUR / DEFAULT_FORMAT_24_HOUR */
  @Prop @Watch('onFormatChanged') format12: string = ClockFormat.DEFAULT_12;
  @Prop @Watch('onFormatChanged') format24: string = ClockFormat.DEFAULT_24;
  /** 上游 chooseFormat() 依赖系统 12/24 制；鸿蒙侧由调用方传入 */
  @Prop @Watch('onFormatChanged') is24HourMode: boolean = true;
  @Prop fontSize: number = 14;
  @Prop fontColor: ResourceColor = '#FFFFFFFF';
  /** 可选文字阴影（供阅读器亮色页边距下保持对比度） */
  textShadowOptions: ShadowOptions | null = null;
  /** 无秒位时的刷新条件（对位上游"只在秒数为 0 时刷新"） */
  @State text: string = '';

  private timerId: number = -1;
  private lastMinute: number = -1;

  private currentFormat(): string {
    return this.is24HourMode ? this.format24 : this.format12;
  }

  private onFormatChanged(): void {
    this.lastMinute = -1;
    this.refresh();
  }

  private refresh(): void {
    const now: Date = new Date();
    const format: string = this.currentFormat();
    const hasSeconds: boolean = ClockFormat.hasSeconds(format);
    if (!hasSeconds && now.getMinutes() === this.lastMinute) {
      return; // 上游：无秒位且分钟未变 → 不刷新
    }
    this.lastMinute = now.getMinutes();
    this.text = ClockFormat.format(now, format, this.is24HourMode);
  }

  aboutToAppear(): void {
    this.refresh();
    this.timerId = setInterval((): void => {
      this.refresh();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  build() {
    Text(this.text)
      .fontSize(this.fontSize)
      .fontColor(this.fontColor)
      .maxLines(1)
      .textShadow(this.textShadowOptions !== null ? this.textShadowOptions : ThemeElevation.none())
  }
}
