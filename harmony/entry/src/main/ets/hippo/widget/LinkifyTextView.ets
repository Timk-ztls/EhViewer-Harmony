/**
 * 迁移自 app/src/main/java/com/hippo/widget/LinkifyTextView.java（inventory S0526，上游 72 行）
 *
 * ============================ 一手语义 ============================
 * 上游 `extends ObservedTextView`，只做一件事：**在 ACTION_DOWN 时判断触点落在哪个 ClickableSpan 上**，
 * 存到 `mCurrentSpan`；每次 DOWN 先置 null 再重算。目的（源码注释）：
 *   "Let the parent or grandparent of TextView to handles click action. Otherwise click effect like ripple
 *    will not work, and if touch area do not contain a url, the TextView will still get MotionEvent."
 * ⇒ 即：**自己不吃点击事件**（让父容器处理 ripple/点击），但要知道"用户按在哪个链接上"。
 * 算法抄自 `LinkMovementMethod`：
 *   x -= totalPaddingLeft; y -= totalPaddingTop; x += scrollX; y += scrollY;
 *   line = layout.getLineForVertical(y); off = layout.getOffsetForHorizontal(line, x);
 *   spans = spanned.getSpans(off, off, ClickableSpan.class); mCurrentSpan = spans.length > 0 ? spans[0] : null
 *
 * ============================ 判据：**分叉 → 平台已提供命中判定，只保留对外的 span 契约** ============================
 * ArkUI 的 `Text` 支持 `Span(...).onClick(...)` —— **"哪个 span 被点了"由框架解析**，
 * 不需要 `getLineForVertical` / `getOffsetForHorizontal` / `getSpans` 三段手工命中测试。
 * 但上游对外的契约（`getCurrentSpan()` / `clearCurrentSpan()`）仍被调用方使用，且"每次按下先清空"的
 * 时序语义真实存在（防"上次点的链接残留"），故保留 `currentSpan` 状态机 + 点击回填。
 *
 * 不移植的部分（已登记）：`getLineForVertical`/`getOffsetForHorizontal`/`getSpans` 手工命中测试
 *   —— 平台已提供同等能力；若将来需要"按下即高亮某片段"（而非点击后才回调），再用 `Text.onTouch`
 *   + 自绘实现，届时另开一条 D 记录。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeTokens } from '../../common/theme/ThemeTokens';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.LinkifyTextView';

/** 对位 ClickableSpan：一段可点击区域（起止偏移 + 携带的标识） */
/** 渲染段：普通文本段或链接段（修 P1：此前只生成链接段，正文全丢） */
export class RenderSegment {
  text: string = '';
  span: LinkSpan | null = null;

  constructor(text: string, span: LinkSpan | null) {
    this.text = text;
    this.span = span;
  }
}


/** 段切分（纯类，可单测）：把整段文本切成 [普通) [span] (普通) … [普通]，
 *  上游由 TextView 渲染整段 Spanned，本函数复现它的渲染区间划分。 */
export class LinkifySegments {
  static build(text: string, spans: LinkSpan[]): RenderSegment[] {
    const len: number = text.length;
    const raw: LinkSpan[] = [];
    for (let i = 0; i < spans.length; i++) {
      const sp: LinkSpan = spans[i];
      const s: number = Math.max(0, Math.min(len, sp.start));
      const e: number = Math.max(0, Math.min(len, sp.end));
      if (e > s) {
        raw.push(new LinkSpan(s, e, sp.token));
      }
    }
    raw.sort((a: LinkSpan, b: LinkSpan) => a.start - b.start);
    const out: RenderSegment[] = [];
    let cursor: number = 0;
    for (let i = 0; i < raw.length; i++) {
      const sp: LinkSpan = raw[i];
      const start: number = Math.max(cursor, sp.start);
      if (start >= sp.end) {
        continue; // 完全被前一个 span 覆盖
      }
      if (start > cursor) {
        out.push(new RenderSegment(text.substring(cursor, start), null));
      }
      out.push(new RenderSegment(text.substring(start, sp.end), new LinkSpan(start, sp.end, sp.token)));
      cursor = sp.end;
    }
    if (cursor < len) {
      out.push(new RenderSegment(text.substring(cursor, len), null));
    }
    return out;
  }
}

