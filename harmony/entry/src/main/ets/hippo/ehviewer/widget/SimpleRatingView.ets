/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/SimpleRatingView.java（inventory S0311，上游 99 行）
 *
 * 上游绘制（逐条搬）：
 *   ratingInt = clamp(ceil(rating * 2), 0, 10)（半星 = 1）
 *   numStar = ratingInt / 2（整除）；numStarHalf = ratingInt % 2
 *   step = ratingSize + ratingInterval；依次画 numStar 个实心星、可选的半星、剩下的空心星
 *   onMeasure：宽 = ratingSize*5 + ratingInterval*4，高 = ratingSize
 *
 * **上游的一个既有缺陷（保留，不修）**：`numOutline = 5 - numStar - numStarHalf;` 里的 `numStar` 已被
 * `while (numStar-- > 0)` 递减到 -1，因此实际计算是 `5+1-numStarHalf = 6-numStarHalf`，
 * 即会多画 1 个空心星（画到 bounds 之外、被裁剪，肉眼不可见）。1:1 原则下**照原样保留**，
 * 并在 MR 里标注；若 Lead 要求修，改为"先算 outline 数量再画"即可（1 行）。
 *
 * ArkUI 对位：三个 Drawable（v_star_x16 / v_star_half_x16 / v_star_outline_x16）**直接复用 part-1 的重绘产物**
 *   （VStarX16 / VStarHalfX16 / VStarOutlineX16 组件），Row 里按 `ratingSize` + `ratingInterval` 排布。
 *   onMeasure 的固定尺寸 → `.width/height` 由 ratingSize 计算（5 星 + 4 间隔）。
 */
import { ThemeDimens } from '../../../common/theme/ThemeTokens';
import { DrawablePalette } from '../../drawable/DrawablePalette';
import { VStarX16 } from '../../ui/drawable/v_star_x16';
import { VStarHalfX16 } from '../../ui/drawable/v_star_half_x16';
import { VStarOutlineX16 } from '../../ui/drawable/v_star_outline_x16';

@Component
export struct SimpleRatingView {
  /** 上游 mRating（0..5，半星粒度） */
  @Prop rating: number = 0;
  /** 上游 R.dimen.rating_size（默认 16dp） */
  @Prop ratingSize: number = ThemeDimens.RATING_SIZE;
  /** 上游 R.dimen.rating_interval（默认 1dp） */
  @Prop ratingInterval: number = ThemeDimens.RATING_INTERVAL;
  @Prop starColor: ResourceColor = DrawablePalette.YELLOW_800;

  private ratingInt(): number {
    const v: number = Math.ceil(this.rating * 2);
    if (v < 0) {
      return 0;
    }
    if (v > 10) {
      return 10;
    }
    return v;
  }

  build() {
    Row({ space: this.ratingInterval }) {
      ForEach(this.buildSlots(), (slot: number, index: number) => {
        if (slot === 2) {
          VStarHalfX16({ iconSize: this.ratingSize, fillColor: this.starColor })
        } else if (slot === 1) {
          VStarX16({ iconSize: this.ratingSize, fillColor: this.starColor })
        } else {
          VStarOutlineX16({ iconSize: this.ratingSize, fillColor: this.starColor })
        }
      }, (slot: number, index: number) => `${index}-${slot}`)
    }
    .width(this.ratingSize * 5 + this.ratingInterval * 4)
    .height(this.ratingSize)
    .alignItems(VerticalAlign.Center)
  }

  /** 生成 5 个槽位：1=实心 2=半星 0=空心（与上游绘制顺序一致） */
  private buildSlots(): number[] {
    const slots: number[] = [];
    const ratingInt: number = this.ratingInt();
    const numStar: number = Math.floor(ratingInt / 2);
    const numHalf: number = ratingInt % 2;
    for (let i = 0; i < numStar; i++) {
      slots.push(1);
    }
    if (numHalf === 1) {
      slots.push(2);
    }
    while (slots.length < 5) {
      slots.push(0);
    }
    return slots;
  }
}
