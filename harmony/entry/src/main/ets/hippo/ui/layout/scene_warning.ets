/*
 * 上游：app/src/main/res/layout/scene_warning.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_warning.ets（inventory S0664）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:textColor=?attr/colorAccent（主题属性，需 ThemeManager 注入）
 *   - android:textColor=?attr/colorPrimary（主题属性，需 ThemeManager 注入）
 *   - com.hippo.widget.MaxSizeContainer → @BuilderParam slot2Builder（自定义控件，属性由 ui-widget 负责）
 *   - ImageView src=@drawable/v_alert_red_x48 → 已迁组件 VAlertRedX48()
 *   - layout_weight=1 已按 layoutWeight 直传（父容器主轴为横时即等价）
 */

import { VAlertRedX48 } from '../drawable/v_alert_red_x48';

@Component
export struct SceneWarningLayout {
  @Prop accept: ResourceStr = $r('app.string.accept');
  @Prop reject: ResourceStr = $r('app.string.reject');
  /**
   * 布局**自己渲染 buttonpanel**，所以必须提供回调 —— 否则调用方会叠一层（两组按钮），
   * 或只删叠加层（看得见点不动的死按钮）。形态照抄 scene_select_site.ets 的 onOk。
   */
  onAccept: () => void = (): void => {};
  onReject: () => void = (): void => {};

  @BuilderParam slot2Builder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      VAlertRedX48().padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
      Column() {
        this.slot2Builder()
      }.id('slot2').layoutWeight(1)
      Row() {
        Button(this.reject).id('reject').layoutWeight(1)
          .onClick(() => { this.onReject(); })
        Button(this.accept).id('accept').layoutWeight(1)
          .onClick(() => { this.onAccept(); })
      }.id('buttonpanel').width('100%')
    }.width('100%').height('100%').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
  }
}
