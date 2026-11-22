/*
 * 上游：app/src/main/res/layout/splash_layout.xml（inventory S0671，上游 **7 行** —— 最小布局）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/splash_layout.ets
 *
 * 上游全文就是：match×match 的空 LinearLayout(vertical) + background=@color/trans。
 * 用途：启动页的**透明底**（Splash 期间先铺一层透明，避免白闪；内容由 Activity 后续添加）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                          ArkUI
 * LinearLayout(vertical)            Stack（见 1）
 *   match × match                    .width('100%').height('100%')
 *   background=@color/trans          .backgroundColor($r('app.color.trans'))
 *   （无子元素）                      （无子元素，槽位留给使用方）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游是空 `LinearLayout(vertical)`：ArkUI 的等价物是 `Column`，但**这里用 `Stack` 更准确** ——
 *    上游这个容器的唯一职责是"铺满 + 透明底 + 后续往里加内容"，`Stack` 对后续叠加内容
 *    （启动图/loading）更宽容；且空 Column 与空 Stack 的渲染结果完全一致。
 *    若使用方确定只竖排追加，改成 Column 也不影响（无子元素，无 orientation 语义可丢）。
 * 2. `@color/trans` 已迁 `app.color.trans`（colors.json 有）。
 * 3. 上游没有 padding/margin/gravity —— **不要**顺手加（这是启动页，任何内边距都会影响
 *    首帧与内容的对齐）。
 * 4. 本文件是 68 个布局里唯一"零子元素"的：1:1 就是 1:1，不做任何"看起来该有"的补充。
 */

@Component
export struct SplashLayout {
  /** 透明底（上游 @color/trans；可被主题覆盖） */
  /** 注意：成员名**不能**叫 backgroundColor（与通用属性同名，编译报 not assignable） */
  @Prop bgColor: ResourceColor = $r('app.color.trans');

  /** 启动页内容（上游由 Activity 后续 addView） */
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
    Row().width(0).height(0)
  }

  build() {
    Stack() {
      this.content();
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.bgColor)
  }
}


