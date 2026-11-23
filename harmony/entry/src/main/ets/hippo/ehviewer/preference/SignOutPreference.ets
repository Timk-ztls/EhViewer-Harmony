/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/preference/SignOutPreference.kt（S0173，上游 66 行）
 *
 * 判据：**UI 组件行**（`class SignOutPreference : MessagePreference`），覆写两处：
 *   init()：setDialogMessage(settings_eh_sign_out_warning)   ← 警告文案
 *   onPrepareDialogBuilder：自定义确认按钮文案
 *   onDialogClosed(positiveResult)：**true 时**执行登出（清 cookie + 重启），false 无动作
 * ⇒ 组合 `MessagePreference` + 动作注入。
 */
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MessagePreference } from '../../preference/MessagePreference';
import { AppWiring } from '../../AppWiring';
import { Settings } from '../Settings';
import { EhCookieStore } from '../client/EhCookieStore';
import { EhUtils } from '../client/EhUtils';

export interface SignOutCookieStoreLike {
  signOut(): void;
}

export class SignOutHelper {
  static performSignOut(cookieStore: SignOutCookieStoreLike | null, setLoginState: (v: boolean) => void): void {
    if (cookieStore !== null) {
      cookieStore.signOut();
    }
    setLoginState(false);
  }
}

class EhSignOutCookieStoreAdapter implements SignOutCookieStoreLike {
  private readonly store: EhCookieStore;

  constructor(store: EhCookieStore) {
    this.store = store;
  }

  signOut(): void {
    this.store.signOut();
  }
}

@Component
export struct SignOutPreference {
  @Prop title: string = '';
  @Prop summary: string = '';
  /** 上游 settings_eh_sign_out_warning */
  @Prop warningMessage: ResourceStr = '';
  /** 上游 settings_eh_sign_out_yes */
  @Prop positiveText: ResourceStr = '';
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  /** 对位 onDialogClosed(true) → 登出后通知（如显示 toast / 刷新页面状态） */
  onSignOut: () => void = () => {
  };
  onCancel: () => void = () => {
  };

  private effectiveMessage(): ResourceStr {
    if (typeof this.warningMessage === 'string') {
      return this.warningMessage.length > 0 ? this.warningMessage : $r('app.string.settings_eh_sign_out_warning');
    }
    return this.warningMessage;
  }

  private effectivePositiveText(): ResourceStr {
    if (typeof this.positiveText === 'string') {
      return this.positiveText.length > 0 ? this.positiveText : $r('app.string.settings_eh_sign_out_yes');
    }
    return this.positiveText;
  }

  build() {
    MessagePreference({
      title: this.title,
      summary: this.summary,
      message: this.effectiveMessage(),
      positiveText: this.effectivePositiveText(),
      negativeText: $r('app.string.cancel'),
      showNegativeButton: true,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onShown: () => {
        const cookieStore: EhCookieStore | null = AppWiring.getCookieStore();
        const adapted: SignOutCookieStoreLike | null =
          cookieStore !== null ? new EhSignOutCookieStoreAdapter(cookieStore) : null;
        SignOutHelper.performSignOut(adapted, (v: boolean) => {
          Settings.setLoginState(v);
        });
        EhUtils.signOut();
        Settings.putDisplayName(null);
        Settings.putAvatar(null);
        Settings.putNeedSignIn(true);
        void Settings.flush();
        try {
          webview.WebCookieManager.clearAllCookiesSync();
          webview.WebCookieManager.saveCookieAsync((_err: Object): void => {
            // Best-effort async cookie flush on sign out
          });
        } catch (e) {
          hilog.debug(0x0000, 'SignOutPreference', 'clear ArkWeb cookies skipped: %{public}s',
            e instanceof Error ? e.message : String(e));
        }
        this.onSignOut();
      },
      onCancel: () => {
        this.onCancel();
      }
    })
  }
}
