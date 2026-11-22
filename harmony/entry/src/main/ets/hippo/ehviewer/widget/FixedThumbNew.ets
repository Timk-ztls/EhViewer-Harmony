/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/FixedThumbNew.java（inventory S0294，上游 68 行）
 *
 * 与 FixedThumb 同构（上游父类是 LoadImageViewNew）。判定逻辑逐行照搬：
 *   minAspect < w/h < maxAspect → CENTER_CROP；否则（含 setImageResource 路径）→ FIT_CENTER。
 *
 * 差异：与 TileThumbNew 相同——鸿蒙侧只有一套加载器实现，两者行为等价，保留双组件只为调用点对位。
 */
import { LoadImageView, LoadImageController } from '../../widget/LoadImageView';

@Component
export struct FixedThumbNew {
  controller: LoadImageController = new LoadImageController();
  @Prop minAspect: number = 0.0;
  @Prop maxAspect: number = 0.0;
  @State fit: ImageFit = ImageFit.Contain;

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
