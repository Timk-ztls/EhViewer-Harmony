/**
 * ui-widget · Preference 行骨架（新增层，登记于 inventory/ui-widget.extra.txt 的 hippo/ui/settings/ 前缀）
 *
 * 为什么需要它：Android 的 `Preference` 是 **UI 框架**（`extends Preference` 即获得一行 UI），
 * ArkTS 没有这个类体系；7 个 Preference 框架类（Dialog/List/SeekBar/Switch/Message/Activity/Url）
 * 的**行外观完全同构**：左侧标题 + 副标题、右侧控件、整行可点击。
 * 因此抽一个行骨架，7 个类只提供"右侧控件"与"点击行为"——**一次收口，不留 7 套行布局**
 * （与 `GalleryAdapterBase` 抽基类、`CategoryTable` 收口到 `CheckTextView` 同一思路）。
 *
 * 与上游的对应关系（外观层）
 *   android:title      → SettingsItem.title
 *   android:summary    → SettingsItem.summary（无副标题时不占位）
 *   android:icon       → 由 @BuilderParam leading 提供（不强制）
 *   widgetLayoutResId  → 由 @BuilderParam trailing 提供（Switch / Slider / Select / 文字值 / 按钮）
 *   isEnabled          → itemEnabled（禁用时整行降透明 + 不响应点击，对位上游 setEnabled）
 *   isSelectable       → 非 selectable 时右侧控件自行处理交互，整行不触发 onClick
 *   注：属性名用 itemEnabled 而非 enabled —— CustomComponent 已内置 enabled，重名会编译失败
 */
import { ThemeDimens, ThemePalette, ThemeTokens, ThemeTypography } from '../../../common/theme/ThemeTokens';

@Component
export struct SettingsItem {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop itemEnabled: boolean = true;
  /** 对位上游 isSelectable：false 时整行不响应点击（由右侧控件自己处理） */
  @Prop selectable: boolean = true;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  /** 左侧图标槽（可选） */
  @BuilderParam leading: () => void = this.empty;
  /** 右侧控件槽（Switch / Slider / Select / 文字值） */
  @BuilderParam trailing: () => void = this.empty;
  /** 整行点击（对位 onPreferenceClick） */
  onItemClick: () => void = () => {
  };

  @Builder
  empty(): void {
  }

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  build() {
    Column() {
      Row({ space: ThemeDimens.SPACING_MD }) {
        this.leading()
        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.itemEnabled ? this.palette().textPrimary : this.palette().textDisabled)
            .width('100%')
          if (this.summary.length > 0) {
            Text(this.summary)
              .fontSize(ThemeTypography.PREF_SUMMARY)
              .fontColor(this.itemEnabled ? this.palette().textSecondary : this.palette().textDisabled)
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.trailing()
      }
      .width('100%')
      .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
      .padding({
        left: ThemeDimens.KEYLINE_MARGIN,
        right: ThemeDimens.KEYLINE_MARGIN,
        top: ThemeDimens.SPACING_MD,
        bottom: ThemeDimens.SPACING_MD
      })
      .enabled(this.itemEnabled)
      .onClick(() => {
        if (this.itemEnabled && this.selectable) {
          this.onItemClick();
        }
      })

      if (this.showDivider) {
        Divider()
          .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
          .color(this.palette().divider)
          .width('100%')
      }
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }
}
