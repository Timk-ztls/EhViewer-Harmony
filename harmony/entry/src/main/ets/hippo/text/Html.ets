/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0462   上游: com/hippo/text/Html.java（969 行）
 * 目标   : harmony/entry/src/main/ets/hippo/text/Html.ets
 *
 * 【D-036】上游 `Html` 不是 HTML 解析器，而是 **`android.text.Spanned` 的编解码器**：
 *   `fromHtml`（L113/L135）用 TagSoup 的 `Parser + HTMLSchema`（外部 jar）把 HTML 解析成 Spanned；
 *   `toHtml`（L162）反向：Spanned → HTML 字符串。
 *   鸿蒙**没有 Spanned**（文本富样式用 `StyledString`/`RichText`），也没有 TagSoup。
 *   故本文件**只移植 toHtml 方向**：
 *     - `toHtml(SpannedText)` / `escapeHtml(string)` / `withinStyle` / `withinParagraph` 逐行照搬
 *     - `fromHtml` **不移植**（D-036）：UI 层用 ArkUI 的 RichText/StyledString 直接渲染 HTML 字符串
 *   不重写 TagSoup（等于重写 HTML 解析器 + 内置 300+ 条 schema，且没有测试基准），也不造假 Spanned。
 *
 * 【Spanned 的替代模型】ArkTS 侧用最小模型表达 Android 的 span 概念（**只表达 toHtml 需要的部分**）：
 *   `SpannedText { text: string; spans: TextSpan[] }`，`TextSpan { start, end, type, value }`。
 *   这不是"造平台没有的概念"——它是 XML/文本标记的通用表达（区间 + 属性），
 *   Android 的 Spanned 也只是"字符序列 + 区间标记"。**算法与上游逐行一致**，只是载体换了。
 *
 * ⚠️【上游的嵌套缺陷 —— 照搬不修，见 D-036 说明】
 *   `withinParagraph` 的**开启标签**按 span 顺序正向、类型固定序（b→i→tt→sup→sub→u→strike→a→img→font），
 *   而**闭合标签**按 span 顺序**反向**、类型固定序（font→a→strike→u→sub→sup→tt→**b→i**）。
 *   同一个 `StyleSpan` 同时带 BOLD|ITALIC 时，输出是 `<b><i>x</b></i>` —— **不严格嵌套**。
 *   上游如此，本实现**逐字保留**（含顺序），因为：
 *     1. 修了会改变已有数据的回写结果（老评论/简介导入再回写会变样）；
 *     2. 上游的 `fromHtml` 走 TagSoup 容错解析，能接受不严格嵌套，往返自洽。
 *   **但 ArkUI/浏览器的严格解析会遇到问题** —— 已在 D-036 的"残余风险"里登记，
 *   若要修，应作为**独立决策**（改 `toHtml` 输出格式 = 改对外契约）。
 */

/** span 类型（只覆盖 toHtml 需要的，对应上游 withinParagraph 里 instanceof 的那 11 种） */
export enum SpanType {
  BOLD,
  ITALIC,
  TT,
  SUPERSCRIPT,
  SUBSCRIPT,
  UNDERLINE,
  STRIKETHROUGH,
  URL,
  IMAGE,
  FONT_SIZE,
  FOREGROUND,
  ALIGN_CENTER,
  ALIGN_RIGHT,
  ALIGN_LEFT,
  QUOTE,
}

/** 一个区间标记：对应 Android 的一个 span 对象 */
export class TextSpan {
  start: number;
  end: number;
  type: SpanType;
  /** URL 的地址 / IMAGE 的 src / FONT_SIZE 的字号 / FOREGROUND 的颜色值（0xRRGGBB） */
  value: string | number | null;

  constructor(start: number, end: number, type: SpanType, value: string | number | null) {
    this.start = start;
    this.end = end;
    this.type = type;
    this.value = value;
  }
}

/** Spanned 的最小替代（见文件头"Spanned 的替代模型"） */
export class SpannedText {
  text: string;
  spans: TextSpan[];

  constructor(text: string, spans: TextSpan[]) {
    this.text = text;
    this.spans = spans;
  }

  length(): number {
    return this.text.length;
  }

  charAt(i: number): string {
    return this.text.charAt(i);
  }

  /** 对应上游 `text.getSpans(start, end, Kind)`：返回与 [start,end) 有交集且类型匹配的 span */
  getSpans(start: number, end: number, types: SpanType[]): TextSpan[] {
    const out: TextSpan[] = [];
    for (let i = 0; i < this.spans.length; i++) {
      const s: TextSpan = this.spans[i];
      if (types.indexOf(s.type) < 0) {
        continue;
      }
      // Android 语义：[start,end) 与 span 区间有交集即命中
      if (s.end > start && s.start < end) {
        out.push(s);
      }
    }
    return out;
  }

