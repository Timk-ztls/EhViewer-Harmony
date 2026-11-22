/*
 * 上游：app/src/main/res/layout/activity_dir_picker.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_dir_picker.ets（inventory S0549）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:layout_gravity=left（Stack 内对齐，已按 Alignment 近似）
 *   - android:layout_gravity=right（Stack 内对齐，已按 Alignment 近似）
 *   - android:textColor=?android:attr/textColorPrimary（主题属性，需 ThemeManager 注入）
 *   - android:textColor=?attr/colorAccent（主题属性，需 ThemeManager 注入）
 *   - android:textColor=?attr/colorPrimary（主题属性，需 ThemeManager 注入）
 *   - com.hippo.widget.DirExplorer → @BuilderParam dirExplorerBuilder（自定义控件，属性由 ui-widget 负责）
 *   - layout_weight=1 已按 layoutWeight 直传（父容器主轴为横时即等价）
 */

@Component
export struct ActivityDirPickerLayout {
  @Prop ok: string = '@android:string/ok';
  @Prop path: string = '';
  @Prop preset: ResourceStr = $r('app.string.preset');

  @BuilderParam dirExplorerBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Column() {
      Text(this.path).id('path').width('100%').fontSize($r('app.float.text_little_small')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Column() {
        this.dirExplorerBuilder()
      }.id('dirExplorer').width('100%').layoutWeight(1)
      Stack() {
        Text(this.preset).id('preset').align(Alignment.Start)
        Text(this.ok).id('ok').align(Alignment.End)
      }.width('100%')
    }.width('100%').height('100%').padding({ left: $r('app.float.keyline_margin'), right: $r('app.float.keyline_margin'), top: $r('app.float.keyline_margin'), bottom: $r('app.float.keyline_margin') })
  }
}
