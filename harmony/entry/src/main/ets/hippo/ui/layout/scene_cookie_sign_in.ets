/*
 * 上游：app/src/main/res/layout/scene_cookie_sign_in.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/scene_cookie_sign_in.ets（inventory S0647）
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
 *   - ImageView src=@drawable/v_cookie_brown_x48 → 已迁组件 VCookieBrownX48()
 *   - layout_weight=1 已按 layoutWeight 直传（父容器主轴为横时即等价）
 */

import { VCookieBrownX48 } from '../drawable/v_cookie_brown_x48';

@Component
export struct SceneCookieSignInLayout {
  @Prop importInClipboard: ResourceStr = $r('app.string.cookie_login_import_in_clipboard');
  @Prop ok: string = '@android:string/ok';

  @BuilderParam slot2Builder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      VCookieBrownX48().padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
      Column() {
        this.slot2Builder()
      }.id('slot2').layoutWeight(1)
      Row() {
        Button(this.importInClipboard).id('importInClipboard').layoutWeight(1)
        Button(this.ok).id('ok').layoutWeight(1)
      }.id('buttonpanel').width('100%')
    }.width('100%').height('100%').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
  }
}
