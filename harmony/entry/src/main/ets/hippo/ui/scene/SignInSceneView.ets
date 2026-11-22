/*
 * SignInSceneView: Material Design UI aligned with res/layout/scene_login.xml & SignInScene.java.
 *
 * Preserves public observation API:
 *   static describeError(code: number): string
 *   getLastAction(): string
 *   getActionCount(name: string): number
 *   isSigningIn(): boolean
 */
import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { SignInScene } from '../../ehviewer/ui/scene/sign/SignInScene';

const DOMAIN: number = 0x0000;
const TAG: string = 'SignInSceneView';

@Component
export struct SignInSceneView {
  scene: SignInScene | null = null;
  @Prop themeId: number = -1;

  @State username: string = '';
  @State password: string = '';
  @State usernameFocused: boolean = false;
  @State passwordFocused: boolean = false;
  @State usernameErrorRes: Resource | null = null;
  @State passwordErrorRes: Resource | null = null;
  @State lastAction: string = '';
  @State webViewUnsupported: boolean = false;
  @State message: string = '';
  @State signingInState: boolean = false;

  private counts: Map<string, number> = new Map<string, number>();

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    const s: SignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      this.username = '';
      this.password = '';
      this.usernameErrorRes = null;
      this.passwordErrorRes = null;
      this.signingInState = s.isSigningIn();
      s.setFailureListener((code: number): void => {
        this.signingInState = false;
        this.message = SignInSceneView.describeError(code);
        hilog.warn(DOMAIN, TAG, 'signIn failure code=%{public}d -> %{public}s', code, this.message);
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'aboutToAppear failed: %{public}s', (e as Error).message);
    }
  }

  /**
   * Maps SignInScene error codes to user-facing strings (net-parse signin.test.ts contract).
   */
  static describeError(code: number): string {
    if (code === 0) {
      return '';
    }
    if (code === -1) {
      return '登录服务未就绪（应用内依赖未接线），不是网络问题';
    }
    if (code === -2) {
      return '登录失败：发生未知错误，可稍后重试';
    }
    if (code === -3) {
      return '登录失败：服务器返回内容无法解析（站点页面可能改版）';
    }
    if (code === -4) {
      return '账号或密码错误';
    }
    if (code > 0) {
      return '登录失败：服务器返回 HTTP ' + code.toString();
    }
    return '登录失败：错误码 ' + code.toString();
  }

  private bump(name: string): void {
    const n: number | undefined = this.counts.get(name);
    this.counts.set(name, n === undefined ? 1 : n + 1);
    this.lastAction = name;
  }

  getLastAction(): string {
    return this.lastAction;
  }

  getActionCount(name: string): number {
    const n: number | undefined = this.counts.get(name);
    return n === undefined ? 0 : n;
  }

  isSigningIn(): boolean {
    return this.scene !== null ? this.scene.isSigningIn() : this.signingInState;
  }

  private doSignIn(): void {
    this.bump('signIn');
    const s: SignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    if (s.isSigningIn()) {
      this.signingInState = true;
      return;
    }
    const trimmedUser: string = this.username.trim();
    if (trimmedUser.length === 0) {
      this.usernameErrorRes = $r('app.string.error_username_cannot_empty');
      this.passwordErrorRes = null;
      return;
    }
    this.usernameErrorRes = null;
    if (this.password.length === 0) {
      this.passwordErrorRes = $r('app.string.error_password_cannot_empty');
      return;
    }
    this.passwordErrorRes = null;
    s.setUsername(this.username);
    s.setPassword(this.password);
    this.message = '';
    try {
      this.signingInState = true;
      s.signIn();
      this.signingInState = s.isSigningIn();
    } catch (e) {
      this.signingInState = false;
      this.message = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'signIn threw: %{public}s', this.message);
    }
  }

  private doRegister(): void {
    this.bump('register');
    this.message = '';
    try {
      const ctx: common.UIAbilityContext | undefined =
        this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (ctx === undefined) {
        this.message = '本版本暂不支持在应用内注册';
        hilog.warn(DOMAIN, TAG, 'doRegister: hostContext unavailable');
        return;
      }
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: EhUrl.URL_REGISTER
      };
      ctx.startAbility(want).catch((e: Error): void => {
        const msg: string = e.message !== undefined ? e.message : String(e);
        this.message = '本版本暂不支持在应用内注册';
        hilog.warn(DOMAIN, TAG, 'open register url failed: %{public}s', msg);
      });
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.message = '本版本暂不支持在应用内注册';
      hilog.warn(DOMAIN, TAG, 'doRegister failed: %{public}s', msg);
    }
  }

  private doCookie(): void {
    this.bump('cookie');
    const s: SignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      s.startCookieSignIn();
    } catch (e) {
      this.message = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'startCookieSignIn threw: %{public}s', this.message);
    }
  }

  private doWebView(): void {
    this.bump('webview');
    this.webViewUnsupported = false;
    this.message = '';
    const s: SignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      s.startWebViewSignIn();
    } catch (e) {
      this.message = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'startWebViewSignIn threw: %{public}s', this.message);
    }
  }

  private doGuest(): void {
    this.bump('guest');
    const s: SignInScene | null = this.scene;
    if (s === null) {
      return;
    }
    try {
      s.skipSigningIn();
    } catch (e) {
      this.message = (e as Error).message;
      hilog.error(DOMAIN, TAG, 'skipSigningIn threw: %{public}s', this.message);
    }
  }

  @Builder
  private buildContent(): void {
    Stack({ alignContent: Alignment.Center }) {
      Scroll() {
        Column({ space: 12 }) {
          Image($r('app.media.ic_launcher'))
            .width(48)
            .height(48)
            .objectFit(ImageFit.Contain)
            .margin({ top: ThemeDimens.KEYLINE_MARGIN, bottom: ThemeDimens.KEYLINE_MARGIN })

          Column() {
            TextInput({ placeholder: $r('app.string.username'), text: this.username })
              .width('100%')
              .height(48)
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontColor(this.palette().textPrimary)
              .placeholderColor(this.palette().textHint)
              .caretColor(this.palette().controlActivated)
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding({ left: 0, right: 0 })
              .enterKeyType(EnterKeyType.Next)
              .onFocus((): void => {
                this.usernameFocused = true;
              })
              .onBlur((): void => {
                this.usernameFocused = false;
              })
              .onChange((v: string): void => {
                this.username = v;
                this.usernameErrorRes = null;
              })

            Row()
              .width('100%')
              .height(this.usernameFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
              .backgroundColor(this.usernameErrorRes !== null
                ? this.palette().errorColor
                : (this.usernameFocused ? this.palette().colorAccent : this.palette().divider))

            if (this.usernameErrorRes !== null) {
              Text(this.usernameErrorRes)
                .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                .fontColor(this.palette().errorColor)
                .margin({ top: ThemeDimens.SPACING_XS })
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: $r('app.float.single_max_width') })
          .alignItems(HorizontalAlign.Start)

          Column() {
            TextInput({ placeholder: $r('app.string.password'), text: this.password })
              .type(InputType.Password)
              .width('100%')
              .height(48)
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontColor(this.palette().textPrimary)
              .placeholderColor(this.palette().textHint)
              .caretColor(this.palette().controlActivated)
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding({ left: 0, right: 0 })
              .enterKeyType(EnterKeyType.Done)
              .onFocus((): void => {
                this.passwordFocused = true;
              })
              .onBlur((): void => {
                this.passwordFocused = false;
              })
              .onChange((v: string): void => {
                this.password = v;
                this.passwordErrorRes = null;
              })
              .onSubmit((): void => {
                this.doSignIn();
              })

            Row()
              .width('100%')
              .height(this.passwordFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
              .backgroundColor(this.passwordErrorRes !== null
                ? this.palette().errorColor
                : (this.passwordFocused ? this.palette().colorAccent : this.palette().divider))

            if (this.passwordErrorRes !== null) {
              Text(this.passwordErrorRes)
                .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                .fontColor(this.palette().errorColor)
                .margin({ top: ThemeDimens.SPACING_XS })
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: $r('app.float.single_max_width') })
          .alignItems(HorizontalAlign.Start)

          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().errorColor)
              .width('100%')
              .constraintSize({ maxWidth: $r('app.float.single_max_width') })
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(this.palette().errorBannerBg)
              .borderRadius(ThemeRadius.CARD)
          }

          Blank().layoutWeight(1)

          Row({ space: ThemeDimens.SPACING_MD }) {
            Button({ type: ButtonType.Normal }) {
              Text($r('app.string.register'))
                .fontSize(ThemeTypography.BUTTON)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette().colorAccent)
            }
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .borderRadius(ThemeRadius.BUTTON)
            .onClick((): void => {
              this.doRegister();
            })

            Button({ type: ButtonType.Normal }) {
              Text($r('app.string.sign_in'))
                .fontSize(ThemeTypography.BUTTON)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette().colorPrimary)
            }
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .borderRadius(ThemeRadius.BUTTON)
            .onClick((): void => {
              this.doSignIn();
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })

          Text($r('app.string.sign_in_via_webview'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textThemeAccent)
            .decoration({ type: TextDecorationType.Underline })
            .padding({ top: 4, bottom: 4 })
            .onClick((): void => {
              this.doWebView();
            })

          Text($r('app.string.sign_in_via_cookies'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textThemeAccent)
            .decoration({ type: TextDecorationType.Underline })
            .padding({ top: 4, bottom: 4 })
            .onClick((): void => {
              this.doCookie();
            })

          Text($r('app.string.guest_mode'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textThemeAccent)
            .decoration({ type: TextDecorationType.Underline })
            .padding({ top: 4, bottom: 4 })
            .onClick((): void => {
              this.doGuest();
            })

          Text($r('app.string.settings'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor(this.palette().textThemePrimary)
            .padding({ top: 4, bottom: 4 })
            .onClick((): void => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' }).catch((e: Error): void => {
                const msg: string = e.message !== undefined ? e.message : String(e);
                this.message = msg;
                hilog.warn(DOMAIN, TAG, 'pushUrl(pages/SettingsPage) failed: %{public}s', msg);
              });
            })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding(ThemeDimens.KEYLINE_MARGIN)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)

      if (this.signingInState || this.isSigningIn()) {
        Stack({ alignContent: Alignment.Center }) {
          LoadingProgress()
            .width(ThemeDimens.ICON_SIZE_LARGE)
            .height(ThemeDimens.ICON_SIZE_LARGE)
            .color(this.palette().progressColor)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }

  build() {
    this.buildContent();
  }
}
