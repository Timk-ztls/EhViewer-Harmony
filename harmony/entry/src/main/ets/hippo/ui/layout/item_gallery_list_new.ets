/*
 * 上游：app/src/main/res/layout/item_gallery_list_new.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_list.ets（inventory S0620）
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                   ArkUI
 * CardView(style=CardView.Reactive, m=2dp)  Column + .backgroundColor(contentColorReactive)（见「无法等价」1）
 * RelativeLayout                            RelativeContainer + 各子组件 .id() / .alignRules()
 * com.hippo.ehviewer.widget.FixedThumbNew   @BuilderParam thumbBuilder（ui-widget 提供 FixedThumbNew）
 *   maxAspect=1.333 minAspect=0.333         → FixedThumb 内部按 max/minAspect 约束，布局侧只给宽高
 *   （上游 _new 变体没有 retryType 属性：重试逻辑在 FixedThumbNew 内部）
 * TextView#title  (CardTitle)               Text.title：16fp / textColorPrimary / ellipsize end / maxLines 2
 * TextView#uploader (CardMessage)           Text.uploader：14fp / textColorSecondary / maxLines 1
 * TextView#category (CardMessage + 白字)     Text.category：white、allCaps、8/2 padding、贴 thumb 底
 * SimpleRatingView#rating                   @BuilderParam ratingBuilder（ui-widget 提供 SimpleRatingView）
 * TextView#posted                           Text.posted：贴 thumb 底 + 父右
 * LinearLayout(horizontal, divider=6dp)      Row + space 6vp（原 spacer_x6 drawable，见「无法等价」4）
 *   ImageView#downloaded / #favourited      Image，默认 gone → 由 @Prop 控制 visibility
 *   TextView#simple_language / #pages       Text
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `?attr/contentColorReactive` 是运行期主题属性（浅/深/黑三套随主题切换），
 *    HarmonyOS 没有 attr 解析；本布局先落到可替换的 @Prop，默认取 base 的浅色卡片色，
 *    由 core-runtime 的主题管理器（D-012 之后的 ThemeManager）在页面初始化时注入。
 * 2. `android:textAllCaps="true"`：ArkUI 无 textAllCaps 属性 → 由数据侧 toUpperCase() 保证
 *    （文字大小写属数据而非布局，避免布局层做 locale 相关的字符串变换）。
 * 3. `style="@style/CardView.Reactive"` 的 elevation/阴影：ArkUI 用 `.shadow()`，
 *    上游 CardView 的 material 阴影半径无法逐像素复现（卡片阴影参数取 CardView 默认 2dp）。
 * 4. `divider="@drawable/spacer_x6"` + `showDividers="middle"`：上游用 1x6dp 透明 spacer 图做间隔，
 *    ArkUI 直接用 Row 的 space=6vp，不需要 drawable。
 * 5. `android:visibility="gone"` 的两个 ImageView 由 downloaded/favourited 两个图标槽位承担（资源属 ui-widget）；ArkUI 用 if 条件渲染，不占位（同 gone 语义，
 *    与 invisible 语义不同——上游是 gone）。
 */

/**
 * 字段名沿用上游 R.id（驼峰化），一行一条，便于与 XML 逐 id 对照。
 * 数据模型不直接引用 net-parse 的 GalleryInfo：ArkTS 无结构化类型，
 * 跨模块传对象会被 arkts-no-structural-typing 拒绝，故由使用方逐字段赋值。
 */
@Component
export struct GalleryListItemNewLayout {
  // ---- 数据（对应 XML 中的 R.id.*） ----
  @Prop title: string = '';
  @Prop uploader: string = '';
  @Prop category: string = '';
  @Prop categoryTextColor: ResourceColor = Color.White;
  @Prop posted: string = '';
  @Prop simpleLanguage: string = '';
  @Prop pages: string = '';
  @Prop downloaded: boolean = false;
  @Prop favourited: boolean = false;
  /** 卡片底色：上游 CardView.Reactive → ?attr/contentColorReactive，由主题层注入 */
  @Prop cardColor: ResourceColor = '#FAFAFA';
  @Prop titleColor: ResourceColor = '#DE000000';
  @Prop messageColor: ResourceColor = '#8A000000';

