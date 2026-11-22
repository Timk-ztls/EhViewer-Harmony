/*
 * 上游：app/src/main/java/com/hippo/widget/ShadowLinearLayout.java（48 行上游 Java，无 XML）
 * 目标：hippo/ui/layout/support/SwipeHandlerShadow.ets（**新增等价层**，登记在 inventory/ui-scene.extra.txt）
 *
 * 用途：item_blacklist / item_download_label / item_download 等布局的根都是
 *   <com.hippo.widget.ShadowLinearLayout android:id="@+id/swipe_handler"
 *       orientation="vertical" background="?attr/contentColorPrimary">
 * 上游这个控件的职责只有两件：
 *   1. 竖直线性容器（等价 Column）
 *   2. 内容在结构上有上下 1dp 分隔线 + 可选的上下阴影（`shadow_top`/`shadow_bottom` drawable，
 *      由 SwipeHelper 在滑动时按位移设置透明度；布局静态态下阴影 alpha=0）
 * 因此这里落一个**共用**容器，避免 item_blacklist / item_download_label / item_download
 * 各自复制一份（Lead 已确认"同构就该复用，不产两份会漂移的代码"）。
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/contentColorPrimary` 无 ArkUI attr → @Prop containerColor 注入，默认 '#FFFFFFFF'。
 * 2. 阴影的**动态透明度**由上游 SwipeHelper（触摸滑动时 setShadowAlpha）驱动；
 *    本容器只提供 `shadowAlpha` 属性把 ShadowTop/ShadowBottom 叠在内容上下，
 *    动画驱动留给使用方（ArkUI 侧用 .opacity 动画即可），静态态默认 0 与上游一致。
 * 3. 上游该控件 `clipChildren=false`（滑动时内容要能越界显示），
 *    ArkUI 默认不裁剪子组件，语义一致，无需额外设置。
 */

import { ShadowTop } from '../../drawable/shadow_top';
import { ShadowBottom } from '../../drawable/shadow_bottom';

@Component
export struct SwipeHandlerShadow {
  @Prop containerColor: ResourceColor = '#FFFFFFFF';
  /** 上下阴影透明度（上游 SwipeHelper 滑动时驱动；静态态为 0） */
  @Prop shadowAlpha: number = 0;

  /** 内容区（各布局的 Row/Column 子结构） */
  @BuilderParam content: () => void;

  build() {
    Column() {
      // 顶部阴影（上游 shadow_top，绘制在内容之上/之上层，静态 alpha=0）
      Stack() {
        ShadowTop()
      }
      .width('100%')
      .height(1)
      .opacity(this.shadowAlpha)

      this.content();

      Stack() {
        ShadowBottom()
      }
      .width('100%')
      .height(1)
      .opacity(this.shadowAlpha)
    }
    .width('100%')
    .backgroundColor(this.containerColor)
    .alignItems(HorizontalAlign.Start)
  }
}
