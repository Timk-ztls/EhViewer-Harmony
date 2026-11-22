/*
 * 上游：app/src/main/res/layout/alert_dialog_progress_material.xml（inventory S0563，上游 39 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/alert_dialog_progress_material.ets
 *
 * 来源：AOSP appcompat（Copyright 2014 AOSP，Apache-2.0）。
 * 背景：**确定进度**对话框：一条水平进度条 + 左下百分比 + 右下数值。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * RelativeLayout(wrap × match)            Stack（见 1）
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop/Bottom=@dimen/dialog_padding_top_material(24dp) .padding({top:24,bottom:24})
 * ProgressBar#progress                    Progress({type: Linear})
 *   style=progressBarStyleHorizontal        → 水平条（**确定进度**）
 *   match 宽 / centerHorizontal             .width('100%')
 * TextView#progress_percent               Text：左对齐、在 progress 下方
 *   alignParentLeft / below=progress        left→容器.Start, top→progress.Bottom
 * TextView#progress_number                Text：右对齐、在 progress 下方
 *   alignParentRight / below=progress       right→容器.End, top→progress.Bottom
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 三个子元素的关系是"进度条占满一行 + 下方左右两个文本"→ ArkUI 用 Column 即可
 *    （第一行进度条，第二行 Row 两端对齐），**不需要 RelativeContainer**：
 *    约束更少、更稳（与 preference_widget_seekbar 同一判断）。
 * 2. 两个 TextView **都在 progress 下方**、一个贴左一个贴右，中间无内容 → 用 Row +
 *    `justifyContent(FlexAlign.SpaceBetween)`。
 * 3. 上游未设 textSize/textColor（AOSP 用主题默认）→ @Prop 注入位保留，默认 14fp。
 * 4. 与 progress_dialog_material 的区别：**那个是圆形不确定进度**（转圈），
 *    这个是**水平确定进度**（带 percent/number）。两者不能混用。
 * 5. `?attr/dialogPreferredPadding` 与 `@dimen/dialog_padding_top_material` 值同为 24 但来源不同
 *    → 两个 @Prop（主题化会分叉）。
 */

@Component
export struct AlertDialogProgressMaterialLayout {
  @Prop progressPercent: string = '';
  @Prop progressNumber: string = '';
  @Prop value: number = 0;
  @Prop total: number = 100;
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop fontSize: number = 14;
  @Prop dialogPreferredPadding: number = 24;
  /** 上游 @dimen/dialog_padding_top_material（24dp，**无 abc_ 前缀**） */
  @Prop dialogPaddingTop: number = 24;

  build() {
    Column() {
      // 水平确定进度条（上游 progressBarStyleHorizontal）
      Progress({ value: this.value, total: this.total, type: ProgressType.Linear })
        .width('100%')

      // 下方：左百分比 + 右数值
      Row() {
        Text(this.progressPercent)
          .fontSize(this.fontSize)
          .fontColor(this.textColor)

        Text(this.progressNumber)
          .fontSize(this.fontSize)
          .fontColor(this.textColor)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding({
      left: this.dialogPreferredPadding,
      right: this.dialogPreferredPadding,
      top: this.dialogPaddingTop,
      bottom: this.dialogPaddingTop
    })
    .alignItems(HorizontalAlign.Start)
  }
}
