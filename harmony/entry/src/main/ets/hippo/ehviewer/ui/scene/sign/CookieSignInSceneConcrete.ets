/*
 * U-02b：`CookieSignInScene` 的薄子类。默认注入三个 Unavailable 兜底（写 cookie / 旧值 / 剪贴板）。
 */
import { CookieSignInScene } from './CookieSignInScene';
import {
  UnavailableCookieWriter, UnavailableLegacyStore, UnavailableClipboard
} from './CookieSignInScene';

export class CookieSignInSceneConcrete extends CookieSignInScene {
  constructor() {
    super();
    this.setCookieWriter(new UnavailableCookieWriter());
    this.setLegacyStore(new UnavailableLegacyStore());
    this.setClipboard(new UnavailableClipboard());
  }

  getSceneName(): string {
    return 'CookieSignInScene';
  }
}