  /** 对应上游 `text.nextSpanTransition(i, limit, Kind)`：下一个 span 边界（含 limit） */
  nextSpanTransition(start: number, limit: number, types: SpanType[]): number {
    let next: number = limit;
    for (let i = 0; i < this.spans.length; i++) {
      const s: TextSpan = this.spans[i];
      if (types.indexOf(s.type) < 0) {
        continue;
      }
      if (s.start > start && s.start < next) {
        next = s.start;
      }
      if (s.end > start && s.end < next) {
        next = s.end;
      }
    }
    return next;
  }
}

const CHARACTER_TYPES: SpanType[] = [
  SpanType.BOLD, SpanType.ITALIC, SpanType.TT, SpanType.SUPERSCRIPT, SpanType.SUBSCRIPT,
  SpanType.UNDERLINE, SpanType.STRIKETHROUGH, SpanType.URL, SpanType.IMAGE,
  SpanType.FONT_SIZE, SpanType.FOREGROUND,
];
const PARAGRAPH_TYPES: SpanType[] = [SpanType.ALIGN_CENTER, SpanType.ALIGN_RIGHT, SpanType.ALIGN_LEFT];
const QUOTE_TYPES: SpanType[] = [SpanType.QUOTE];

export class Html {

  /** 对应上游 toHtml(Spanned)（L162） */
  static toHtml(text: SpannedText): string {
    const out: string[] = [];
    Html.withinHtml(out, text);
    return out.join('');
  }

  /** 对应上游 escapeHtml(CharSequence)（L171）：实体转义，用于纯文本安全嵌入 HTML */
  static escapeHtml(text: string): string {
    const out: string[] = [];
    Html.withinStyle(out, text, 0, text.length);
    return out.join('');
  }

  /** 对应上游 withinHtml（L177）：按 ParagraphStyle 分段，带 Alignment 时包 <div> */
  private static withinHtml(out: string[], text: SpannedText): void {
    const len: number = text.length();
    let next: number = 0;
    for (let i = 0; i < text.length(); i = next) {
      next = text.nextSpanTransition(i, len, PARAGRAPH_TYPES);
      const style: TextSpan[] = text.getSpans(i, next, PARAGRAPH_TYPES);
      let elements: string = ' ';
      let needDiv: boolean = false;

      for (let j = 0; j < style.length; j++) {
        needDiv = true;
        if (style[j].type === SpanType.ALIGN_CENTER) {
          elements = `align="center" ${elements}`;
        } else if (style[j].type === SpanType.ALIGN_RIGHT) {
          elements = `align="right" ${elements}`;
        } else {
          elements = `align="left" ${elements}`;
        }
      }
      if (needDiv) {
        out.push(`<div ${elements}>`);
      }

      Html.withinDiv(out, text, i, next);

      if (needDiv) {
        out.push('</div>');
      }
    }
  }

  /** 对应上游 withinDiv（L213）：QuoteSpan → <blockquote> */
  private static withinDiv(out: string[], text: SpannedText, start: number, end: number): void {
    let next: number = 0;
    for (let i = start; i < end; i = next) {
      next = text.nextSpanTransition(i, end, QUOTE_TYPES);
      const quotes: TextSpan[] = text.getSpans(i, next, QUOTE_TYPES);

      for (let q = 0; q < quotes.length; q++) {
        out.push('<blockquote>');
      }

      Html.withinBlockquote(out, text, i, next);

      for (let q = 0; q < quotes.length; q++) {
        out.push('</blockquote>\n');
      }
    }
  }

  /** 对应上游 getOpenParaTagWithDirection（L232）：上游把双向计算注释掉了，固定 ltr */
  private static getOpenParaTagWithDirection(): string {
    return '<p dir="ltr">';
  }

  /** 对应上游 withinBlockquote（L250）：按 '\n' 切段，每段一个 <p> */
  private static withinBlockquote(out: string[], text: SpannedText, start: number, end: number): void {
    out.push(Html.getOpenParaTagWithDirection());

    let next: number = 0;
    for (let i = start; i < end; i = next) {
      next = text.text.indexOf('\n', i);
      if (next < 0 || next >= end) {
        next = end;
      }

      let nl: number = 0;
      while (next < end && text.charAt(next) === '\n') {
        nl++;
        next++;
      }

      if (Html.withinParagraph(out, text, i, next - nl, nl, next === end)) {
        /* Paragraph should be closed */
        out.push('</p>\n');
        out.push(Html.getOpenParaTagWithDirection());
      }
    }

    out.push('</p>\n');
  }

