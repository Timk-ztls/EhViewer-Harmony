/**
 * 迁移自 app/src/main/java/com/hippo/widget/LoadImageView.java（inventory S0527，上游 414 行）
 *
 * ============================ C-8 契约（Lead 定稿，必须逐字满足） ============================
 *   export interface PreviewTarget {          // 声明在 net-parse: hippo/ehviewer/client/data/PreviewSet.ets
 *     setClip(left: number, top: number, width: number, height: number): void
 *     resetClip(): void
 *     load(key: string, url: string): void    // ← 第一参数是缓存键，第二才是 URL（与上游 view.load(key,url) 同序）
 *   }
 *
 * **必须知道的形状差异**：ArkUI 的 `@Component struct` 不能 implements 接口，因此
 * **实现 PreviewTarget 的是本文件的 `LoadImageController`（class）**，组件 `LoadImageView` 只负责渲染。
 * net-parse 侧持有的是 controller 引用（构造组件时传入），调用序列与上游完全一致：
 *   `this.controller.load(imageKey, imageUrl)`、`this.controller.setClip(l,t,w,h)`、`this.controller.resetClip()`
 * 这条已作为 C-8 的落地形状报给 Lead（契约文字不变，只是"实现者"从控件本体变成其 controller）。
 *
 * ============================ 上游行为逐条对位 ============================
 * 字段：mTaskId / mKey / mUrl / mDataContainer / mUseNetwork / mHardware /
 *       mOffsetX,mOffsetY,mClipWidth,mClipHeight（Integer.MIN_VALUE 表示"无裁剪"）/ mRetryType / mFailed /
 *       mLoadFromDrawable / secondTry / downloadInfo / mRequestId
 * 生命周期：
 *   onAttachedToWindow → 若 !mLoadFromDrawable：失败则 onFailure()；否则 taskId 无效时按缓存字段重发 load
 *   onDetachedFromWindow → 取消请求 + clearDrawable()
 * load(key,url,...)   → url/key 为 null 直接 return；置 mLoadFromDrawable=false、mFailed=false、clearRetry()，
 *                       记录字段后投递 ConacoTask（本实现改为注入 ImageRequestHost.request）
 * unload()            → cancel + 清空 key/url/dataContainer + clearDrawable()
 * onMiss(MEMORY)      → clearDrawable()
 * onWait()            → clearDrawable()
 * onGetValue(value,source) → 取 drawable；有裁剪则包 PreciselyClipDrawable；
 *                       若来源是 DISK/NETWORK 且可见 → TransitionDrawable 300ms 淡入；否则直接设置
 * onFailure()         → mFailed=true、清图、设置失败占位图（API>=26 用 image_failed_new，否则 image_failed）、
 *                       按 mRetryType 挂点击/长按重试；RETRY_TYPE_NONE 时清 key/url 并释放
 *
 * ArkUI 对位：
 *   setImageDrawable(d)            → @State imageSource + Image()
 *   PreciselyClipDrawable          → controller 保存 offset/clip 四值 → 组件用 .clip() + 偏移裁出子区域
 *   TransitionDrawable(300ms)      → 透明度 0→1 的 animateTo（Curve.Linear，与 TransitionDrawable 的线性一致）
 *   setOnClickListener/长按重试    → .onClick() / .gesture(LongPressGesture) 按 mRetryType 挂载
 *   Conaco/ConacoTask              → 注入 ImageRequestHost（core-runtime 的 conaco 尚未落地，接口注入避免编译互锁）
 *   image_failed / image_failed_new → 直接复用本模块 part-1 重绘产物（hippo/ui/drawable/image_failed*.ets）
 *
 * 无法等价（已登记 MR）：
 *   1) RETRY_TYPE_NONE 分支里"重新拉取画廊详情"那段耦合了 EhClient/EhApplication 全局状态（net-parse + core-runtime），
 *      本实现只保留"清 key/url 释放"部分，重试详情由 ui-scene 注入 `onRequestDetail` 回调。
 *   2) isShown()（是否可见）无同步查询 → 用 @State attached（aboutToAppear 置 true）近似。
 */
