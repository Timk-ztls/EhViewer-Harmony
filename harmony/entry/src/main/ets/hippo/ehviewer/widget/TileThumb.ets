/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/TileThumb.java（inventory S0313，上游 43 行）
 *
 * 上游：extends LoadImageView，唯一方法 setThumbSize(w,h)：
 *   w>0 && h>0 → aspect = clamp(w/h, MIN_ASPECT=0.33f, MAX_ASPECT=1.5f)
 *   否则      → DEFAULT_ASPECT = 0.67f
 *   然后 setAspect(aspect)（FixedAspectImageView 的宽高比）
 *
 * ArkUI 对位：无法继承 struct，改为**包装组件**：把算出的 aspect 传给 LoadImageView 的
 *   `aspectRatioValue`（对位 setAspect），默认 `imageFit = ImageFit.Cover` 对齐 item_gallery_grid.xml 的 centerCrop。
 */
import { LoadImageView, LoadImageController } from '../../widget/LoadImageView';

@Component
export struct TileThumb {
  static readonly MIN_ASPECT: number = 0.33;
  static readonly MAX_ASPECT: number = 1.5;
  static readonly DEFAULT_ASPECT: number = 0.67;

  controller: LoadImageController = new LoadImageController();
  /** 上游 setThumbSize(thumbWidth, thumbHeight) */
  @Prop thumbWidth: number = 0;
  @Prop thumbHeight: number = 0;
  /** 上游 item_gallery_grid.xml android:scaleType="centerCrop" */
  @Prop imageFit: ImageFit = ImageFit.Cover;

  private aspect(): number {
    if (this.thumbWidth > 0 && this.thumbHeight > 0) {
      const raw: number = this.thumbWidth / this.thumbHeight;
      if (raw < TileThumb.MIN_ASPECT) {
        return TileThumb.MIN_ASPECT;
      }
      if (raw > TileThumb.MAX_ASPECT) {
        return TileThumb.MAX_ASPECT;
      }
      return raw;
    }
    return TileThumb.DEFAULT_ASPECT;
  }

  build() {
    LoadImageView({
      controller: this.controller,
      aspectRatioValue: this.aspect(),
      imageFit: this.imageFit
    })
  }
}
