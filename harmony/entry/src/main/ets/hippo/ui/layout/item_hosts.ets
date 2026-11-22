/*
 * 上游：app/src/main/res/layout/item_hosts.xml（inventory S0626，上游 36 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_hosts.ets
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                 ArkUI
 * LinearLayout(vertical)                  Column
 *   paddingLeft/Right=@dimen/keyline_margin（16dp）  .padding({left:16,right:16})
 *   paddingTop/Bottom=8dp                          .padding({top:8,bottom:8})
 * TextView#host                             Text
 *   textColor=?android:attr/textColorPrimary        .fontColor(textColorPrimary)
 * TextView#ip                               Text
 *   layout_marginTop=8dp                            .margin({top:8})
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `@dimen/keyline_margin` 已由 ui-widget 迁到 `resources/base/element/dimens.json`
 *    （值为 16dp），这里直接写 16vp 并在注释标明来源；不 import JSON（ArkUI 资源用 $r 引用，
 *    该 dimen 未注册进 float.json，故用字面量 + 注释，避免构建期资源缺失）。
 * 2. `?android:attr/textColorPrimary` 无 attr 解析 → @Prop 注入，默认 `#DE000000`（Material 浅色）。
 * 3. TextView 无字号设置 → 用系统默认正文 16fp（上游未指定 textSize，沿用主题默认）。
 */

@Component
export struct HostsItemLayout {
  @Prop host: string = '';
  @Prop ip: string = '';

  // 主题注入位（上游 ?android:attr/textColorPrimary）
  @Prop textColor: ResourceColor = '#DE000000';

  build() {
    Column() {
      Text(this.host)
        .fontSize(16)
        .fontColor(this.textColor)
        .width('100%')
        .textAlign(TextAlign.Start)

      Text(this.ip)
        .fontSize(16)
        .fontColor(this.textColor)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }
}