import { PreviewTarget } from '../ehviewer/client/data/PreviewSet';
import { ImageFailed } from '../ui/drawable/image_failed';
import { PreciselyClipDrawableView } from '../drawable/PreciselyClipDrawable';
import { ImageFailedNew } from '../ui/drawable/image_failed_new';

/** 上游 Unikery.INVALID_ID */
export const INVALID_TASK_ID: number = -1;

/** 上游 Conaco 的 source 常量（仅用到这三个） */
export class ImageSource {
  static readonly MEMORY: number = 1;
  static readonly DISK: number = 2;
  static readonly NETWORK: number = 3;
}

/** 一次图片请求（对位 ConacoTask.Builder 的可序列化数据） */
export class ImageRequest {
  key: string = '';
  url: string = '';
  useNetwork: boolean = true;
  hardware: boolean = false;
  /** 上游 DataContainer 的等价物：不透明句柄，由 storage-db 侧解释 */
  dataContainerId: string = '';
  /** 列表/网格中项索引（用于可见窗口优先调度，-1 表示未知） */
  listIndex: number = -1;
}

/** 请求宿主：由 core-runtime 的 conaco 实现；未落地前可用内存实现兜底 */
export interface ImageRequestHost {
  request(target: LoadImageController, req: ImageRequest): void;

  cancel(target: LoadImageController): void;
}

/** 宿主桥（具名类，ArkTS 禁止无类型对象字面量） */
export class ImageRequestHostBridge implements ImageRequestHost {
  private reqFn: (target: LoadImageController, req: ImageRequest) => void;
  private cancelFn: (target: LoadImageController) => void;

  constructor(reqFn: (target: LoadImageController, req: ImageRequest) => void,
              cancelFn: (target: LoadImageController) => void) {
    this.reqFn = reqFn;
    this.cancelFn = cancelFn;
  }

  request(target: LoadImageController, req: ImageRequest): void {
    this.reqFn(target, req);
  }

  cancel(target: LoadImageController): void {
    this.cancelFn(target);
  }
}

/** 组件向控制器回吐的渲染能力 */
export interface LoadImageHost {
  applyImage(src: string, fadeIn: boolean): void;

  applyFailureImage(useNew: boolean): void;

  clearImage(): void;
}

export class LoadImageHostBridge implements LoadImageHost {
  private imageFn: (src: string, fadeIn: boolean) => void;
  private failFn: (useNew: boolean) => void;
  private clearFn: () => void;

  constructor(imageFn: (src: string, fadeIn: boolean) => void,
              failFn: (useNew: boolean) => void,
              clearFn: () => void) {
    this.imageFn = imageFn;
    this.failFn = failFn;
    this.clearFn = clearFn;
  }

  applyImage(src: string, fadeIn: boolean): void {
    this.imageFn(src, fadeIn);
  }

  applyFailureImage(useNew: boolean): void {
    this.failFn(useNew);
  }

  clearImage(): void {
    this.clearFn();
  }
}

/**
 * LoadImageView 的状态与逻辑（**本类实现 C-8 的 PreviewTarget**）。
 */
export class LoadImageController implements PreviewTarget {
  static readonly RETRY_TYPE_NONE: number = 0;
  static readonly RETRY_TYPE_CLICK: number = 1;
  static readonly RETRY_TYPE_LONG_CLICK: number = 2;

  taskId: number = INVALID_TASK_ID;
  key: string | null = null;
  url: string | null = null;
  useNetwork: boolean = true;
  hardware: boolean = false;
  dataContainerId: string = '';
  listIndex: number = -1;
  offsetX: number = Number.MIN_VALUE;
  offsetY: number = Number.MIN_VALUE;
  clipWidth: number = Number.MIN_VALUE;
  clipHeight: number = Number.MIN_VALUE;
  retryType: number = LoadImageController.RETRY_TYPE_NONE;
  failed: boolean = false;
  loadFromDrawable: boolean = false;
  /** 已重试过一次（上游 secondTry） */
  secondTry: boolean = false;
  attached: boolean = false;
  /** true 表示 RequestHost 已在磁盘/解码阶段按 offset/clip 完成真裁切，视图无需二次 PreciselyClip */
  preCropped: boolean = false;

