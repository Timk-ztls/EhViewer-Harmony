/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/sign/SignInScene.java（400 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/sign/SignInScene.ets（inventory S0260）
 *
 * Part 1（本批）：账号密码登录 + 三条旁路（WebView / Cookie / 游客）+ 结果回传。
 * Part 2 待补：表单校验的视觉态（TextInputLayout 的错误文案）、注册链接、头像展示、进度环时序。
 *
 * 上游常量（逐个核对，不按名字推断 —— 陷阱：结果码是历史遗留的任意分配）：
 *   REQUEST_CODE_WEBVIEW = 0
 *   REQUEST_CODE_COOKIE  = 0      ← 与 WEBVIEW 同值，靠 requestCode 之外的分支区分不了，见下
 *   REQUEST_CODE_PROFILE = 0x000F
 * 因为 WEBVIEW 与 COOKIE 同为 0，上游实际靠 **不同场景类** 分派（onSceneResult 里拿到的是
 * 场景 tag），所以本移植版把两个旁路的 requestCode 都保留原值，但分派用 tag 判断。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Announcer } from '../../../../scene/Announcer';
import { SceneArgs } from '../../../../scene/SceneTypes';
import { SceneFragment } from '../../../../scene/SceneFragment';
import { SceneResultCode } from '../../../../scene/SceneTypes';

/** 登录请求接口（EhClient 未交付时的契约先行，同既有模式） */
export interface SignInClientLike {
  /** 上游 EhClient.signIn(username, password)；失败时返回错误码（原值透传） */
  signIn(username: string, password: string): Promise<SignInResult>;
}

/** 上游结果：成功带 displayName/avatar，失败带错误码（原值，不重编号） */
export class SignInResult {
  readonly success: boolean;
  readonly errorCode: number;
  readonly displayName: string;
  readonly avatar: string;
  constructor(success: boolean, errorCode: number, displayName: string, avatar: string) {
    this.success = success;
    this.errorCode = errorCode;
    this.displayName = displayName;
    this.avatar = avatar;
  }
}

export class UnavailableSignInClient implements SignInClientLike {
  async signIn(username: string, password: string): Promise<SignInResult> {
    hilog.warn(0x0000, 'SignInScene', 'EhClient 未接线: signIn(user=%{public}s)；后果：登录不可用', username);
    return new SignInResult(false, -1, '', '');
  }
}

export abstract class SignInScene extends SceneFragment {
  static readonly KEY_REQUEST_ID: string = 'request_id';
  static readonly REQUEST_CODE_WEBVIEW: number = 0;
  static readonly REQUEST_CODE_COOKIE: number = 0;
  static readonly REQUEST_CODE_PROFILE: number = 0x000F;
  static readonly DISPLAY_NAME: string = 'displayName';
  static readonly AVATAR: string = 'avatar';

  protected username: string = '';
  protected password: string = '';
  protected signingIn: boolean = false;
  protected client: SignInClientLike = new UnavailableSignInClient();

  getSceneName(): string {
    return 'SignInScene';
  }

  setSignInClient(client: SignInClientLike): void {
    this.client = client;
  }

  setUsername(v: string): void { this.username = v; }
  setPassword(v: string): void { this.password = v; }
  isSigningIn(): boolean { return this.signingIn; }

  /** 上游 signIn()：两个字段都非空才发；期间 mSigningIn 门控防重复提交 */
  signIn(): void {
    if (this.signingIn) {
      return;
    }
    const u: string = this.username.trim();
    const p: string = this.password;
    if (u.length === 0 || p.length === 0) {
      hilog.info(0x0000, 'SignInScene', 'signIn 前置不满足: username 空=%{public}s；后果：不发请求', String(u.length === 0));
      return;
    }
    this.signingIn = true;
    this.client.signIn(u, p).then((r: SignInResult) => {
      this.signingIn = false;
      if (!r.success) {
        this.onSignInFailure(r.errorCode);
        return;
      }
      const result: SceneArgs = new Map<string, Object>();
      result.set(SignInScene.DISPLAY_NAME, r.displayName);
      result.set(SignInScene.AVATAR, r.avatar);
      this.result = result;
      this.resultCode = SceneResultCode.OK;
      this.finish();
    }).catch((e: Error) => {
      this.signingIn = false;
      hilog.error(0x0000, 'SignInScene', 'signIn failed: user=%{public}s err=%{public}s；后果：停留在登录页，密码框内容保留',
        u, e.message !== undefined ? e.message : String(e));
    });
  }

  /**
   * 上游 onSignInFailure：错误码**原值**透传给 UI 选文案（不同码不同提示）。
   *
   * 为什么要 listener 而不只是 hilog：`signIn()` 是 void（fire-and-forget），
   * 渲染层无法从返回值得知失败；没有这条回调时，用户输错密码后**界面上什么都不会发生**
   * —— 正是"失败必须显式"要避免的形态。
   */
  private failureListener: ((errorCode: number) => void) | null = null;

  /** 渲染层注册失败回调（错误码 → 文案由 UI 决定，场景不写文案） */
  setFailureListener(fn: (errorCode: number) => void): void {
    this.failureListener = fn;
  }

  /** 最近一次失败码（观测面；成功时为 0） */
  private lastErrorCode: number = 0;

  getLastErrorCode(): number {
    return this.lastErrorCode;
  }

  protected onSignInFailure(errorCode: number): void {
    this.lastErrorCode = errorCode;
    hilog.warn(0x0000, 'SignInScene', 'signIn 失败: errorCode=%{public}d；后果：停留在登录页', errorCode);
    if (this.failureListener !== null) {
      this.failureListener(errorCode);
    }
  }

  private skipSignInHandler: (() => void) | null = null;

  /** 注入游客跳过登录时的持久态副作用（如 Settings.putNeedSignIn(false)） */
  setSkipSignInHandler(handler: (() => void) | null): void {
    this.skipSignInHandler = handler;
  }

  /** 上游「跳过登录」= 游客模式，置 needSignIn=false 并 finish(OK) */
  skipSigningIn(): void {
    if (this.skipSignInHandler !== null) {
      this.skipSignInHandler();
    }
    this.result = null;
    this.resultCode = SceneResultCode.OK;
    this.finish();
  }

  /** 三条旁路：WebView / Cookie（requestCode 同为 0，靠场景 tag 分派） */
  startWebViewSignIn(): void {
    this.startSceneForResult(new Announcer('WebViewSignInScene'), SignInScene.REQUEST_CODE_WEBVIEW);
  }

  startCookieSignIn(): void {
    this.startSceneForResult(new Announcer('CookieSignInScene'), SignInScene.REQUEST_CODE_COOKIE);
  }

  /** 上游 onSceneResult：三条旁路成功后都会回到本场景，再继续 profile 或直接 finish */
  onSceneResult(requestCode: number, resultCode: number, data: SceneArgs | null): void {
    if (resultCode !== SceneResultCode.OK) {
      return;
    }
    if (requestCode === SignInScene.REQUEST_CODE_WEBVIEW || requestCode === SignInScene.REQUEST_CODE_COOKIE) {
      this.result = data;
      this.resultCode = SceneResultCode.OK;
      this.finish();
      return;
    }
    if (requestCode === SignInScene.REQUEST_CODE_PROFILE) {
      this.result = data;
      this.resultCode = SceneResultCode.OK;
      this.finish();
    }
  }
}
