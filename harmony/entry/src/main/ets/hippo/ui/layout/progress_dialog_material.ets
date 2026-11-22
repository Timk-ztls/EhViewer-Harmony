/*
 * 上游：app/src/main/res/layout/progress_dialog_material.xml（inventory S0645，上游 40 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/progress_dialog_material.ets
 *
 * 来源：AOSP appcompat 的 `abc_alert_dialog_material` 变体（Copyright 2014 AOSP，Apache-2.0）。
 * 背景：**不确定进度**对话框：左侧转圈 + 右侧消息（message 可空）。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                  ArkUI
 * FrameLayout(match × wrap)                 Stack（单子元素，见 1）
 * LinearLayout#body(horizontal, match×match) Row
 *   baselineAligned=false                    → ArkUI Row 无 baseline 对齐概念（见 2）
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop/Bottom=@dimen/dialog_padding_top_material(24dp) .padding({top:24,bottom:24})
 * ProgressBar#progress                     LoadingProgress（见 3）
 *   style=?android:attr/progressBarStyle      → 圆形不确定进度（不是 Horizontal！）
 *   layout_marginRight=?attr/dialogPreferredPadding(24dp)  .margin({right:24})
 * TextView#message(match 宽, center_vertical) Text：.layoutWeight(1) + Row 居中
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 上游 FrameLayout 里只有一个 LinearLayout 子元素 → ArkUI 用 Stack 承载（等价）。
 * 2. `baselineAligned="false"` 的作用是**禁用按基线对齐**（让 ProgressBar 与文本按各自高度居中）。
 *    ArkUI 的 Row 默认就没有 baseline 对齐（用 `alignItems(VerticalAlign.Center)`），
 *    所以这个属性**没有对位但也不需要** —— 语义等价，不登记差异。
 * 3. `progressBarStyle`（无 `.Horizontal`）= **圆形不确定进度**：ArkUI `LoadingProgress` 对位。
 *    注意与 `preference_dialog_task` 里的 Horizontal 条区分（那是横条）。
 *    `max=10000` 对不确定进度无意义（不绑定 value）。
 * 4. `?attr/dialogPreferredPadding`(24dp) 与 `@dimen/dialog_padding_top_material`(24dp)
 *    值相同但**来源不同**（主题属性 vs dimens）→ 两个 @Prop，不合并（主题化后会分叉）。
 *    注意本文件用的是 `dialog_padding_top_material`，与其它布局的
 *    `abc_dialog_padding_top_material` **不是同一个 dimens**（前者无 abc_ 前缀）。
 * 5. message 可空（上游不设 text，由代码 setMessage）：本组件 message 为空时不留空 Text 占位。
 */

@Component
export struct ProgressDialogMaterialLayout {
  @Prop message: string = '';
  @Prop textColor: ResourceColor = '#DE000000';
  /** 上游 ?attr/dialogPreferredPadding（Material 24dp） */
  @Prop dialogPreferredPadding: number = 24;
  /** 上游 @dimen/dialog_padding_top_material（24dp，**无 abc_ 前缀**） */
  @Prop dialogPaddingTop: number = 24;

  build() {
    Stack() {
      Row() {
        // 圆形不确定进度（上游 progressBarStyle，非 Horizontal）
        LoadingProgress()
          .width(32)
          .height(32)
          .margin({ right: this.dialogPreferredPadding })

        if (this.message.length > 0) {
          Text(this.message)
            .fontColor(this.textColor)
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.dialogPreferredPadding,
        right: this.dialogPreferredPadding,
        top: this.dialogPaddingTop,
        bottom: this.dialogPaddingTop
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }
}