  private static sDefaultRequestHost: ImageRequestHost | null = null;

  private host: LoadImageHost | null = null;
  private requestHost: ImageRequestHost | null = null;
  private onRetry: (() => void) | null = null;
  private pendingSrc: string | null = null;
  private pendingSource: number = ImageSource.MEMORY;
  private delivered: boolean = false;

  static setDefaultRequestHost(requestHost: ImageRequestHost | null): void {
    LoadImageController.sDefaultRequestHost = requestHost;
  }

  static getDefaultRequestHost(): ImageRequestHost | null {
    return LoadImageController.sDefaultRequestHost;
  }

  private resolveRequestHost(): ImageRequestHost | null {
    return this.requestHost !== null ? this.requestHost : LoadImageController.sDefaultRequestHost;
  }

  attach(host: LoadImageHost): void {
    this.host = host;
    if (this.pendingSrc !== null && !this.failed) {
      const src: string = this.pendingSrc;
      const source: number = this.pendingSource;
      this.pendingSrc = null;
      const fadeIn: boolean = (source === ImageSource.DISK || source === ImageSource.NETWORK) && this.attached;
      host.applyImage(src, fadeIn);
    }
  }

  detach(): void {
    this.host = null;
  }

  setRequestHost(requestHost: ImageRequestHost): void {
    this.requestHost = requestHost;
  }

  /** 上游 RETRY_TYPE_NONE 分支的"重新拉详情"回调（由 ui-scene 注入） */
  setOnRetry(fn: (() => void) | null): void {
    this.onRetry = fn;
  }

  // ---------- PreviewTarget（C-8）----------
  setClip(left: number, top: number, width: number, height: number): void {
    this.offsetX = left;
    this.offsetY = top;
    this.clipWidth = width;
    this.clipHeight = height;
  }

  /** 是否设置了裁剪窗口（四值都不是 MIN_VALUE 哨兵） */
  hasClip(): boolean {
    return this.clipWidth !== Number.MIN_VALUE && this.clipHeight !== Number.MIN_VALUE
      && this.clipWidth > 0 && this.clipHeight > 0;
  }

  resetClip(): void {
    this.offsetX = Number.MIN_VALUE;
    this.offsetY = Number.MIN_VALUE;
    this.clipWidth = Number.MIN_VALUE;
    this.clipHeight = Number.MIN_VALUE;
    this.preCropped = false;
  }

  /** 第一参数 = 缓存键，第二 = URL（与上游 view.load(key, url) 同序） */
  load(key: string, url: string, listIndex: number = -1): void {
    this.loadWith(key, url, true, true, listIndex);
  }

  loadWith(key: string, url: string, useNetwork: boolean, hardware: boolean, listIndex: number = -1): void {
    if (url.length === 0 || key.length === 0) {
      return;
    }
    this.loadFromDrawable = false;
    this.failed = false;
    this.preCropped = false;
    this.pendingSrc = null;
    this.delivered = false;
    this.clearRetry();
    this.key = key;
    this.url = url;
    this.useNetwork = useNetwork;
    this.hardware = hardware;
    this.listIndex = listIndex;
    const rh: ImageRequestHost | null = this.resolveRequestHost();
    if (rh !== null) {
      const req: ImageRequest = new ImageRequest();
      req.key = key;
      req.url = url;
      req.useNetwork = useNetwork;
      req.hardware = hardware;
      req.dataContainerId = this.dataContainerId;
      req.listIndex = listIndex;
      rh.request(this, req);
    }
  }

  unload(): void {
    const rh: ImageRequestHost | null = this.resolveRequestHost();
    if (rh !== null) {
      rh.cancel(this);
    }
    this.key = null;
    this.url = null;
    this.dataContainerId = '';
    this.listIndex = -1;
    this.failed = false;
    this.preCropped = false;
    this.pendingSrc = null;
    this.delivered = false;
    this.clearDrawable();
  }

  /** 上游 onAttachedToWindow 的补齐逻辑 */
  onAttached(): void {
    this.attached = true;
    if (this.loadFromDrawable) {
      return;
    }
    if (this.failed) {
      this.onFailure();
    } else if (this.taskId === INVALID_TASK_ID && !this.delivered) {
      if (this.key !== null && this.url !== null) {
        this.loadWith(this.key, this.url, this.useNetwork, this.hardware);
      }
    }
  }

