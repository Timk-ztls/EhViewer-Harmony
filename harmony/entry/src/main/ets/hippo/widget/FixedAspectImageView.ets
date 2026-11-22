/**
 * 迁移自 app/src/main/java/com/hippo/widget/FixedAspectImageView.java（S0521，上游 262 行）
 *
 * 上游：`ShapeableImageView` 的固定宽高比版本
 *   · setMinimumWidth/Height、setMaxWidth/Height、setAdjustViewBounds 各自记录一份字段（要参与测量）
 *   · **setAspect(ratio)**：ratio > 0 才生效，**任何 <= 0 都关闭**（置 -1），然后 requestLayout()
 *     注释明确："Enable aspect will set AdjustViewBounds true"（aspect 开启等价 adjustViewBounds）
 *   · resolveAdjustedSize(desired, min, max, spec)：三分支
 *       UNSPECIFIED → clamp(desired, min, max)
 *       AT_MOST     → clamp(min(desired, specSize), min, max)
 *       EXACTLY     → specSize
 *   · onMeasure：drawable 为空 → w=h=0；aspect>0 时按 spec 模式决定 resizeWidth/Height 并令
 *       desiredAspect = mAspect；否则用 drawable intrinsic 比例（adjustViewBounds 才允许改尺寸）
 *
 * ArkUI 对位：`Image` + `.aspectRatio(ratio)` + `.constraintSize({min/max})` —— 测量由框架承担，
 *   **不手写 onMeasure**（判据：完全重复）。本文件保留可测的 `resolveAdjustedSize` 与
 *   "负值即关闭"的语义，供调用方与断言使用。
 *
 * 差异（已登记 MR）：
 *   1) 上游 onMeasure 的完整分支表 → aspectRatio + constraintSize（宽度/高度解析需 P5 截图比对）
 *   2) `ShapeableImageView` 的形状/圆角 → ArkUI `.borderRadius()` / `.clipShape()`
 */
export class FixedAspectMath {
  static readonly MODE_UNSPECIFIED: number = 0;
  static readonly MODE_EXACTLY: number = 1;
  static readonly MODE_AT_MOST: number = 2;

  /** 上游 MathUtils.clamp */
  static clamp(v: number, lo: number, hi: number): number {
    if (v < lo) {
      return lo;
    }
    if (v > hi) {
      return hi;
    }
    return v;
  }

  /** 上游 resolveAdjustedSize（三分支逐式搬） */
  static resolveAdjustedSize(desired: number, min: number, max: number, specMode: number, specSize: number): number {
    if (specMode === FixedAspectMath.MODE_UNSPECIFIED) {
      return FixedAspectMath.clamp(desired, min, max);
    }
    if (specMode === FixedAspectMath.MODE_AT_MOST) {
      return FixedAspectMath.clamp(Math.min(desired, specSize), min, max);
    }
    return specSize;
  }

  /** 上游 setAspect：ratio > 0 才生效，**任何 <= 0 都关闭**（返回 -1） */
  static normalizeAspect(ratio: number): number {
    return ratio > 0 ? ratio : -1;
  }

  static isAspectEnabled(ratio: number): boolean {
    return FixedAspectMath.normalizeAspect(ratio) > 0;
  }

  /** ratio = width / height（上游注释明确） */
  static heightForWidth(width: number, ratio: number): number {
    const r: number = FixedAspectMath.normalizeAspect(ratio);
    return r > 0 ? width / r : width;
  }

  static widthForHeight(height: number, ratio: number): number {
    const r: number = FixedAspectMath.normalizeAspect(ratio);
    return r > 0 ? height * r : height;
  }
}

@Component
export struct FixedAspectImageView {
  @Prop src: string = '';
  /** 上游 setAspect：width/height；<= 0 表示不固定比例 */
  @Prop aspect: number = -1;
  @Prop minWidthValue: number = 0;
  @Prop minHeightValue: number = 0;
  @Prop maxWidthValue: number = Number.MAX_SAFE_INTEGER;
  @Prop maxHeightValue: number = Number.MAX_SAFE_INTEGER;
  @Prop imageFit: ImageFit = ImageFit.Cover;

  build() {
    Image(this.src)
      .width('100%')
      .height('100%')
      .objectFit(this.imageFit)
      .aspectRatio(FixedAspectMath.isAspectEnabled(this.aspect) ? this.aspect : undefined)
      .constraintSize({
        minWidth: this.minWidthValue,
        minHeight: this.minHeightValue,
        maxWidth: this.maxWidthValue,
        maxHeight: this.maxHeightValue
      })
  }
}