  // ---- 控件槽位（ui-widget 提供，避免 ui-scene 直接依赖控件实现） ----
  @BuilderParam thumbBuilder: () => void = this.emptyThumb;
  @BuilderParam ratingBuilder: () => void = this.emptyRating;
  /** 已下载角标（上游 @drawable/v_download_x16，16x16） */
  @BuilderParam downloadedIconBuilder: () => void = this.emptyIcon;
  /** 已收藏角标（上游 @drawable/v_heart_x16，16x16） */
  @BuilderParam favouritedIconBuilder: () => void = this.emptyIcon;

  @Builder
  emptyThumb() {
    // 未注入 FixedThumb 时的占位：保持与上游一致的 80x120vp 尺寸，不影响布局对齐
    Column()
      .width($r('app.float.gallery_list_thumb_width'))
      .height($r('app.float.gallery_list_thumb_height'))
      .backgroundColor('#22000000')
  }

  @Builder
  emptyRating() {
    Row().width(0).height(0)
  }

  @Builder
  emptyIcon() {
    // 图标未注入时占位 16x16，保持右侧图标行宽度稳定
    Column().width(16).height(16)
  }

  build() {
    RelativeContainer() {
      // thumb（FixedThumb：80x120vp，aspect 约束由控件内部处理）
      Column() {
        this.thumbBuilder();
      }
      .id('thumb_new')
      .width($r('app.float.gallery_list_thumb_width'))
      .height($r('app.float.gallery_list_thumb_height'))
      .alignRules({
        left: { anchor: '__container__', align: HorizontalAlign.Start },
        top: { anchor: '__container__', align: VerticalAlign.Top }
      })

      // title（CardTitle：16fp / maxLines 2 / ellipsize end）
      Text(this.title)
        .id('title')
        .fontSize($r('app.float.text_medium'))
        .fontColor(this.titleColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8, top: 4, right: 8 })
        .alignRules({
          left: { anchor: 'thumb_new', align: HorizontalAlign.End },
          top: { anchor: '__container__', align: VerticalAlign.Top }
        })

      // uploader（CardMessage：14fp / textColorSecondary / 单行）
      Text(this.uploader)
        .id('uploader')
        .fontSize($r('app.float.text_small'))
        .fontColor(this.messageColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
        .alignRules({
          left: { anchor: 'title', align: HorizontalAlign.Start },
          top: { anchor: 'title', align: VerticalAlign.Bottom }
        })

      // category（白字 + allCaps + 贴 thumb 底）
      Text(this.category)
        .id('category')
        .fontSize($r('app.float.text_small'))
        .fontColor(this.categoryTextColor)
        .padding({ left: 8, top: 2, right: 8, bottom: 2 })
        .margin({ bottom: 8 })
        .alignRules({
          left: { anchor: 'title', align: HorizontalAlign.Start },
          bottom: { anchor: 'thumb_new', align: VerticalAlign.Bottom }
        })

      // rating（SimpleRatingView，位于 category 之上、与 title 左对齐）
      Column() {
        this.ratingBuilder();
      }
      .id('rating')
      .margin({ bottom: 4 })
      .alignRules({
        left: { anchor: 'title', align: HorizontalAlign.Start },
        bottom: { anchor: 'category', align: VerticalAlign.Top }
      })

      // posted（贴 thumb 底 + 父右）
      Text(this.posted)
        .id('posted')
        .fontSize($r('app.float.text_small'))
        .fontColor(this.messageColor)
        .maxLines(1)
        .margin({ right: 6, bottom: 4 })
        .alignRules({
          right: { anchor: '__container__', align: HorizontalAlign.End },
          bottom: { anchor: 'thumb_new', align: VerticalAlign.Bottom }
        })

      // 右侧图标行（downloaded / favourited / language / pages），位于 posted 之上
      Row({ space: 6 }) {
        if (this.downloaded) {
          this.downloadedIconBuilder();
        }
        if (this.favourited) {
          this.favouritedIconBuilder();
        }
        Text(this.simpleLanguage)
          .fontSize($r('app.float.text_small'))
          .fontColor(this.messageColor)
          .maxLines(1)
        Text(this.pages)
          .fontSize($r('app.float.text_small'))
          .fontColor(this.messageColor)
          .maxLines(1)
      }
      .id('info_row')
      .margin({ right: 6 })
      .alignRules({
        right: { anchor: '__container__', align: HorizontalAlign.End },
        bottom: { anchor: 'posted', align: VerticalAlign.Top }
      })
    }
    .width('100%')
    .height(144)
    .padding(12)
    .margin(2)
    .borderRadius(2)
    .backgroundColor(this.cardColor)
    .shadow({ radius: 2, color: '#26000000', offsetY: 1 })
  }
}