  /**
   * 对应上游 withinParagraph（L279）。返回 true 表示调用方应关闭并重开段落。
   * **标签开闭顺序逐字照搬上游**（含同一 StyleSpan 的 `<b><i>…</b></i>` 不严格嵌套，见文件头）。
   */
  private static withinParagraph(out: string[], text: SpannedText,
    start: number, end: number, nl: number, last: boolean): boolean {
    let next: number = 0;
    for (let i = start; i < end; i = next) {
      next = text.nextSpanTransition(i, end, CHARACTER_TYPES);
      const style: TextSpan[] = text.getSpans(i, next, CHARACTER_TYPES);

      // ── 开启标签（正向 j，类型固定序）──
      for (let j = 0; j < style.length; j++) {
        const t: SpanType = style[j].type;
        if (t === SpanType.BOLD) {
          out.push('<b>');
        } else if (t === SpanType.ITALIC) {
          out.push('<i>');
        } else if (t === SpanType.TT) {
          out.push('<tt>');
        } else if (t === SpanType.SUPERSCRIPT) {
          out.push('<sup>');
        } else if (t === SpanType.SUBSCRIPT) {
          out.push('<sub>');
        } else if (t === SpanType.UNDERLINE) {
          out.push('<u>');
        } else if (t === SpanType.STRIKETHROUGH) {
          out.push('<strike>');
        } else if (t === SpanType.URL) {
          out.push('<a href="');
          out.push(`${style[j].value}`);
          out.push('">');
        } else if (t === SpanType.IMAGE) {
          out.push('<img src="');
          out.push(`${style[j].value}`);
          out.push('">');
          // Don't output the dummy character underlying the image.
          i = next;
        } else if (t === SpanType.FONT_SIZE) {
          // 上游：`getSize() / 6`（整数除法）
          out.push('<font size ="');
          out.push(`${Math.trunc((style[j].value as number) / 6)}`);
          out.push('">');
        } else if (t === SpanType.FOREGROUND) {
          out.push('<font color ="#');
          out.push(Html.colorToHex6(style[j].value as number));
          out.push('">');
        }
      }

      if (i < end) {
        Html.withinStyle(out, text.text, i, next);
      }

      // ── 闭合标签（反向 j，类型固定序：font → a → strike → u → sub → sup → tt → b → i）──
      for (let j = style.length - 1; j >= 0; j--) {
        const t: SpanType = style[j].type;
        if (t === SpanType.FOREGROUND || t === SpanType.FONT_SIZE) {
          out.push('</font>');
        }
        if (t === SpanType.URL) {
          out.push('</a>');
        }
        if (t === SpanType.STRIKETHROUGH) {
          out.push('</strike>');
        }
        if (t === SpanType.UNDERLINE) {
          out.push('</u>');
        }
        if (t === SpanType.SUBSCRIPT) {
          out.push('</sub>');
        }
        if (t === SpanType.SUPERSCRIPT) {
          out.push('</sup>');
        }
        if (t === SpanType.TT) {
          out.push('</tt>');
        }
        if (t === SpanType.BOLD) {
          out.push('</b>');
        }
        if (t === SpanType.ITALIC) {
          out.push('</i>');
        }
      }
    }

    if (nl === 1) {
      out.push('<br>\n');
      return false;
    } else {
      for (let i = 2; i < nl; i++) {
        out.push('<br>');
      }
      return !last;
    }
  }

  /**
   * 对应上游 withinStyle（L403）：字符级实体转义。
   * 逐条照搬：`<`→`&lt;`、`>`→`&gt;`、`&`→`&amp;`、代理对→`&#codepoint;`、
   * `c > 0x7E || c < ' '`→`&#code;`、连续空格→第一个之后全部 `&nbsp;`。
   */
  private static withinStyle(out: string[], text: string, start: number, end: number): void {
    for (let i = start; i < end; i++) {
      const c: string = text.charAt(i);
      const code: number = text.charCodeAt(i);

      if (c === '<') {
        out.push('&lt;');
      } else if (c === '>') {
        out.push('&gt;');
      } else if (c === '&') {
        out.push('&amp;');
      } else if (code >= 0xD800 && code <= 0xDFFF) {
        if (code < 0xDC00 && i + 1 < end) {
          const d: number = text.charCodeAt(i + 1);
          if (d >= 0xDC00 && d <= 0xDFFF) {
            i++;
            const codepoint: number = 0x010000 | ((code - 0xD800) << 10) | (d - 0xDC00);
            out.push(`&#${codepoint};`);
          }
        }
      } else if (code > 0x7E || code < 0x20) {
        out.push(`&#${code};`);
      } else if (c === ' ') {
        while (i + 1 < end && text.charAt(i + 1) === ' ') {
          out.push('&nbsp;');
          i++;
        }
        out.push(' ');
      } else {
        out.push(c);
      }
    }
  }

  /** 上游 `Integer.toHexString(color + 0x01000000)` 再左侧补 0 到 6 位 */
  private static colorToHex6(color: number): string {
    // 上游是 Java int32 运算：`color + 0x01000000` 会溢出回绕（丢掉 alpha 字节）。
    // JS number 不截断，必须显式 >>> 0 复刻 int32 语义：
    //   ARGB 0xFFFF0000 + 0x01000000 = 0x100FF0000 → >>>0 = 0x00FF0000 → "ff0000"
    const v: number = (color + 0x01000000) >>> 0;
    let colorStr: string = v.toString(16);
    while (colorStr.length < 6) {
      colorStr = '0' + colorStr;
    }
    return colorStr;
  }
}
