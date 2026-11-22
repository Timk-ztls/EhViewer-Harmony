/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/sign/CookieSignInScene.java（319 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/sign/CookieSignInScene.ets（inventory S0258）
 *
 * Part 1（本批）：三个字段（ipb_member_id / ipb_pass_hash / igneous）+ 旧 cookie 回填 +
 *                 从剪贴板导入 + 写 cookie + 结果回传。
 * Part 2 待补：字段级错误提示、igneous 为空时的警告对话框文案、导入成功/失败的 Toast 文案。
 *
 * 上游事实（grep 确认，不推断）：
 *   三个键名就是 cookie 名：ipb_member_id / ipb_pass_hash / igneous
 *   旧值从 SharedPreferences 读同名键回填（"Try to get old version cookie info"）
 *   needShowLeftDrawer() = false（登录页无侧栏）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../../../scene/SceneTypes';
import { SceneFragment } from '../../../../scene/SceneFragment';
import { SceneResultCode } from '../../../../scene/SceneTypes';

/** cookie 读写（生产实现包 @ohos.web.webview 的 WebCookieManager） */
export interface CookieWriterLike {
  setCookie(url: string, cookie: string): void;
  getCookie(url: string): string;
}

/** 旧值来源（上游 SharedPreferences） */
export interface LegacyCookieStoreLike {
  getString(key: string): string;
}

/** 剪贴板（上游 ClipboardManager） */
export interface ClipboardLike {
  getText(): string;
}

export class UnavailableCookieWriter implements CookieWriterLike {
  setCookie(url: string, cookie: string): void {
    hilog.warn(0x0000, 'CookieSignInScene', 'WebCookieManager 未接线: setCookie(url=%{public}s)；后果：cookie 未写入', url);
  }
  getCookie(url: string): string {
    return '';
  }
}

export class UnavailableLegacyStore implements LegacyCookieStoreLike {
  getString(key: string): string {
    return '';
  }
}

export class UnavailableClipboard implements ClipboardLike {
  getText(): string {
    return '';
  }
}

export abstract class CookieSignInScene extends SceneFragment {
  static readonly KEY_IPB_MEMBER_ID: string = 'ipb_member_id';
  static readonly KEY_IPB_PASS_HASH: string = 'ipb_pass_hash';
  static readonly KEY_IGNEOUS: string = 'igneous';

  protected ipbMemberId: string = '';
  protected ipbPassHash: string = '';
  protected igneous: string = '';

  protected writer: CookieWriterLike = new UnavailableCookieWriter();
  protected legacy: LegacyCookieStoreLike = new UnavailableLegacyStore();
  protected clipboard: ClipboardLike = new UnavailableClipboard();

  getSceneName(): string {
    return 'CookieSignInScene';
  }

  /** 上游 needShowLeftDrawer() = false */
  needShowLeftDrawer(): boolean {
    return false;
  }

  setCookieWriter(w: CookieWriterLike): void { this.writer = w; }
  setLegacyStore(s: LegacyCookieStoreLike): void { this.legacy = s; }
  setClipboard(c: ClipboardLike): void { this.clipboard = c; }

  /** 上游 onCreateView2 尾部：用旧 cookie 回填三个输入框 */
  restoreLegacyCookies(): void {
    const id: string = this.legacy.getString(CookieSignInScene.KEY_IPB_MEMBER_ID);
    const pass: string = this.legacy.getString(CookieSignInScene.KEY_IPB_PASS_HASH);
    const ign: string = this.legacy.getString(CookieSignInScene.KEY_IGNEOUS);
    if (id.length > 0) { this.ipbMemberId = id; }
    if (pass.length > 0) { this.ipbPassHash = pass; }
    if (ign.length > 0) { this.igneous = ign; }
  }

  setFields(memberId: string, passHash: string, igneous: string): void {
    this.ipbMemberId = memberId.trim();
    this.ipbPassHash = passHash.trim();
    this.igneous = igneous.trim();
  }

  getIpbMemberId(): string { return this.ipbMemberId; }
  getIpbPassHash(): string { return this.ipbPassHash; }
  getIgneous(): string { return this.igneous; }

  /** 上游 importInClipboard：把剪贴板里的三行/分号/冒号分隔串填进输入框 */
  importCookieFromClipboard(): boolean {
    const text: string = this.clipboard.getText();
    if (text.length === 0) {
      hilog.info(0x0000, 'CookieSignInScene', 'importCookie: 剪贴板为空；后果：字段不变');
      return false;
    }
    const idMatch: RegExpMatchArray | null = text.match(/ipb_member_id\s*[:=]\s*([^;\s\r\n]+)/i);
    const passMatch: RegExpMatchArray | null = text.match(/ipb_pass_hash\s*[:=]\s*([^;\s\r\n]+)/i);
    const ignMatch: RegExpMatchArray | null = text.match(/igneous\s*[:=]\s*([^;\s\r\n]+)/i);
    if (idMatch !== null) { this.ipbMemberId = idMatch[1]; }
    if (passMatch !== null) { this.ipbPassHash = passMatch[1]; }
    if (ignMatch !== null) { this.igneous = ignMatch[1]; }
    if (idMatch === null || passMatch === null) {
      hilog.warn(0x0000, 'CookieSignInScene', 'importCookie: 未匹配到 ipb_member_id/ipb_pass_hash；后果：字段部分未填');
    }
    return idMatch !== null || passMatch !== null || ignMatch !== null;
  }

  /**
   * 上游 OK 按钮：三个键拼成 cookie 串写入，成功即设置 resultCode=OK 并 finish。
   * 上游判据：mIpbMemberId / mIpbPassHash 必须有；igneous 可空（空时上游会提示但允许提交）。
   */
  apply(): boolean {
    if (this.ipbMemberId.length === 0 || this.ipbPassHash.length === 0) {
      hilog.info(0x0000, 'CookieSignInScene', 'apply 前置不满足: memberId 空=%{public}s passHash 空=%{public}s；后果：不写 cookie',
        String(this.ipbMemberId.length === 0), String(this.ipbPassHash.length === 0));
      return false;
    }
    let cookie: string = CookieSignInScene.KEY_IPB_MEMBER_ID + '=' + this.ipbMemberId
      + '; ' + CookieSignInScene.KEY_IPB_PASS_HASH + '=' + this.ipbPassHash;
    if (this.igneous.length > 0) {
      cookie = cookie + '; ' + CookieSignInScene.KEY_IGNEOUS + '=' + this.igneous;
    }
    try {
      this.writer.setCookie('https://e-hentai.org/', cookie);
    } catch (e) {
      hilog.error(0x0000, 'CookieSignInScene', 'setCookie failed: err=%{public}s；后果：登录未生效，停留在本页',
        (e as Error).message);
      return false;
    }
    this.resultCode = SceneResultCode.OK;
    this.finish();
    return true;
  }
}
