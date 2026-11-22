/**
 * 迁移自 app/src/main/java/com/hippo/widget/LoadImageViewNew.java（inventory S0528，上游 329 行）
 *
 * ============================ 与 LoadImageView 的差异（先看清再读代码） ============================
 * 上游两个类是**同一套状态机**的两份实现，差别只在加载管线：
 *   | 能力 | LoadImageView | LoadImageViewNew |
 *   |---|---|---|
 *   | DataContainer（本地文件/压缩包数据源） | 有 | **无** |
 *   | hardware 位图标志 | 有 | **无** |
 *   | downloadInfo / secondTry（失败后重拉详情） | 有 | **无** |
 *   | 其余（retryType / clip / 淡入 / 失败占位 / attach-detach 重发） | 有 | 有（完全相同） |
 *
 * 鸿蒙侧没有两套加载器：解码路径统一由 native-image + `ImageRequestHost` 承担，
 * 因此本文件**组合**已实现的 `LoadImageController`（不复制 300 行状态机），只把 New 版缺失的
 * DataContainer / hardware / downloadInfo 三个入口显式"不提供"，并用注释标明这是上游 New 版的语义。
 * 这样 TileThumbNew / FixedThumbNew 等调用点的行为与上游一致，且不会出现两份实现漂移。
 *
 * C-8 契约：本文件的 `LoadImageControllerNew` 同样实现 `PreviewTarget`（load(key,url) 第一参数=缓存键）。
 */
import { ThemeTokens } from '../../common/theme/ThemeTokens';
import { LoadImageController, LoadImageHost, LoadImageHostBridge, ImageRequestHost } from './LoadImageView';
import { PreviewTarget } from '../ehviewer/client/data/PreviewSet';

export class LoadImageControllerNew implements PreviewTarget {
  static readonly RETRY_TYPE_NONE: number = 0;
  static readonly RETRY_TYPE_CLICK: number = 1;
  static readonly RETRY_TYPE_LONG_CLICK: number = 2;

  /** 组合而非继承：New 版的状态机与旧版逐字相同，差异仅在管线能力（见文件头表） */
  private inner: LoadImageController = new LoadImageController();

  // ---------- 上游公开字段/方法（New 版子集） ----------
  get taskId(): number {
    return this.inner.taskId;
  }

  set taskId(v: number) {
    this.inner.taskId = v;
  }

  get failed(): boolean {
    return this.inner.failed;
  }

  get retryType(): number {
    return this.inner.retryType;
  }

  attach(host: LoadImageHost): void {
    this.inner.attach(host);
  }

  detach(): void {
    this.inner.detach();
  }

  setRequestHost(requestHost: ImageRequestHost): void {
    this.inner.setRequestHost(requestHost);
  }

  setRetryType(retryType: number): void {
    this.inner.setRetryType(retryType);
  }

  // ---------- PreviewTarget（C-8）----------
  setClip(left: number, top: number, width: number, height: number): void {
    this.inner.setClip(left, top, width, height);
  }

  resetClip(): void {
    this.inner.resetClip();
  }

  /** 第一参数 = 缓存键，第二 = URL（与上游 New 版 load(key,url) 同序） */
  load(key: string, url: string): void {
    this.inner.load(key, url);
  }

  /** 上游 New 版独有：load() 无参重载（用上次的 key/url 重发，useNetwork 固定 true） */
  reload(): void {
    const k: string | null = this.inner.key;
    const u: string | null = this.inner.url;
    if (k !== null && u !== null) {
      this.inner.loadWith(k, u, true, false); // New 版无 hardware 概念，恒 false
    }
  }

  loadWith(key: string, url: string, useNetwork: boolean): void {
    this.inner.loadWith(key, url, useNetwork, false);
  }

  unload(): void {
    this.inner.unload();
  }

  onAttached(): void {
    this.inner.onAttached();
  }

  onDetached(): void {
    this.inner.onDetached();
  }

  onMiss(source: number): void {
    this.inner.onMiss(source);
  }

  onWait(): void {
    this.inner.onWait();
  }

  onGetValue(src: string, source: number): void {
    this.inner.onGetValue(src, source);
  }

  onFailure(): void {
    this.inner.onFailure();
  }

  clearDrawable(): void {
    this.inner.clearDrawable();
  }
}

/**
 * 渲染组件：与 LoadImageView 同构（上游两个类的绘制/淡入/失败占位完全相同）。
 * 差异仅在 controller 类型（New 版没有 DataContainer/hardware/downloadInfo 入口）。
 */
@Component
export struct LoadImageViewNew {
  controller: LoadImageControllerNew = new LoadImageControllerNew();
  @Prop aspectRatioValue: number = 0;
  @Prop imageFit: ImageFit = ImageFit.CENTER;
  @Prop failureIconSize: number = 48;
  @Prop failureTextColor: ResourceColor = '';
  onImageLoaded: (width: number, height: number) => void = () => {
  };

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State imageSrc: string = '';
  @State showFailure: boolean = false;
  @State imageAlpha: number = 1.0;

  private effectiveFailureColor(): ResourceColor {
    return this.failureTextColor !== '' ? this.failureTextColor : ThemeTokens.current().textSecondary;
  }

  aboutToAppear(): void {
    this.controller.attach(new LoadImageHostBridge(
      (src: string, fadeIn: boolean): void => {
        this.imageSrc = src;
        this.showFailure = false;
        if (fadeIn) {
          this.imageAlpha = 0.0;
          animateTo({ duration: 300, curve: Curve.Linear }, () => {
            this.imageAlpha = 1.0;
          });
        } else {
          this.imageAlpha = 1.0;
        }
      },
      (useNew: boolean): void => {
        this.showFailure = true;
      },
      (): void => {
        this.imageSrc = '';
        this.showFailure = false;
      }
    ));
    this.controller.onAttached();
  }

  aboutToDisappear(): void {
    this.controller.onDetached();
    this.controller.detach();
  }

  build() {
    Stack() {
      if (this.showFailure) {
        Text('!')
          .fontSize(this.failureIconSize)
          .fontColor(this.effectiveFailureColor())
      } else if (this.imageSrc.length > 0) {
        Image(this.imageSrc)
          .width('100%')
          .height('100%')
          .objectFit(this.imageFit)
          .opacity(this.imageAlpha)
          .onComplete((event) => {
            if (event !== undefined && event.width > 0 && event.height > 0) {
              this.onImageLoaded(event.width, event.height);
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    .aspectRatio(this.aspectRatioValue > 0 ? this.aspectRatioValue : undefined)
  }
}
