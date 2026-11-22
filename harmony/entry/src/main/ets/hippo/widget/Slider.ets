/**
 * 迁移自 app/src/main/java/com/hippo/widget/Slider.java（inventory S0546，上游 440 行）
 *
 * ============================ 裁决结论（Lead：平台优先，用原生 Slider） ============================
 * 上游是全自绘（两个 RectF + 圆 thumb + 独立 BubbleView：Paint.getTextWidths 逐字算宽 + FontMetrics 基线 +
 * ValueAnimator 弹出）。ArkUI 用原生 `Slider` 承载，视觉差异（气泡位置/字体/矩形 vs 圆角轨道/thumb 半径）
 * 归入 DEVIATIONS D-007「不承诺像素级」。
 *
 * ============================ 关键：OnSetProgressListener 的 5 参语义映射（Lead 的硬要求） ============================
 * 上游接口：
 *   onSetProgress(slider, newProgress, oldProgress, byUser, confirm)
 *   onFingerDown() / onFingerUp()
 *   触发点：ACTION_DOWN → onFingerDown；ACTION_MOVE → onSetProgress(..., byUser=true, confirm=false)；
 *           ACTION_UP → onFingerUp() + onSetProgress(..., byUser=true, confirm=true)；
 *           ACTION_CANCEL → onSetProgress(..., byUser=true, confirm=false)；
 *           setProgress(p)（程序化） → onSetProgress(p, old, byUser=false, confirm=true)
 *
 * ArkUI `Slider.onChange(value, mode: SliderChangeMode)`：Begin=0 / Moving=1 / End=2 / Click=3
 *
 * | ArkUI mode | 上游等价 | 本实现动作 |
 * |---|---|---|
 * | Begin(0)  | ACTION_DOWN | `onFingerDown()` |
 * | Moving(1) | ACTION_MOVE | `onSetProgress(new, old, byUser=true, confirm=false)` |
 * | End(2)    | ACTION_UP   | `onFingerUp()` + `onSetProgress(new, old, true, true)` |
 * | Click(3)  | 轨道单击（上游 DOWN→UP 同帧） | `onSetProgress(new, old, true, true)`（一次提交） |
 * | `setProgress()`（程序化） | 上游 setProgress | `onSetProgress(new, old, byUser=false, confirm=true)` |
 *
 * **唯一对不上的点（必须登记）**：ACTION_CANCEL（手指被系统手势打断）上游发 `confirm=false`（不提交），
 * ArkUI 没有 cancel 信号，会以 End(2) 收尾 → 本实现只能**按提交处理**。对阅读器进度条的后果：
 * 被打断时保留当前视觉值并提交，而不是回退。已登记 MR「平台差异」。
 *
 * 其余等价：setRange→min/max、setProgress/getProgress→value、setReverse→.reverse(true)、
 *          setColor→selectedColor/trackColor/blockColor、拖动气泡→.showTips(true)
 */
export interface OnSetProgressListener {
  /** 上游签名逐字保留（slider 用 this 表达，ArkTS 里传控制器自身） */
  onSetProgress(controller: SliderController, newProgress: number, oldProgress: number, byUser: boolean, confirm: boolean): void;

  onFingerDown(): void;

  onFingerUp(): void;
}

/** 具名实现类：ArkTS 禁止无类型对象字面量 */
export class OnSetProgressListenerImpl implements OnSetProgressListener {
  private setFn: (c: SliderController, n: number, o: number, byUser: boolean, confirm: boolean) => void;
  private downFn: () => void;
  private upFn: () => void;

  constructor(setFn: (c: SliderController, n: number, o: number, byUser: boolean, confirm: boolean) => void,
              downFn: () => void, upFn: () => void) {
    this.setFn = setFn;
    this.downFn = downFn;
    this.upFn = upFn;
  }

  onSetProgress(controller: SliderController, newProgress: number, oldProgress: number,
                byUser: boolean, confirm: boolean): void {
    this.setFn(controller, newProgress, oldProgress, byUser, confirm);
  }

