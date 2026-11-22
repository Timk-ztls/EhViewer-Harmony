/**
 * 迁移自 app/src/main/java/com/hippo/widget/ObservedTextView.java（inventory S0533，上游 52 行）
 *
 * 上游：
 *   onAttachedToWindow()   → mOnWindowAttachListener.onAttachedToWindow()
 *   onDetachedFromWindow() → mOnWindowAttachListener.onDetachedFromWindow()
 *   setOnWindowAttachListener(...)
 *   interface OnWindowAttachListener { onAttachedToWindow(); onDetachedFromWindow(); }
 * 用途：把"文字被挂到窗口 / 从窗口摘除"当作生命周期信号（常用于延迟测量、动画起停）。
 *
 * ArkUI 对位：
 *   onAttachedToWindow  ≡ 组件 aboutToAppear（组件进入组件树）
 *   onDetachedFromWindow ≡ 组件 aboutToDisappear（组件移出组件树）
 *   顺序差异：Android 是先挂窗口再布局；ArkUI aboutToAppear 在首次 build 前触发，
 *            若监听方依赖"已有父节点尺寸"，应改用 onAreaChange 首帧回调（已在 MR 登记）。
 */
export interface OnWindowAttachListener {
  onAttachedToWindow(): void;

  onDetachedFromWindow(): void;
}

/** 具名实现类：ArkTS 禁止无类型对象字面量，故监听器必须显式实现接口 */
export class WindowAttachListenerImpl implements OnWindowAttachListener {
  private attachFn: () => void;
  private detachFn: () => void;

  constructor(attachFn: () => void, detachFn: () => void) {
    this.attachFn = attachFn;
    this.detachFn = detachFn;
  }

  onAttachedToWindow(): void {
    this.attachFn();
  }

  onDetachedFromWindow(): void {
    this.detachFn();
  }
}

@Component
export struct ObservedTextView {
  @Prop text: string = '';
  @Prop textSize: number = 14;
  @Prop textColor: ResourceColor = '#FF000000';
  /** 上游 mOnWindowAttachListener */
  attachListener: OnWindowAttachListener | null = null;
  /** 便捷入口：不想建类时直接给两个回调（与 attachListener 二选一，attachListener 优先）。
   *  注意命名：onAttach/onDetach 与 ArkUI CustomComponent 基类属性冲突（编译器报 not assignable），故加 Window 前缀。 */
  onWindowAttached: () => void = () => {
  };
  onWindowDetached: () => void = () => {
  };

  aboutToAppear(): void {
    if (this.attachListener !== null) {
      this.attachListener.onAttachedToWindow();
    } else {
      this.onWindowAttached();
    }
  }

  aboutToDisappear(): void {
    if (this.attachListener !== null) {
      this.attachListener.onDetachedFromWindow();
    } else {
      this.onWindowDetached();
    }
  }

  build() {
    Text(this.text)
      .fontSize(this.textSize)
      .fontColor(this.textColor)
  }
}
