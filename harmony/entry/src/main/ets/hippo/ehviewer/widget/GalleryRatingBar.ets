/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/GalleryRatingBar.java（inventory S0298，上游 60 行）
 *
 * 上游三个行为，逐条搬：
 *   1) 构造 init()：给自身注册 OnRatingBarChangeListener（本类实现该接口）
 *   2) onRatingChanged(ratingBar, rating, fromUser)：rating <= 0.0f 时强制 setRating(0.5f)
 *      —— 保证"一颗星都没有"的状态不可达（上游画廊评分最少半星）
 *   3) onDraw()：每帧把当前 getRating() 回吐给 OnUserRateListener.onUserRate(rating)
 *      —— 上游用 onDraw 做回调（不是 setter），意味着**排版/重绘会触发回调**，调用方据此刷新文字
 *
 * ArkUI 对位：
 *   AppCompatRatingBar → `Rating`（stepSize 0.5 表达"半星"，与上游 RatingBar 的 numStars/stepSize 等价）
 *   onRatingChanged 的 0 → 0.5 夹紧 → `.onChange` 里判断并回写 `@State rating`
 *   onDraw 每帧回调 → ArkUI 无"每帧绘制回调"，改为**值变化时回调**（onChange + aboutToAppear 首帧），
 *     即"评级变化就通知"，比"每帧通知"少回调但状态最终一致（已登记 MR；若调用方依赖每帧刷新需另议）
 *   fromUser 语义：`Rating.onChange` 只由用户交互触发，等价于上游 fromUser=true 的情形；
 *     程序化 setRating 需要走本组件的 `setRatingProgrammatic()`
 */
export interface OnUserRateListener {
  onUserRate(rating: number): void;
}

/** 具名实现类：ArkTS 禁止无类型对象字面量 */
export class OnUserRateListenerImpl implements OnUserRateListener {
  private fn: (rating: number) => void;

  constructor(fn: (rating: number) => void) {
    this.fn = fn;
  }

  onUserRate(rating: number): void {
    this.fn(rating);
  }
}

@Component
export struct GalleryRatingBar {
  /** 上游 getRating()/setRating()，步长 0.5，范围 0.5–5（0 被夹到 0.5） */
  @Link rating: number;
  /** 上游 mListener */
  listener: OnUserRateListener | null = null;
  @Prop starCount: number = 5;

  /** 上游 onRatingChanged 的夹紧规则：rating <= 0 → 0.5 */
  private clampRating(v: number): number {
    return v <= 0.0 ? 0.5 : v;
  }

  /** 程序化设置（对位上游 setRating，不触发 fromUser=true 的语义） */
  setRatingProgrammatic(v: number): void {
    this.rating = this.clampRating(v);
    if (this.listener !== null) {
      this.listener.onUserRate(this.rating);
    }
  }

  aboutToAppear(): void {
    // 对位上游 onDraw 首次回调：进入时先通知一次当前值
    if (this.listener !== null) {
      this.listener.onUserRate(this.clampRating(this.rating));
    }
  }

  build() {
    Rating({ rating: this.clampRating(this.rating), indicator: false })
      .stars(this.starCount)
      .stepSize(0.5)
      .width(160)
      .onChange((value: number) => {
        const clamped: number = this.clampRating(value);
        this.rating = clamped;
        if (this.listener !== null) {
          this.listener.onUserRate(clamped);
        }
      })
  }
}
