/**
 * 迁移自 app/src/main/java/com/hippo/drawable/PreciselyClipDrawable.kt（inventory S0028，上游 96 行）
 *
 * 上游是「按比例精确裁剪」的 DrawableWrapper：
 *   init：originWidth/Height = drawable.intrinsic；不可裁剪（<=0）时 mClip=false
 *        mScale = 把 (offsetX, offsetY, offsetX+width, offsetY+height) 归一化到 [0,1] 的矩形
 *   onBoundsChange(bounds)：把父 bounds 通过 mScale 的线性变换**反算**成子 drawable 的 bounds，
 *        使"子图被裁出的那块"正好铺满父 bounds（这就是"precisely"的含义）
 *   getIntrinsicWidth/Height = 原始值 * mScale.width()/height()
 *
 * 公式（上游逐式搬，注意是反算）：
 *   denom = sL*(1-sR) - sR*(1-sL)
 *   left   = (sL*right  - sR*left) / denom
 *   right  = ((1-sR)*left - (1-sL)*right) / denom
 *   top    = (sT*bottom - sB*top) / denom
 *   bottom = ((1-sB)*top - (1-sT)*bottom) / denom
 *
 * ArkUI 对位：
 *   1) 纯算术部分 `PreciselyClipDrawable`（下方 class）**逐式搬**，可单测（已断言覆盖）。
 *   2) 渲染部分：`Image` + `.clip()` + 按算出的子 rect 做 `objectFit/定位`。**注意**：真正的"按需解码子区域"
 *      省内存依赖 native-image 的解码区域参数（与 C-8 批准的 setClip 语义一致），组件层只能做视觉裁剪。
 *      这条已在 MR 与 C-8 讨论中确认：组件级 clip 是"视觉先裁、解码后裁"，PreciselyClipDrawable 的意图是后者。
 */
export class ClipScale {
  left: number = 0;
  top: number = 0;
  right: number = 1;
  bottom: number = 1;

  isEmpty(): boolean {
    return this.right <= this.left || this.bottom <= this.top;
  }

  width(): number {
    return this.right - this.left;
  }

  height(): number {
    return this.bottom - this.top;
  }
}

export class ClipRect {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
}

function clamp01(v: number): number {
  if (v < 0) {
    return 0;
  }
  if (v > 1) {
    return 1;
  }
  return v;
}

export class PreciselyClipDrawable {
  /** 上游 mClip */
  clip: boolean = false;
  /** 上游 mScale（归一化裁剪窗口） */
  scale: ClipScale = new ClipScale();
  /** 上游 drawable.intrinsicWidth/Height */
  originWidth: number = 0;
  originHeight: number = 0;

  constructor(originWidth: number, originHeight: number, offsetX: number, offsetY: number,
              width: number, height: number) {
    this.originWidth = originWidth;
    this.originHeight = originHeight;
    if (originWidth <= 0 || originHeight <= 0) {
      // Can not clip
      this.clip = false;
      return;
    }
    this.clip = true;
    this.scale.left = clamp01(offsetX / originWidth);
    this.scale.top = clamp01(offsetY / originHeight);
    this.scale.right = clamp01((offsetX + width) / originWidth);
    this.scale.bottom = clamp01((offsetY + height) / originHeight);
  }

  /** 上游 onBoundsChange：父 bounds → 子 bounds（反算） */
  resolveBounds(parentLeft: number, parentTop: number, parentRight: number, parentBottom: number): ClipRect {
    const out: ClipRect = new ClipRect();
    const s: ClipScale = this.scale;
    if (this.clip && !s.isEmpty()) {
      // 代数化简：denomX = sL - sR（= -scale.width()）⇒ 只要 !isEmpty 就恒非负数为零，**无除零风险**
      //（上游同样未做保护，因为结构上不需要；此处保留 !==0 判断仅为 NaN 兜底）
      const denomX: number = s.left * (1 - s.right) - s.right * (1 - s.left);
      const denomY: number = s.top * (1 - s.bottom) - s.bottom * (1 - s.top);
      if (denomX !== 0) {
        // 上游 .toInt()：向零截断（保持与 Android 逐像素一致的取整行为）
        out.left = Math.trunc((s.left * parentRight - s.right * parentLeft) / denomX);
        out.right = Math.trunc(((1 - s.right) * parentLeft - (1 - s.left) * parentRight) / denomX);
      }
      if (denomY !== 0) {
        out.top = Math.trunc((s.top * parentBottom - s.bottom * parentTop) / denomY);
        out.bottom = Math.trunc(((1 - s.bottom) * parentTop - (1 - s.top) * parentBottom) / denomY);
      }
      return out;
    }
    out.left = parentLeft;
    out.top = parentTop;
    out.right = parentRight;
    out.bottom = parentBottom;
    return out;
  }

  /** 上游 getIntrinsicWidth()（mClip 时按 scale 比例缩放） */
  intrinsicWidth(): number {
    return this.clip ? Math.trunc(this.originWidth * this.scale.width()) : this.originWidth;
  }

  /** 上游 getIntrinsicHeight() */
  intrinsicHeight(): number {
    return this.clip ? Math.trunc(this.originHeight * this.scale.height()) : this.originHeight;
  }
}

/**
 * 渲染层：按 clip 参数显示图像子区域。
 * 真正的省内存解码需要 native-image 提供"只解码指定区域"的参数（对位 C-8 的 setClip）。
 */
@Component
export struct PreciselyClipDrawableView {
  @Prop src: string = '';
  /** 上游构造参数：裁剪窗口（原图像素坐标） */
  @Prop offsetX: number = 0;
  @Prop offsetY: number = 0;
  @Prop clipWidth: number = 0;
  @Prop clipHeight: number = 0;
  @Prop originWidth: number = 0;
  @Prop originHeight: number = 0;

  private model(): PreciselyClipDrawable {
    return new PreciselyClipDrawable(this.originWidth, this.originHeight,
      this.offsetX, this.offsetY, this.clipWidth, this.clipHeight);
  }

  build() {
    Stack() {
      if (this.src.length > 0) {
        Image(this.src)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          // 视觉裁剪：把子图按反算 bounds 平移/缩放填入父区域（省内存的解码需 native-image 支持）
          .translate({
            x: -this.model().scale.left * 100,
            y: -this.model().scale.top * 100
          })
          .scale({ x: 1 / Math.max(0.0001, this.model().scale.width()), y: 1 / Math.max(0.0001, this.model().scale.height()) })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