export class LinkSpan {
  start: number = 0;
  end: number = 0;
  /** 业务标识（上游 ClickableSpan 里携带的 URL/标签名等） */
  token: string = '';

  constructor(start: number, end: number, token: string) {
    this.start = start;
    this.end = end;
    this.token = token;
  }
}

/**
 * 上游 mCurrentSpan 的状态机。
 * 关键时序（上游 `onTouchEvent` 开头）：**每次 ACTION_DOWN 先把 mCurrentSpan 置 null，再重新判定**。
 * 漏掉"先清空"会让上一次的 span 残留 —— 表现为"这次按在空白处，却触发了上次的链接动作"。
 */
export class LinkifyState {
  private currentSpan: LinkSpan | null = null;

  /** 上游 ACTION_DOWN 的第一句：mCurrentSpan = null */
  onTouchDown(): void {
    this.currentSpan = null;
  }

  /** 点击某个 span（ArkUI 由 Span.onClick 直接给出，无需命中测试） */
  onSpanClicked(span: LinkSpan): void {
    this.currentSpan = span;
  }

  /** 上游 getCurrentSpan() */
  getCurrentSpan(): LinkSpan | null {
    return this.currentSpan;
  }

  /** 上游 clearCurrentSpan() */
  clearCurrentSpan(): void {
    this.currentSpan = null;
  }
}

@Component
export struct LinkifyTextView {
  @Prop text: string = '';
  @Prop spans: LinkSpan[] = [];
  @Prop fontSize: number = 14;
  @Prop textColor: ResourceColor = '';
  @Prop linkColor: ResourceColor = '';
  state: LinkifyState = new LinkifyState();
  /** span 被点击（对位消费方拿 getCurrentSpan() 后自己处理） */
  onSpanClick: (span: LinkSpan) => void = (span: LinkSpan) => {
  };
  onBlankClick: () => void = () => {
  };
  @State rev: number = 0;

  private effectiveTextColor(): ResourceColor {
    return this.textColor !== '' ? this.textColor : ThemeTokens.current().textPrimary;
  }

  private effectiveLinkColor(): ResourceColor {
    return this.linkColor !== '' ? this.linkColor : ThemeTokens.current().textThemePrimary;
  }

  aboutToAppear(): void {
    if (this.onSpanClick === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'onSpanClick not injected — span taps will do nothing');
    }
  }

  /**
   * 把整段文本切成 `[普通) [span] (普通) [span] … [普通]`。
   * **修 P1**：此前只遍历 span 列表、span 之间的普通文本从未生成 ⇒ 评论只显示链接那几十个字符，
   * 纯文本评论整条空白。上游由 TextView 自己渲染整段 Spanned，链接只是其中被标记的区段。
   *
   * 边界处理（不猜，逐条定）：
   *   · span 越界 → 裁到 [0, text.length]（防 substring 抛错）
   *   · span 区间非法（end <= start）→ 丢弃该 span（不渲染空链接）
   *   · span 互相重叠 → 按 start 升序，重叠部分归属**先出现**的 span（后者起点前移）
   */
  private buildRenderSegments(): RenderSegment[] {
    return LinkifySegments.build(this.text, this.spans);
  }

  build() {
    Text() {
      ForEach(this.buildRenderSegments(), (seg: RenderSegment, index: number) => {
        if (seg.span === null) {
          // 普通文本段：与正文同色，无点击
          Span(seg.text)
            .fontColor(this.effectiveTextColor())
        } else {
          Span(seg.text)
            .fontColor(this.effectiveLinkColor())
            .onClick(() => {
              const sp: LinkSpan | null = seg.span;
              if (sp !== null) {
                this.state.onSpanClicked(sp);
                this.onSpanClick(sp);
                this.rev = this.rev + 1;
              }
            })
        }
      }, (seg: RenderSegment, index: number) => `${index}:${seg.text.length}:${seg.span === null ? 'plain' : 'link'}`)
    }
    .fontSize(this.fontSize)
    .fontColor(this.effectiveTextColor())
    .onClick(() => {
      // 空白处点击：对位上游"不命中 span 时 mCurrentSpan 为 null"
      this.state.onTouchDown();
      this.onBlankClick();
      this.rev = this.rev + 1;
    })
  }
}
