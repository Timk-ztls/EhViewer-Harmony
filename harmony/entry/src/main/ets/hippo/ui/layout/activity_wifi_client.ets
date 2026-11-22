/*
 * 上游：app/src/main/res/layout/activity_wifi_client.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_wifi_client.ets（inventory S0561）
 * 生成：scripts/conv/convert_layout.ps1（结构骨架 + 逐 id 数据绑定字段）
 * 映射：FrameLayout→Stack / LinearLayout→Row|Column / RelativeLayout·ConstraintLayout→RelativeContainer
 *       ScrollView→Scroll / RecyclerView→List / ViewPager→Swiper / CardView→Column
 *       TextView→Text(@Prop) / ImageView→Image(@Prop Src) / Button→Button / EditText→TextInput
 *       com.* 自定义控件→@BuilderParam 槽位（ui-widget 注入）
 *
 * 无法等价 / 需人工接续（生成期统计）：
 *   （无）
 */

@Component
export struct ActivityWifiClientLayout {
  @Prop connectServer: ResourceStr = $r('app.string.wifi_server_connect');
  @Prop receiveMessage: string = '';
  @Prop statusInfo: string = 'status';
  @Prop statusInit: string = 'init';


  build() {
    Column() {
      Text(this.statusInit).id('statusInit').margin({ left: 10, right: 10, top: 10, bottom: 10 })
      Text(this.statusInfo).id('statusInfo').margin({ left: 10, right: 10, top: 10, bottom: 10 })
      Button(this.connectServer).id('connectServer').margin({ left: 10, right: 10, top: 10, bottom: 10 })
      Text(this.receiveMessage).id('receiveMessage').margin({ left: 10, right: 10, top: 10, bottom: 10 })
    }.width('100%').height('100%').padding({ left: 10, right: 10, top: 10, bottom: 10 })
  }
}
