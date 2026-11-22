/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/UConfigActivity.java（266 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/UConfigActivity.ets（S0274）
 *
 * 上游事实（读源码确认）：extends ToolbarActivity
 *   字段 webView / progress / url / loaded / okHttpClient
 *   即"加载一个固定页面的 WebView + 进度条"，与 GetProfileScene 同属"被拦截的 WebView"一族。
 *
 * 拦截逻辑**不重复实现**：直接复用 GetProfileScene 已导出的
 *   planInterception(request) / intercept(request, executor, jar) / syncCookies(response, jar, url)
 * 与类型 WebRequestLike / HttpResponseLike / ProfileHttpExecutor / ProfileCookieJar / WebResponsePlan。
 * （当前全仓只有 GetProfileScene 一处实现、WebViewSignInScene 一处消费，本文件是第二个消费者；
 *   若再出现第三个消费者，再抽到 hippo/ui/web/ 公共层 —— 三次重复才抽。）
 *
 * Part 1（本批）：URL 加载、loaded 状态机、进度、初始化失败兜底。
 * Part 2 待补：ToolbarActivity 的菜单项、返回键与 WebView 的 canGoBack 交互。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GetProfileScene, WebRequestLike, ProfileCookieJar, ProfileHttpExecutor, WebResponsePlan
} from './scene/sign/GetProfileScene';

/** 进度视图（生产实现接 Progress 组件；上游 ProgressView） */
export interface ProgressViewLike {
  setVisibility(visible: boolean): void;
  setProgress(progress: number): void;
}

export class UnavailableProgressView implements ProgressViewLike {
  setVisibility(visible: boolean): void {}
  setProgress(progress: number): void {}
}

export class UConfigActivity {
  /** 上游私有字段的等价物 */
  private url: string = '';
  private loaded: boolean = false;
  private progress: ProgressViewLike = new UnavailableProgressView();
  private cookieJar: ProfileCookieJar | null = null;
  private executor: ProfileHttpExecutor | null = null;

  constructor(url: string) {
    this.url = url;
  }

  setProgressView(v: ProgressViewLike): void { this.progress = v; }
  setCookieJar(jar: ProfileCookieJar): void { this.cookieJar = jar; }
  setHttpExecutor(executor: ProfileHttpExecutor): void { this.executor = executor; }

  getUrl(): string { return this.url; }
  isLoaded(): boolean { return this.loaded; }

  /** 上游 onCreate 里的加载入口：进度可见、loaded 复位 */
  startLoad(): void {
    if (this.url.length === 0) {
      hilog.warn(0x0000, 'UConfigActivity', 'startLoad: url 为空；后果：页面不加载，停在空白页');
      return;
    }
    this.loaded = false;
    this.progress.setVisibility(true);
    this.progress.setProgress(0);
  }

  /**
   * WebView 的 shouldInterceptRequest 等价入口。
   * 完全委托给 GetProfileScene 的静态实现：返回 null 表示"交给 WebView 自己处理"。
   */
  onInterceptRequest(request: WebRequestLike): WebResponsePlan | null {
    if (this.executor === null || this.cookieJar === null) {
      // 上游未接线时的行为等价于"不拦截"，交回 WebView 默认网络栈
      hilog.info(0x0000, 'UConfigActivity',
        'executor/jar 未注入: url=%{public}s；后果：本请求走 WebView 默认网络栈（不带 App cookie）', request.url);
      return null;
    }
    return GetProfileScene.intercept(request, this.executor, this.cookieJar);
  }

  /** 上游 onProgressChanged：进度到 100 隐藏 */
  onProgressChanged(newProgress: number): void {
    this.progress.setProgress(newProgress);
    if (newProgress >= 100) {
      this.progress.setVisibility(false);
    }
  }

  /** 上游 onPageFinished：置 loaded，隐藏进度 */
  onPageFinished(): void {
    this.loaded = true;
    this.progress.setVisibility(false);
  }

  /**
   * 上游 onReceivedError / 初始化失败：日志 + 进度隐藏，loaded 保持 false。
   * 后果写明：页面停在错误态，用户只能返回。
   */
  onLoadError(description: string): void {
    this.loaded = false;
    this.progress.setVisibility(false);
    hilog.error(0x0000, 'UConfigActivity', 'WebView 加载失败: url=%{public}s err=%{public}s；后果：页面停在错误态，需返回重进',
      this.url, description);
  }
}
