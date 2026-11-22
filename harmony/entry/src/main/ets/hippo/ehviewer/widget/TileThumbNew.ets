/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/TileThumbNew.java（inventory S0314，上游 43 行）
 *
 * 与 TileThumb **完全同构**，唯一差别是上游父类是 LoadImageViewNew（新版图片加载器实现）。
 * 鸿蒙侧不存在两套加载器（LoadImageViewNew 与 LoadImageView 的差异在解码路径，由 native-image 统一承担），
 * 故本文件复用同一个 LoadImageController，逻辑逐行照搬：clamp(w/h, 0.33, 1.5)，非法尺寸回落 0.67。
 *
 * 差异：上游 TileThumbNew 与 TileThumb 是两个独立类（便于灰度切换加载器）；鸿蒙侧两者行为等价，
 *      保留两个同名组件只为让 ui-scene 的调用点 1:1 对位（已登记 MR）。
 */
import { LoadImageView, LoadImageController } from '../../widget/LoadImageView';

@Component
export struct TileThumbNew {
  static readonly MIN_ASPECT: number = 0.33;
  static readonly MAX_ASPECT: number = 1.5;
  static readonly DEFAULT_ASPECT: number = 0.67;

  controller: LoadImageController = new LoadImageController();
  @Prop thumbWidth: number = 0;
  @Prop thumbHeight: number = 0;

  private aspect(): number {
    if (this.thumbWidth > 0 && this.thumbHeight > 0) {
      const raw: number = this.thumbWidth / this.thumbHeight;
      if (raw < TileThumbNew.MIN_ASPECT) {
        return TileThumbNew.MIN_ASPECT;
      }
      if (raw > TileThumbNew.MAX_ASPECT) {
        return TileThumbNew.MAX_ASPECT;
      }
      return raw;
    }
    return TileThumbNew.DEFAULT_ASPECT;
  }

  build() {
    LoadImageView({ controller: this.controller, aspectRatioValue: this.aspect() })
  }
}