  /** 上游 onDetachedFromWindow */
  onDetached(): void {
    this.attached = false;
    this.failed = false;
    if (this.loadFromDrawable) {
      return;
    }
    const rh: ImageRequestHost | null = this.resolveRequestHost();
    if (rh !== null) {
      rh.cancel(this);
    }
    this.pendingSrc = null;
    this.delivered = false;
    this.clearDrawable();
  }

  /**
   * 上游 `onClick → load(mKey, mUrl, true)`：**真正重发请求**。
   * 缺陷修复（审计 D P1-b）：原实现的点击走 `onAttached()`，而 `onAttached()` 在 failed 时只调
   * `onFailure()`（重设失败图）⇒ 图片永远停在失败态，点多少次都一样，只能重进页面。
   * 返回 false 表示没有 key/url 可重发（此时调用方应保持失败态）。
   */
  retry(): boolean {
    const k: string | null = this.key;
    const u: string | null = this.url;
    if (k === null || u === null) {
      return false;
    }
    this.loadWith(k, u, this.useNetwork, this.hardware);
    return true;
  }

  /**
   * 上游在 `GalleryDetailCallback.onSuccess` 把 `secondTry` 置 true 后用新 thumb URL 重载。
   * 缺陷修复（审计 D P1-b）：该字段此前全仓从未被置位 ⇒ `onRetry` 是死路径 ⇒ 下载列表里的
   * 过期缩略图永远恢复不了。现在由宿主在拿到新 URL 时调用本方法。
   */
  markSecondTry(): void {
    this.secondTry = true;
  }

  setRetryType(retryType: number): void {
    if (this.retryType !== retryType) {
      this.retryType = retryType;
    }
  }

  // ---------- Unikery 回调 ----------
  onMiss(source: number): void {
    if (source === ImageSource.MEMORY) {
      this.clearDrawable();
    }
  }

  onWait(): void {
    this.clearDrawable();
  }

  /** 上游 onGetValue：mOffsetX != MIN_VALUE 且未预裁切时套 PreciselyClipDrawable；DISK/NETWORK 且可见时 300ms 淡入 */
  onGetValue(src: string, source: number): void {
    this.delivered = true;
    if (this.host !== null) {
      this.pendingSrc = null;
      const fadeIn: boolean = (source === ImageSource.DISK || source === ImageSource.NETWORK) && this.attached;
      this.host.applyImage(src, fadeIn);
    } else {
      this.pendingSrc = src;
      this.pendingSource = source;
    }
  }

  /** 上游 onFailure */
  onFailure(): void {
    this.failed = true;
    this.delivered = false;
    this.clearDrawable();
    // API>=26 用 image_failed_new，否则 image_failed（鸿蒙无 SDK 分支，统一用新版并保留注释）
    if (this.host !== null) {
      this.host.applyFailureImage(true);
    }
    if (this.retryType === LoadImageController.RETRY_TYPE_NONE && this.secondTry && this.onRetry !== null) {
      this.onRetry();
    }
    if (this.retryType === LoadImageController.RETRY_TYPE_NONE) {
      // Can't retry, so release
      this.key = null;
      this.url = null;
    }
  }

  /** 上游 clearRetry() */
  clearRetry(): void {
    // 点击/长按监听在 ArkUI 里由组件按 retryType 条件挂载，这里无需解绑
  }

  clearDrawable(): void {
    if (this.host !== null) {
      this.host.clearImage();
    }
  }
}

