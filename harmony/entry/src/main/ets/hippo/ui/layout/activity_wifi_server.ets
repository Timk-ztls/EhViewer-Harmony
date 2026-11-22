/*
 * 上游：app/src/main/res/layout/activity_wifi_server.xml（72 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_wifi_server.ets（inventory S0562）
 *
 * ============================================================================
 * 本文件修补的骨架缺口（auditor-ui 量化 28/82：Spinner 未生成）
 * ============================================================================
 * 生成期缺的一块：`Spinner#migrate_spinner`（`entries=@array/migrate_data_types`）→ ArkUI `Select`。
 * 本版补齐，并按上游顺序还原四个可见节点。
 *
 * 结构（逐节点对照）：
 *   LinearLayout(vertical)
 *     TextView（**无 id**，wifi_server_illustrate，margin 10，colorPrimaryDark，textSize dad_bar_size）
 *     Spinner#migrate_spinner（wrap_content，paddingHorizontal=spinner_horizontal_padding）
 *     Button#status_change（margin 10，textAllCaps=false）
 *     ── 上游这里有 3 组**整块注释掉**的 LinearLayout（send_bookmark / send_download / send_favorite）
 *     TextView#receive（margin 10，wifi_send_text）
 *
 * 三处**移植陷阱**：
 *   1. 上游 XML 里那三组按钮是**注释**（`<!-- <Button ...> -->`），不是"待生成"——
 *      **不要补**，补上就是新增功能（已按注释保留在下方）；
 *   2. `Spinner` 的 `entries` 是**数组资源**（`migrate_data_types`），ArkUI `Select` 要
 *      `SelectOption[]`；数组内容由字符串资源侧提供，这里只声明 `options` 入参；
 *   3. 上游根布局同时写了 `orientation="vertical"` **和** 约束属性
 *      （`app:layout_constraint*`，那是 ConstraintLayout 的遗留，`LinearLayout` 会忽略）——
 *      照搬"只有 vertical 生效"，别去实现那些约束。
 */

/** 迁移类型的下拉选项（上游 `@array/migrate_data_types`）。 */
export interface MigrateOption {
  /** 显示文案（已本地化） */
  label: string;
  /** 提交给迁移接口的值（上游 `String.valueOf(position)` 或接口约定值） */
  value: string;
}

@Component
export struct ActivityWifiServerLayout {
  /** 上游 `@id/receive` 的文案（`wifi_send_text`） */
  @Prop receive: ResourceStr = $r('app.string.wifi_send_text');
  /** 上游 `@id/status_change` 的按钮文案（XML 里 `android:text=""`，由代码设置） */
  @Prop statusChange: string = '';
  /** 上游 `Spinner#migrate_spinner` 的 `entries=@array/migrate_data_types` */
  @Prop migrateOptions: MigrateOption[] = [];
  /** 上游 `Spinner` 的当前选中下标 */
  @Prop migrateSelected: number = 0;

  build() {
    Column() {
      // TextView（**无 id** —— 上游就是这么写的，别自己加一个 id）
      Text($r('app.string.wifi_server_illustrate'))
        .margin({ left: 10, right: 10, top: 10, bottom: 10 })
        .fontSize($r('app.float.dad_bar_size'))
        .fontColor($r('app.color.colorPrimaryDark'))

      // Spinner → Select（entries 来自数组资源）
      Select(this.migrateOptions.map((o: MigrateOption): SelectOption => {
        return { value: o.label } as SelectOption;
      }))
        .id('migrate_spinner')
        .selected(this.migrateSelected)
        .value(this.migrateOptions.length > 0 && this.migrateSelected >= 0
          && this.migrateSelected < this.migrateOptions.length
          ? this.migrateOptions[this.migrateSelected].label : '')
        .padding({ left: $r('app.float.spinner_horizontal_padding'),
          right: $r('app.float.spinner_horizontal_padding') })

      Button(this.statusChange)
        .id('status_change')
        .margin({ left: 10, right: 10, top: 10, bottom: 10 })

      // 上游这里被整块注释掉的三组按钮（send_bookmark / send_download / send_favorite）：
      // 保持"不存在"。补上 = 新增功能，必须走 D 编号。
      //   <!-- <Button android:id="@+id/send_bookmark" android:text="@string/wifi_send_bookmark" /> -->
      //   <!-- <Button android:id="@+id/send_download" android:text="@string/wifi_send_download" /> -->
      //   <!-- <Button android:id="@+id/send_favorite" android:text="@string/wifi_send_favorite" /> -->

      Text(this.receive)
        .id('receive')
        .margin({ left: 10, right: 10, top: 10, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
