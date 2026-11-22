/**
 * 迁移自 app/src/main/java/com/hippo/preference/UrlPreference.java（inventory S0451，上游 54 行）
 *
 * 判据：**完全重复** —— 上游 = "一行标题 + 点击打开 URL（或长按复制）"，无自有逻辑。
 * 上游属性：android:title / android:summary / preprint：url / longClickText。
 *
 * ArkUI 对位：SettingsItem 行 + `onOpenUrl` / `onCopyUrl` 两个注入回调
 *   （打开用 `@ohos.app.ability.common` 的 UIAbilityContext.openLink 或 Want，
 *    复制用 pasteboard —— 两者都属调用方能力，ui-widget 只发意图）。
 * 差异（已登记 MR）：上游内部直接 startActivity(ACTION_VIEW)；鸿蒙侧把"打开"抽象成回调，
 *   由 ui-scene 注入具体实现（避免 ui-widget 依赖 pasteboard/openLink 的权限声明）。
 */
import { SettingsItem } from '../ui/settings/SettingsItem';

@Component
export struct UrlPreference {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop url: string = '';
  @Prop longClickText: string = 'Copy URL';
  @Prop itemEnabled: boolean = true;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  onOpenUrl: (url: string) => void = (url: string) => {
  };
  onCopyUrl: (url: string) => void = (url: string) => {
  };

  build() {
    SettingsItem({
      title: this.title,
      // 上游 getSummary()：if (null != mUrl) return mUrl; else return super.getSummary();`n      // ⇒ 没设 android:summary 时**副标题显示 URL 本身**（about/eh 设置里 3 个 UrlPreference 都没写 summary）
      summary: this.summary.length > 0 ? this.summary : this.url,
      itemEnabled: this.itemEnabled,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onItemClick: () => {
        this.onOpenUrl(this.url);
      }
    })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.onCopyUrl(this.url);
          })
      )
  }
}
