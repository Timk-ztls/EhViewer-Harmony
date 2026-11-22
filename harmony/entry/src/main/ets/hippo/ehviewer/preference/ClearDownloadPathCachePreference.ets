/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/preference/ClearDownloadPathCachePreference.java（S0165，上游 52 行）
 *
 * 判据：**UI 组件行**（`extends MessagePreference`），自有逻辑只有两处覆写：
 *   onPrepareDialogBuilder：super + 自定义确认按钮文案
 *   onDialogClosed(positiveResult)：**true 时**清缓存（false 时什么都不做）
 * ⇒ 用已交付的 `MessagePreference` 组合 + 动作注入（清缓存逻辑属 core-runtime 的 PreferenceActions）。
 */
import { MessagePreference } from '../../preference/MessagePreference';

@Component
export struct ClearDownloadPathCachePreference {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop message: ResourceStr = '';
  @Prop positiveText: ResourceStr = '';
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  /** 对位 onDialogClosed(true) → 清缓存（core-runtime 的 PreferenceActions.clearDownloadPathCache） */
  onClear: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  private effectiveMessage(): ResourceStr {
    if (typeof this.message === 'string') {
      return this.message.length > 0 ? this.message : $r('app.string.settings_advanced_clear_download_path_cache_message');
    }
    return this.message;
  }

  build() {
    MessagePreference({
      title: this.title,
      summary: this.summary,
      message: this.effectiveMessage(),
      positiveText: this.positiveText,
      negativeText: $r('app.string.cancel'),
      showNegativeButton: true,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onShown: () => {
        // 只有按确定才会走到这里（MessagePreference 的 onShown ≡ onDialogClosed(true)）
        this.onClear();
      },
      onCancel: () => {
        this.onCancel();
      }
    })
  }
}
