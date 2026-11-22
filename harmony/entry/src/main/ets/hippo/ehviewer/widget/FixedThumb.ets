/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/FixedThumb.java（inventory S0293，上游 68 行）
 *
 * 上游：
 *   属性 minAspect / maxAspect（默认 0.0f，来自 R.styleable.FixedThumb）
 *   setFix(minAspect, maxAspect)
 *   onPreSetImageDrawable(drawable, isTarget)：
 *     图片有固有宽高且 minAspect < w/h < maxAspect → setScaleType(CENTER_CROP)
 *     否则（以及 onPreSetImageResource）           → setScaleType(FIT_CENTER)
 *   用途：把"接近目标宽高比"的图裁切填满，比例差太多的图完整显示，避免缩略图被裁得看不出内容。
 *
 * ArkUI 对位：
 *   CENTER_CROP → ImageFit.Cover   （等比放大裁切填满）
 *   FIT_CENTER  → ImageFit.Contain （等比完整显示，留边）
 *   intrinsicWidth/Height 的读取时机（onPreSetImageDrawable）→ LoadImageView 的 onImageLoaded 回调
 *   （Image.onComplete 给出解码后的宽高，等价于 drawable 的固有尺寸）
 */
import { LoadImageView, LoadImageController } from '../../widget/LoadImageView';

@Component
export struct FixedThumb {
  controller: LoadImageController = new LoadImageController();
  /** 上游 R.styleable.FixedThumb_minAspect / maxAspect（默认 0.0f） */
  @Prop minAspect: number = 0.0;
  @Prop maxAspect: number = 0.0;
  @State fit: ImageFit = ImageFit.Contain;

  /** 上游 onPreSetImageDrawable 的判定 */
  private applyFix(width: number, height: number): void {
    if (width > 0 && height > 0) {
      const aspect: number = width / height;
      if (aspect < this.maxAspect && aspect > this.minAspect) {
        this.fit = ImageFit.Cover;
        return;
      }
    }
    this.fit = ImageFit.Contain;
  }

  build() {
    LoadImageView({
      controller: this.controller,
      imageFit: this.fit,
      onImageLoaded: (w: number, h: number) => {
        this.applyFix(w, h);
      }
    })
  }
}
