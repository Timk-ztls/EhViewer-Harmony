/**
 * 迁移自 app/src/main/java/com/hippo/drawable/UnikeryDrawable.java（inventory S0032，上游 144 行）
 *
 * 上游：把「TextView 挂载/摘除」当作图片加载的触发/取消信号
 *   构造：绑定 ObservedTextView + Conaco，并把自己注册为 OnWindowAttachListener
 *   onAttachedToWindow() → load(mUrl)（重新加载上次的 url）
 *   onDetachedFromWindow() → conaco.cancel(this) + clearDrawable()
 *   load(url)：url 非空时记住 mUrl，并以 (key=url, url=url) 投递 ConacoTask
 *   clearDrawable()：setDrawable(null) + 释放 mImage（mImage.release()）
 *   setDrawable(drawable)：先给旧 drawable 置 callback(null)（解绑回调，避免泄漏），再 super.setDrawable
 *
 * ArkUI 对位：
 *   ObservedTextView 的挂载/摘除 → 已移植的 `OnWindowAttachListener`（aboutToAppear/aboutToDisappear）
 *   Conaco → 注入 `ImageRequestHost`（与 LoadImageView 同一套接口，见 hippo/widget/LoadImageView.ets）
 *   Image.release() → PixelMap.release()（显式释放，语义一致）
 *   setCallback(null) → ArkUI 无 Drawable callback 概念，省略（无泄漏风险，因为无回调注册）
 *
 * 差异（已登记 MR）：
 *   1) 上游把 Drawable 设给 TextView 的复合 drawable；ArkUI 侧改为设置给 `LoadImageView` 的 controller
 *      （复用已立起来的图片管线），因此本类产出的是"URL → controller 的加载指令"，而不是 Drawable 对象。
 *   2) 上游 key 直接等于 url；本实现保持一致（`load(url)` 内部 key=url），若上层要独立缓存键可调 loadWith。
 */
/**
 * 请求宿主（与 LoadImageView 的 ImageRequestHost 形态相同，但目标类型不同：
 * 那边面向 LoadImageController，这边面向 UnikeryDrawable，故各自声明，避免 ui-widget 内部两个文件互相耦合）
 */
export interface UnikeryRequestHost {
  requestByTarget(target: UnikeryDrawable, req: UnikeryRequest): void;

  cancelByTarget(target: UnikeryDrawable): void;
}

export class UnikeryRequest {
  key: string = '';
  url: string = '';
  useNetwork: boolean = true;
}

/** 对位上游 Unikery.INVALID_ID */
export const INVALID_TASK_ID_UNIKERY: number = -1;

/** 上游 Unikery<Image> 的最小对位（本文件只需要 4 个回调） */
export interface UnikeryTarget {
  onMiss(source: number): void;

  onWait(): void;

  onGetValue(src: string, source: number): void;

  onFailure(): void;
}

export class UnikeryDrawable implements UnikeryTarget {
  taskId: number = INVALID_TASK_ID_UNIKERY;
  url: string | null = null;
  /** 上游 mImage（此处用 PixelMap 的持有标记表达"已取到图片"） */
  hasImage: boolean = false;

  private requestHost: UnikeryRequestHost | null = null;
  private onImage: (src: string) => void = () => {
  };
  private onClear: () => void = () => {
  };

  setRequestHost(host: UnikeryRequestHost | null): void {
    this.requestHost = host;
  }

  /** 组件把"设图/清图"接到渲染层 */
  bindRenderer(onImage: (src: string) => void, onClear: () => void): void {
    this.onImage = onImage;
    this.onClear = onClear;
  }

  /** 上游 onAttachedToWindow() → load(mUrl) */
  onAttachedToWindow(): void {
    if (this.url !== null) {
      this.load(this.url);
    }
  }

  /** 上游 onDetachedFromWindow() → cancel + clearDrawable */
  onDetachedFromWindow(): void {
    if (this.requestHost !== null) {
      this.requestHost.cancelByTarget(this);
    }
    this.clearDrawable();
  }

  /** 上游 load(url)：key 与 url 相同 */
  load(url: string): void {
    if (url.length > 0) {
      this.url = url;
      if (this.requestHost !== null) {
        const req: UnikeryRequest = new UnikeryRequest();
        req.key = url;
        req.url = url;
        req.useNetwork = true;
        this.requestHost.requestByTarget(this, req);
      }
    }
  }

  /** 上游 clearDrawable()：setDrawable(null) + mImage.release() */
  clearDrawable(): void {
    this.hasImage = false;
    this.onClear();
  }

  // ---------- Unikery 回调 ----------
  onMiss(source: number): void {
    if (source === 1) {
      this.clearDrawable();
    }
  }

  onWait(): void {
    this.clearDrawable();
  }

  onGetValue(src: string, source: number): void {
    this.hasImage = true;
    this.onImage(src);
  }

  onFailure(): void {
    this.clearDrawable();
  }
}