@Component
export struct LoadImageView {
  controller: LoadImageController = new LoadImageController();
  /** 固定宽高比（上游 extends FixedAspectImageView），0 表示不约束 */
  @Prop aspectRatioValue: number = 0;
  /** 缩放模式：CENTER_CROP → ImageFit.Cover，FIT_CENTER → ImageFit.Contain（FixedThumb 会按图片宽高比切换） */
  @Prop imageFit: ImageFit = ImageFit.CENTER;
  /** 图片加载完成回调（对位 onPreSetImageDrawable 里读 intrinsicWidth/Height 的时机） */
  onImageLoaded: (width: number, height: number) => void = () => {
  };
  @State imageSrc: string = '';
  /** 原图自然尺寸：由 onComplete 给出，供裁剪反算使用（上游 drawable.intrinsicWidth/Height） */
  @State naturalW: number = 0;
  @State naturalH: number = 0;
  @State failed: boolean = false;
  @State useNewFailure: boolean = true;
  @State imageAlpha: number = 1.0;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
    this.controller.attach(new LoadImageHostBridge(
      (src: string, fadeIn: boolean): void => {
        if (!this.alive) {
          return;
        }
        if (this.imageSrc !== src) {
          this.naturalW = 0;
          this.naturalH = 0;
        }
        this.imageSrc = src;
        this.failed = false;
        if (fadeIn) {
          this.imageAlpha = 0.0;
          this.getUIContext().animateTo({ duration: 300, curve: Curve.Linear }, () => {
            if (this.alive) {
              this.imageAlpha = 1.0;
            }
          });
        } else {
          this.imageAlpha = 1.0;
        }
      },
      (useNew: boolean): void => {
        if (!this.alive) {
          return;
        }
        this.failed = true;
        this.naturalW = 0;
        this.naturalH = 0;
        this.useNewFailure = useNew;
      },
      (): void => {
        if (!this.alive) {
          return;
        }
        this.imageSrc = '';
        this.naturalW = 0;
        this.naturalH = 0;
        this.failed = false;
      }
    ));
    this.controller.onAttached();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.controller.detach();
    this.controller.onDetached();
  }

  build() {
    Stack() {
      if (this.failed) {
        // 仅失败态挂载重试手势；正常态不抢占外层容器点击（如 GalleryDetailSceneView 的 PreviewTileView）
        Stack() {
          // 上游 failure 占位图：API>=26 用 image_failed_new，否则 image_failed
          if (this.useNewFailure) {
            ImageFailedNew({ iconSize: 48 })
          } else {
            ImageFailed({ iconSize: 48 })
          }
        }
        .width('100%')
        .height('100%')
        .onClick(() => {
          if (this.controller.failed && this.controller.retryType === LoadImageController.RETRY_TYPE_CLICK) {
            // 缺陷修复（P1-b）：必须真正重发请求，不能走 onAttached（那只会重设失败图）
            this.controller.retry();
          }
        })
        .gesture(
          LongPressGesture()
            .onAction(() => {
              if (this.controller.failed && this.controller.retryType === LoadImageController.RETRY_TYPE_LONG_CLICK) {
                // 缺陷修复（P1-b）：同 onClick
                this.controller.retry();
              }
            })
        )
      } else if (this.imageSrc.length > 0 && this.controller.hasClip()
        && !this.controller.preCropped && this.naturalW > 0 && this.naturalH > 0) {
        // 缺陷修复（P1-a）：把 setClip 的四个值真正接到渲染。
        // 数学复用已交付的 PreciselyClipDrawable（不写第二份实现）；
        // **本次只做视觉裁剪**，按需解码子区域（省内存）依赖 native-image 的 C-8 参数。
        PreciselyClipDrawableView({
          src: this.imageSrc,
          offsetX: this.controller.offsetX,
          offsetY: this.controller.offsetY,
          clipWidth: this.controller.clipWidth,
          clipHeight: this.controller.clipHeight,
          originWidth: this.naturalW,
          originHeight: this.naturalH
        })
          .opacity(this.imageAlpha)
      } else if (this.imageSrc.length > 0) {
        Image(this.imageSrc)
          .width('100%')
          .height('100%')
          .objectFit(this.imageFit)
          .onComplete((event) => {
            if (event !== undefined && event.width > 0 && event.height > 0) {
              this.naturalW = event.width;
              this.naturalH = event.height;
              this.onImageLoaded(event.width, event.height);
            }
          })
          .opacity(this.imageAlpha)
      }
    }
    .width('100%')
    .height('100%')
    .aspectRatio(this.aspectRatioValue > 0 ? this.aspectRatioValue : undefined)
  }
}