  onFingerDown(): void {
    this.downFn();
  }

  onFingerUp(): void {
    this.upFn();
  }
}

export class SliderController {
  start: number = 0;
  end: number = 100;
  progress: number = 0;
  reverse: boolean = false;
  /** 上游 mListener */
  listener: OnSetProgressListener | null = null;

  setRange(start: number, end: number): void {
    this.start = start;
    this.end = end;
    if (this.progress < start) {
      this.setProgressInternal(start, false);
    } else if (this.progress > end) {
      this.setProgressInternal(end, false);
    }
  }

  /** 程序化设置（对位上游 setProgress：byUser=false, confirm=true） */
  setProgress(progress: number): void {
    this.setProgressInternal(progress, true);
  }

  private setProgressInternal(progress: number, notify: boolean): void {
    const clamped: number = progress < this.start ? this.start : (progress > this.end ? this.end : progress);
    const old: number = this.progress;
    this.progress = clamped;
    if (notify && this.listener !== null && old !== clamped) {
      this.listener.onSetProgress(this, clamped, old, false, true);
    }
  }

  getProgress(): number {
    return this.progress;
  }

  setReverse(reverse: boolean): void {
    this.reverse = reverse;
  }

  setOnSetProgressListener(listener: OnSetProgressListener | null): void {
    this.listener = listener;
  }

  /** 供组件在 onChange 里驱动（逐模式映射，见文件头表） */
  handleChange(value: number, mode: SliderChangeMode): void {
    const old: number = this.progress;
    const clamped: number = value < this.start ? this.start : (value > this.end ? this.end : value);
    if (mode === SliderChangeMode.Begin) {
      if (this.listener !== null) {
        this.listener.onFingerDown();
      }
      return;
    }
    if (mode === SliderChangeMode.Moving) {
      this.progress = clamped;
      if (this.listener !== null) {
        this.listener.onSetProgress(this, clamped, old, true, false);
      }
      return;
    }
    if (mode === SliderChangeMode.End) {
      this.progress = clamped;
      if (this.listener !== null) {
        this.listener.onFingerUp();
        this.listener.onSetProgress(this, clamped, old, true, true);
      }
      return;
    }
    // Click(3)：轨道单击，一次提交（上游 DOWN→UP 同帧）
    this.progress = clamped;
    if (this.listener !== null) {
      this.listener.onSetProgress(this, clamped, old, true, true);
    }
  }
}

/**
 * 组件名从上游 `Slider` 改为 `HippoSlider`：**ArkUI 保留标签名 `Slider`**（内置滑块组件），
 * 同名 struct 会报 `The struct name cannot contain reserved tag name: 'Slider'`。
 * 文件路径仍为 inventory 契约的 `hippo/widget/Slider.ets`，调用点改用 `HippoSlider`；状态机在 `SliderController`。
 */
@Component
export struct HippoSlider {
  controller: SliderController = new SliderController();
  @Prop trackThickness: number = 3;
  @Prop blockSize: number = 16;
  @Prop selectedColor: ResourceColor = '#FF009688';
  @Prop trackColor: ResourceColor = '#33000000';
  @Prop blockColor: ResourceColor = '#FF009688';
  @Prop showTips: boolean = true;
  @State value: number = 0;

  aboutToAppear(): void {
    this.value = this.controller.progress;
  }

  build() {
    Slider({
      value: this.value,
      min: this.controller.start,
      max: this.controller.end,
      step: 1,
      style: SliderStyle.OutSet,
      reverse: this.controller.reverse
    })
      .trackThickness(this.trackThickness)
      .blockSize({ width: this.blockSize, height: this.blockSize })
      .selectedColor(this.selectedColor)
      .trackColor(this.trackColor)
      .blockColor(this.blockColor)
      .showTips(this.showTips)
      .width('100%')
      .onChange((value: number, mode: SliderChangeMode) => {
        this.value = value;
        this.controller.handleChange(value, mode);
      })
  }
}
