/*
 * 上游：app/src/main/res/layout/bookmarks_draw.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/bookmarks_draw.ets（inventory S0565）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   - android:background=@drawable/shadow_bottom → 已迁组件 ShadowBottom()，需手工改为子元素叠加或 .background()
 *   - android:layout_gravity=center（Stack 内对齐，已按 Alignment 近似）
 *   - android:layout_weight=1（ArkUI 用 .layoutWeight()，需按父容器主轴重算）
 *   - androidx.appcompat.widget.Toolbar（未识别节点，未生成）
 *   - layout_width/height=0dp：上游靠 weight 撑开，ArkUI 需 layoutWeight 或固定值
 */

import { ShadowBottom } from '../drawable/shadow_bottom';

@Component
export struct BookmarksDrawLayout {
  @Prop tip: string = '';
  @Prop tipVisibility: Visibility = Visibility.None;


  build() {
    Column() {
      // androidx.appcompat.widget.Toolbar 未识别
      Stack() {
        Stack() {
        ShadowBottom()
      }.width('100%').height(8)
        Text(this.tip).id('tip').visibility(this.tipVisibility).align(Alignment.Center)
        List() {
        }.id('listView').width('100%').height('100%')
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%')
  }
}



