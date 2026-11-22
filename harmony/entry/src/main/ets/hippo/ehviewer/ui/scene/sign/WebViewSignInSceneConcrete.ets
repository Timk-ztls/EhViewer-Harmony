/*
 * U-02b：`WebViewSignInScene` 的薄子类。默认注入 `UnavailableWebCookieManager`。
 * cookieJar / signInUrl 由宿主在启动本场景时注入（它们没有安全的默认值），此处不伪造。
 */
import { WebViewSignInScene } from './WebViewSignInScene';
import { UnavailableWebCookieManager } from './WebViewSignInScene';

export class WebViewSignInSceneConcrete extends WebViewSignInScene {
  constructor() {
    super();
    this.setCookieManager(new UnavailableWebCookieManager());
  }

  getSceneName(): string {
    return 'WebViewSignInScene';
  }
}
