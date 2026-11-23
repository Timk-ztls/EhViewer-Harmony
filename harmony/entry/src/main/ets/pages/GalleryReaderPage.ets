/*
 * 交互式画廊阅读页（route: `pages/GalleryReaderPage`）：
 *   Stage C (Track P5) 主引擎切接为 `XComponent` + `GLRootViewController` + `GLES20Canvas` + `GalleryView`
 *   （支持 EH 在线画廊 / DIR 本地目录 / ARCHIVE 外部与本地 ZIP/7z 压缩包三分派，以及触摸/缩放/物理键/窗口属性）。
 *   当 Watchdog（1500ms）超时、EGL 后端不可用或连续 3 帧渲染失败时，自动安全回退到 ArkUI `Swiper`
 *   阅读器并保持页码、三源支持与缓存策略不变。
 */
import fs from '@ohos.file.fs';
import i18n from '@ohos.i18n';
import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeShadowOptions,
  ThemeTokens,
  ThemeTypography
} from '../common/theme/ThemeTokens';
import { AppConfig } from '../hippo/ehviewer/AppConfig';
import { EhApplication } from '../hippo/ehviewer/EhApplication';
import { GetText } from '../hippo/ehviewer/GetText';
import { Settings } from '../hippo/ehviewer/Settings';
import { PrivacySettingsRules } from '../hippo/ehviewer/ui/fragment/PrivacySettingsRules';
import { applyWindowPrivacyToWindow } from '../hippo/ui/ThemeSystemBar';
import { EhEngine, HttpCaller, PreviewSetResult } from '../hippo/ehviewer/client/EhEngine';
import { EhUrl } from '../hippo/ehviewer/client/EhUrl';
import { GalleryDetail } from '../hippo/ehviewer/client/data/GalleryDetail';
import { GalleryInfo } from '../hippo/ehviewer/client/data/GalleryInfo';
import { PreviewSet } from '../hippo/ehviewer/client/data/PreviewSet';
import { GalleryPageParserResult } from '../hippo/ehviewer/client/parser/GalleryPageParser';
import { GalleryPageApiParserResult } from '../hippo/ehviewer/client/parser/GalleryPageApiParser';
import { GalleryPageUrlParser, PageUrlResult } from '../hippo/ehviewer/client/parser/GalleryPageUrlParser';
import { ArchiveGalleryProvider } from '../hippo/ehviewer/gallery/ArchiveGalleryProvider';
import { DirGalleryProvider } from '../hippo/ehviewer/gallery/DirGalleryProvider';
import { EhGalleryProvider } from '../hippo/ehviewer/gallery/EhGalleryProvider';
import { GalleryProvider2 } from '../hippo/ehviewer/gallery/GalleryProvider2';
import { GalleryActivity, KeyAction, LayoutMode, ProviderKind } from '../hippo/ehviewer/ui/GalleryActivity';
import { GalleryHeader } from '../hippo/ehviewer/widget/GalleryHeader';
import { SeekBarPanel } from '../hippo/ehviewer/widget/SeekBarPanel';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VRefreshDarkX24 } from '../hippo/ui/drawable/v_refresh_dark_x24';
import { VSettingsDarkX24 } from '../hippo/ui/drawable/v_settings_dark_x24';
import { IcStartPlay24 } from '../hippo/ui/drawable/ic_start_play_24';
import { IcPauseCircle } from '../hippo/ui/drawable/ic_pause_circle';
import { DialogGalleryMenuLayout } from '../hippo/ui/layout/dialog_gallery_menu';
import { BatteryView } from '../hippo/widget/BatteryView';
import { HippoTextClock } from '../hippo/widget/TextClock';
import { FileOutputStreamPipe } from '../hippo/io/FileOutputStreamPipe';
import { GalleryProvider } from '../hippo/lib/glgallery/GalleryProvider';
import { GalleryView, GalleryViewBuilder, GalleryViewListener } from '../hippo/lib/glgallery/GalleryView';
import { SimpleAdapter } from '../hippo/lib/glgallery/SimpleAdapter';
import { GLErr } from '../hippo/lib/glview/native/GLNativeBridge';
import { MotionEvent } from '../hippo/lib/glview/util/MotionEvent';
import { GLRootView } from '../hippo/lib/glview/view/GLRootView';
import { GLRootViewController } from '../hippo/lib/glview/view/GLRootViewController';
import { ArkTouchEventLike, ArkTouchPoint, TouchEventBridge } from '../hippo/lib/glview/view/TouchEventBridge';
import { DownloadResult } from '../hippo/okhttp/ChunkedSinkWriter';
import { PageImageDownloaderImpl } from '../hippo/okhttp/PageImageDownloaderImpl';
import { OkHttpCallerAdapter } from '../hippo/AppWiring';
import { ByteSink } from '../hippo/streampipe/OutputStreamPipe';
import { UniFile } from '../hippo/unifile/UniFile';
import {
  FallbackReason,
  ProgressThrottle,
  ReaderEngineCoordinator,
  ReaderRouteRequest,
  RenderEngineMode,
  ZoomedEdgeTurn,
  computeSafeDownloadPercent,
  mapArkKeyCodeToGalleryKeyCode,
  resolveZoomedEdgeTurn
} from '../hippo/ui/reader/ReaderEngineCoordinator';
import {
  OnSpiderListener,
  PageRequestResult,
  SpiderQueen
} from '../hippo/ehviewer/spider/SpiderQueen';
import { Image as SpiderImage } from '../hippo/lib/image/Image';

const DOMAIN: number = 0x0000;
const TAG: string = 'GalleryReaderPage';

class PageLoadStatus {
  static readonly IDLE: number = 0;
  static readonly LOADING: number = 1;
  static readonly READY: number = 2;
  static readonly ERROR: number = 3;
}

class ArkUiSpiderListener implements OnSpiderListener {
  private readonly onGetPagesCb: (pages: number) => void;
  private readonly onGet509Cb: (index: number) => void;
  private readonly onPageDownloadCb: (index: number, contentLength: number, receivedSize: number, bytesRead: number) => void;
  private readonly onPageSuccessCb: (index: number, finished: number, downloaded: number, total: number) => void;
  private readonly onPageFailureCb: (index: number, error: string, finished: number, downloaded: number, total: number) => void;
  private readonly onFinishCb: (finished: number, downloaded: number, total: number) => void;

  constructor(
    onGetPagesCb: (pages: number) => void,
    onGet509Cb: (index: number) => void,
    onPageDownloadCb: (index: number, contentLength: number, receivedSize: number, bytesRead: number) => void,
    onPageSuccessCb: (index: number, finished: number, downloaded: number, total: number) => void,
    onPageFailureCb: (index: number, error: string, finished: number, downloaded: number, total: number) => void,
    onFinishCb: (finished: number, downloaded: number, total: number) => void
  ) {
    this.onGetPagesCb = onGetPagesCb;
    this.onGet509Cb = onGet509Cb;
    this.onPageDownloadCb = onPageDownloadCb;
    this.onPageSuccessCb = onPageSuccessCb;
    this.onPageFailureCb = onPageFailureCb;
    this.onFinishCb = onFinishCb;
  }

  onGetPages(pages: number): void {
    this.onGetPagesCb(pages);
  }

  onGet509(index: number): void {
    this.onGet509Cb(index);
  }

  onPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void {
    this.onPageDownloadCb(index, contentLength, receivedSize, bytesRead);
  }

  onPageSuccess(index: number, finished: number, downloaded: number, total: number): void {
    this.onPageSuccessCb(index, finished, downloaded, total);
  }

  onPageFailure(index: number, error: string, finished: number, downloaded: number, total: number): void {
    this.onPageFailureCb(index, error, finished, downloaded, total);
  }

  onFinish(finished: number, downloaded: number, total: number): void {
    this.onFinishCb(finished, downloaded, total);
  }

  onGetImageSuccess(_index: number, _image: SpiderImage): void {
  }

  onGetImageFailure(_index: number, _error: string): void {
  }
}

@Observed
class ReaderPageState {
  readonly index: number;
  status: number = PageLoadStatus.IDLE;
  localPath: string = '';
  errorMessage: string = '';
  progress: number = -1;
  aspectRatio: number = 0;

  constructor(index: number) {
    this.index = index;
  }
}

class ReaderPageDataSource implements IDataSource {
  private items: ReaderPageState[] = [];
  private listeners: DataChangeListener[] = [];

  setTotalPages(count: number): void {
    const safeCount: number = count > 0 ? Math.trunc(count) : 0;
    const next: ReaderPageState[] = [];
    for (let i = 0; i < safeCount; i++) {
      if (i < this.items.length) {
        next.push(this.items[i]);
      } else {
        next.push(new ReaderPageState(i));
      }
    }
    this.items = next;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  getPageState(index: number): ReaderPageState | null {
    if (index < 0 || index >= this.items.length) {
      return null;
    }
    return this.items[index];
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ReaderPageState {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }
}

class ReaderSimpleAdapter extends SimpleAdapter {
  private readonly onDataUpdated: (size: number, err: string | null) => void;

  constructor(
    glRootView: GLRootView,
    provider: GalleryProvider,
    onDataUpdated: (size: number, err: string | null) => void
  ) {
    super(glRootView, provider);
    this.onDataUpdated = onDataUpdated;
  }

  onDataChanged(): void {
    super.onDataChanged();
    this.onDataUpdated(this.size(), this.getError());
  }
}

class ReaderGalleryViewListener implements GalleryViewListener {
  private readonly provider: GalleryProvider2;
  private readonly onIndexChanged: (index: number) => void;
  private readonly onShowControls: () => void;
  private readonly onToggleControls: () => void;
  private readonly onHideControls: () => void;

  constructor(
    provider: GalleryProvider2,
    onIndexChanged: (index: number) => void,
    onShowControls: () => void,
    onToggleControls: () => void,
    onHideControls: () => void
  ) {
    this.provider = provider;
    this.onIndexChanged = onIndexChanged;
    this.onShowControls = onShowControls;
    this.onToggleControls = onToggleControls;
    this.onHideControls = onHideControls;
  }

  onUpdateCurrentIndex(index: number): void {
    this.onIndexChanged(index);
  }

  onTapSliderArea(): void {
    this.onShowControls();
  }

  onTapMenuArea(): void {
    this.onToggleControls();
  }

  onTapErrorText(index: number): void {
    this.provider.forceRequest(index);
  }

  onLongPressPage(index: number): void {
    hilog.info(DOMAIN, TAG, 'long press page %{public}d', index);
  }

  onAutoTransferDone(): void {
    this.onHideControls();
  }
}

class TouchPointPayload implements ArkTouchPoint {
  id: number;
  x: number;
  y: number;

  constructor(id: number, x: number, y: number) {
    this.id = id;
    this.x = x;
    this.y = y;
  }
}

class TouchEventPayload implements ArkTouchEventLike {
  type: number;
  timestamp: number;
  touches: ArkTouchPoint[];
  changedTouches: ArkTouchPoint[];

  constructor(type: number, timestamp: number, touches: ArkTouchPoint[], changedTouches: ArkTouchPoint[]) {
    this.type = type;
    this.timestamp = timestamp;
    this.touches = touches;
    this.changedTouches = changedTouches;
  }
}

@Component
struct ReaderSlideView {
  @ObjectLink pageState: ReaderPageState;
  @Prop fitCover: boolean = false;
  @Prop @Watch('onExternalZoomChanged') zoomMultiplier: number = 1.0;
  @Prop @Watch('onZoomResetSeqChanged') zoomResetSeq: number = 0;
  @Prop primaryColor: ResourceColor = ThemeTokens.LIGHT.colorPrimary;
  @Prop errorColor: ResourceColor = ThemeTokens.LIGHT.errorColor;
  @Prop progressTrackColor: ResourceColor = ThemeTokens.DARK.readerControlBg;
  onRetry: () => void = (): void => {};
  onToggleControls: () => void = (): void => {};
  onTapLeft: () => void = (): void => {};
  onTapRight: () => void = (): void => {};
  onZoomStateChange: (zoomed: boolean) => void = (): void => {};

  @State scaleValue: number = 1.0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State slideWidth: number = 0;
  @State slideHeight: number = 0;
  private pinchStartScale: number = 1.0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private panStartedZoomed: boolean = false;
  private lastPinchAtMs: number = 0;
  private pendingCenterTapTimer: number = -1;
  private lastCenterTapMs: number = 0;

  private clearPendingCenterTap(): void {
    if (this.pendingCenterTapTimer >= 0) {
      clearTimeout(this.pendingCenterTapTimer);
      this.pendingCenterTapTimer = -1;
    }
  }

  aboutToDisappear(): void {
    this.clearPendingCenterTap();
  }

  private onExternalZoomChanged(): void {
    this.clearPendingCenterTap();
    const target: number = this.zoomMultiplier > 1.01 ? this.zoomMultiplier : 1.0;
    this.scaleValue = target;
    if (target <= 1.01) {
      this.offsetX = 0;
      this.offsetY = 0;
    } else {
      this.clampOffsets();
    }
    this.onZoomStateChange(this.scaleValue > 1.01);
  }

  private onZoomResetSeqChanged(): void {
    this.clearPendingCenterTap();
    this.lastCenterTapMs = 0;
    this.resetTransform(false);
  }

  private resetTransform(animated: boolean): void {
    this.clearPendingCenterTap();
    const apply = (): void => {
      this.scaleValue = 1.0;
      this.offsetX = 0;
      this.offsetY = 0;
    };
    if (animated) {
      this.getUIContext().animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, apply);
    } else {
      apply();
    }
    this.onZoomStateChange(false);
  }

  private clampOffsetX(raw: number): number {
    const maxX: number = this.slideWidth > 0 ? Math.max(0, (this.scaleValue - 1) * this.slideWidth / 2) : 0;
    return Math.max(-maxX, Math.min(maxX, raw));
  }

  private clampOffsetY(raw: number): number {
    const maxY: number = this.slideHeight > 0 ? Math.max(0, (this.scaleValue - 1) * this.slideHeight / 2) : 0;
    return Math.max(-maxY, Math.min(maxY, raw));
  }

  private clampOffsets(): void {
    this.offsetX = this.clampOffsetX(this.offsetX);
    this.offsetY = this.clampOffsetY(this.offsetY);
  }

  private toggleDoubleTapZoom(): void {
    if (this.scaleValue > 1.05) {
      this.resetTransform(true);
    } else {
      this.getUIContext().animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
        this.scaleValue = 2.0;
        this.offsetX = 0;
        this.offsetY = 0;
      });
      this.onZoomStateChange(true);
    }
  }

  private handleTapAtX(x: number): void {
    if (this.scaleValue <= 1.01 && this.slideWidth > 0 && x >= 0) {
      if (x < this.slideWidth / 3) {
        this.clearPendingCenterTap();
        this.lastCenterTapMs = 0;
        this.onTapLeft();
        return;
      }
      if (x > this.slideWidth * 2 / 3) {
        this.clearPendingCenterTap();
        this.lastCenterTapMs = 0;
        this.onTapRight();
        return;
      }
    }
    const now: number = Date.now();
    if (this.pendingCenterTapTimer >= 0 && (now - this.lastCenterTapMs) <= 220) {
      this.clearPendingCenterTap();
      this.lastCenterTapMs = 0;
      if (this.pageState.status === PageLoadStatus.READY) {
        this.toggleDoubleTapZoom();
      }
      return;
    }
    this.clearPendingCenterTap();
    this.lastCenterTapMs = now;
    this.pendingCenterTapTimer = setTimeout((): void => {
      this.pendingCenterTapTimer = -1;
      this.onToggleControls();
    }, 200) as number;
  }

  private resolveImageSrc(pathOrUri: string): string {
    if (pathOrUri.startsWith('file://') ||
      pathOrUri.startsWith('datashare://') ||
      pathOrUri.startsWith('content://')) {
      return pathOrUri;
    }
    return 'file://' + pathOrUri;
  }

  build() {
    Stack() {
      if (this.pageState.status === PageLoadStatus.READY && this.pageState.localPath.length > 0) {
        Stack() {
          Image(this.resolveImageSrc(this.pageState.localPath))
            .width('100%')
            .height('100%')
            .objectFit(this.fitCover ? ImageFit.Cover : ImageFit.Contain)
            .autoResize(this.scaleValue <= 1.01)
            .interpolation(ImageInterpolation.Medium)
            .draggable(false)
            .scale({ x: this.scaleValue, y: this.scaleValue })
            .translate({ x: this.offsetX, y: this.offsetY })
            .onComplete((event): void => {
              if (event !== undefined && event.width > 0 && event.height > 0 && this.pageState.aspectRatio <= 0) {
                this.pageState.aspectRatio = event.width / event.height;
              }
            })
            .onError((error): void => {
              const msg: string = error !== undefined && error.message !== undefined && error.message.length > 0
                ? error.message : GetText.getString('error_decoding_failed');
              hilog.warn(DOMAIN, TAG, '[ArkUIReader] Image decode error page=%{public}d src=%{public}s msg=%{public}s',
                this.pageState.index, this.pageState.localPath, msg);
              this.pageState.errorMessage = msg;
              this.pageState.status = PageLoadStatus.ERROR;
            })
        }
        .width('100%')
        .height('100%')
        .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
          // 未放大时放行全部单指拖动给外层 Swiper，实现 1:1 跟手左右滑动翻页
          if (gestureInfo.type === GestureControl.GestureType.PAN_GESTURE &&
            this.scaleValue <= 1.01) {
            return GestureJudgeResult.REJECT;
          }
          return GestureJudgeResult.CONTINUE;
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart((): void => {
                this.clearPendingCenterTap();
                this.pinchStartScale = this.scaleValue;
                this.lastPinchAtMs = Date.now();
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.lastPinchAtMs = Date.now();
                const next: number = Math.max(1.0, Math.min(4.0, this.pinchStartScale * event.scale));
                this.scaleValue = next;
                this.clampOffsets();
              })
              .onActionEnd((): void => {
                this.lastPinchAtMs = Date.now();
                if (this.scaleValue <= 1.05) {
                  this.resetTransform(true);
                } else {
                  this.onZoomStateChange(true);
                }
              }),
            PanGesture({ fingers: 1, distance: 4 })
              .onActionStart((): void => {
                this.clearPendingCenterTap();
                this.panStartX = this.offsetX;
                this.panStartY = this.offsetY;
                this.panStartedZoomed = this.scaleValue > 1.01;
              })
              .onActionUpdate((event: GestureEvent): void => {
                if (this.panStartedZoomed || this.scaleValue > 1.01) {
                  this.offsetX = this.clampOffsetX(this.panStartX + event.offsetX);
                  this.offsetY = this.clampOffsetY(this.panStartY + event.offsetY);
                }
              })
              .onActionEnd((event: GestureEvent): void => {
                if (this.panStartedZoomed && this.scaleValue > 1.01) {
                  const maxX: number = this.slideWidth > 0
                    ? Math.max(0, (this.scaleValue - 1) * this.slideWidth / 2)
                    : 0;
                  const edgeTurn: ZoomedEdgeTurn = resolveZoomedEdgeTurn(
                    this.panStartX, maxX, event.offsetX, event.offsetY, Date.now() - this.lastPinchAtMs
                  );
                  if (edgeTurn === 'right') {
                    this.clearPendingCenterTap();
                    this.resetTransform(false);
                    this.onTapRight();
                  } else if (edgeTurn === 'left') {
                    this.clearPendingCenterTap();
                    this.resetTransform(false);
                    this.onTapLeft();
                  }
                }
              }),
            TapGesture({ count: 1 })
              .onAction((event: GestureEvent): void => {
                if (event.fingerList.length > 0) {
                  this.handleTapAtX(event.fingerList[0].localX);
                } else {
                  this.onToggleControls();
                }
              })
          )
        )
      } else if (this.pageState.status === PageLoadStatus.ERROR) {
        Column({ space: 12 }) {
          Text(String(this.pageState.index + 1))
            .fontSize(56)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF666666')
          Text($r('app.string.load_failed'))
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .fontColor(this.errorColor)
            .fontWeight(FontWeight.Bold)
          if (this.pageState.errorMessage.length > 0) {
            Text(this.pageState.errorMessage)
              .fontSize(12)
              .fontColor('#FFDDDDDD')
              .textAlign(TextAlign.Center)
          }
          Button($r('app.string.retry'), { type: ButtonType.Normal })
            .height(40)
            .padding({ left: 20, right: 20 })
            .borderRadius(ThemeRadius.BUTTON)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.primaryColor)
            .fontColor(Color.White)
            .onClick(() => { this.onRetry(); })
        }
        .width('100%')
        .height('100%')
        .padding(24)
        .justifyContent(FlexAlign.Center)
        .onClick((event: ClickEvent) => { this.handleTapAtX(event.x); })
      } else {
        Column({ space: 16 }) {
          Text(String(this.pageState.index + 1))
            .fontSize(56)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF666666')
          if (this.pageState.progress >= 0 && this.pageState.progress <= 100) {
            Progress({ value: this.pageState.progress, total: 100, type: ProgressType.Ring })
              .width(56)
              .height(56)
              .color(this.primaryColor)
              .backgroundColor(this.progressTrackColor)
              .style({ strokeWidth: 4 })
            Text(`${this.pageState.progress}%`)
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor('#FFCCCCCC')
          } else {
            LoadingProgress()
              .width(56)
              .height(56)
              .color(this.primaryColor)
            Text($r('app.string.loading'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor('#FFCCCCCC')
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick((event: ClickEvent) => { this.handleTapAtX(event.x); })
      }
    }
    .width('100%')
    .height('100%')
    .direction(Direction.Ltr)
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w: number = typeof newArea.width === 'number' ? newArea.width : Number(newArea.width);
      const h: number = typeof newArea.height === 'number' ? newArea.height : Number(newArea.height);
      if (w > 0) {
        this.slideWidth = w;
      }
      if (h > 0) {
        this.slideHeight = h;
      }
      this.clampOffsets();
    })
  }
}

@Component
struct ReaderWebtoonPageView {
  @ObjectLink pageState: ReaderPageState;
  @Prop primaryColor: ResourceColor = ThemeTokens.LIGHT.colorPrimary;
  @Prop errorColor: ResourceColor = ThemeTokens.LIGHT.errorColor;
  @Prop progressTrackColor: ResourceColor = ThemeTokens.DARK.readerControlBg;
  onRetry: () => void = (): void => {};
  onToggleControls: () => void = (): void => {};
  @State viewWidth: number = 0;

  private resolveImageSrc(pathOrUri: string): string {
    if (pathOrUri.startsWith('file://') ||
      pathOrUri.startsWith('datashare://') ||
      pathOrUri.startsWith('content://')) {
      return pathOrUri;
    }
    return 'file://' + pathOrUri;
  }

  build() {
    Column() {
      if (this.pageState.status === PageLoadStatus.READY && this.pageState.localPath.length > 0) {
        Image(this.resolveImageSrc(this.pageState.localPath))
          .width('100%')
          .aspectRatio(this.pageState.aspectRatio > 0 ? this.pageState.aspectRatio : 0.72)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .onComplete((event): void => {
            if (event !== undefined && event.width > 0 && event.height > 0) {
              const ratio: number = event.width / event.height;
              if (ratio > 0 && Math.abs(ratio - this.pageState.aspectRatio) > 0.005) {
                this.pageState.aspectRatio = ratio;
              }
            }
          })
          .onError((error): void => {
            const msg: string = error !== undefined && error.message !== undefined && error.message.length > 0
              ? error.message : GetText.getString('error_decoding_failed');
            this.pageState.errorMessage = msg;
            this.pageState.status = PageLoadStatus.ERROR;
          })
          .onClick((event: ClickEvent): void => {
            if (this.viewWidth <= 0 || (event.x >= this.viewWidth * 0.15 && event.x <= this.viewWidth * 0.85)) {
              this.onToggleControls();
            }
          })
      } else if (this.pageState.status === PageLoadStatus.ERROR) {
        Column({ space: 12 }) {
          Text(String(this.pageState.index + 1))
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF666666')
          Text($r('app.string.load_failed'))
            .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
            .fontColor(this.errorColor)
            .fontWeight(FontWeight.Bold)
          if (this.pageState.errorMessage.length > 0) {
            Text(this.pageState.errorMessage)
              .fontSize(12)
              .fontColor('#FFDDDDDD')
              .textAlign(TextAlign.Center)
          }
          Button($r('app.string.retry'), { type: ButtonType.Normal })
            .height(40)
            .padding({ left: 20, right: 20 })
            .borderRadius(ThemeRadius.BUTTON)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(this.primaryColor)
            .fontColor(Color.White)
            .onClick((): void => { this.onRetry(); })
        }
        .width('100%')
        .height(420)
        .padding(24)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => { this.onToggleControls(); })
      } else {
        Column({ space: 14 }) {
          Text(String(this.pageState.index + 1))
            .fontSize(44)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FF666666')
          if (this.pageState.progress >= 0 && this.pageState.progress <= 100) {
            Progress({ value: this.pageState.progress, total: 100, type: ProgressType.Ring })
              .width(48)
              .height(48)
              .color(this.primaryColor)
              .backgroundColor(this.progressTrackColor)
              .style({ strokeWidth: 4 })
            Text(`${this.pageState.progress}%`)
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor('#FFCCCCCC')
          } else {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.primaryColor)
            Text($r('app.string.loading'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor('#FFCCCCCC')
          }
        }
        .width('100%')
        .height(420)
        .justifyContent(FlexAlign.Center)
        .onClick((): void => { this.onToggleControls(); })
      }
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const w: number = typeof newArea.width === 'number' ? newArea.width : Number(newArea.width);
      if (w > 0) {
        this.viewWidth = w;
      }
    })
  }
}

@Entry
@Component
struct GalleryReaderPage {
  private static nextSessionSeq: number = 0;

  @State gid: number = 0;
  @State token: string = '';
  @State title: string = '';
  @State apiUrl: string = '';
  @State currentPage: number = 0;
  @State totalPages: number = 0;
  @State initialSwiperIndex: number = 0;
  @State initializing: boolean = true;
  @State initError: string = '';
  @State controlsVisible: boolean = false;
  @State settingsDialogOpen: boolean = false;
  @State fitCover: boolean = false;
  @State zoomed: boolean = false;
  @State currentPageZoomed: boolean = false;
  @State zoomResetSeq: number = 0;
  @State webtoonScale: number = 1.0;
  @State engineMode: RenderEngineMode = RenderEngineMode.ARKUI_PRIMARY;

  // Theme & Reading Settings states (synced with Settings)
  @State themeId: number = ThemeMode.LIGHT;
  @State screenRotation: number = Settings.DEFAULT_SCREEN_ROTATION;
  @State readingDirection: number = Settings.DEFAULT_READING_DIRECTION;
  @State pageScaling: number = Settings.DEFAULT_PAGE_SCALING;
  @State startPosition: number = Settings.DEFAULT_START_POSITION;
  @State startTransferTime: number = Settings.DEFAULT_START_TRANSFER_TIME;
  @State keepScreenOn: boolean = Settings.DEFAULT_KEEP_SCREEN_ON;
  @State showClock: boolean = Settings.DEFAULT_SHOW_CLOCK;
  @State showProgress: boolean = Settings.DEFAULT_SHOW_PROGRESS;
  @State showBattery: boolean = Settings.DEFAULT_SHOW_BATTERY;
  @State showPageInterval: boolean = Settings.DEFAULT_SHOW_PAGE_INTERVAL;
  @State pageTurnAnimation: boolean = Settings.DEFAULT_PAGE_TURN_ANIMATION;
  @State volumePage: boolean = Settings.DEFAULT_VOLUME_PAGE;
  @State reverseVolumePage: boolean = Settings.DEFAULT_REVERSE_VOLUME_PAGE;
  @State readingFullscreen: boolean = Settings.VALUE_READING_FULLSCREEN;
  @State customScreenLightness: boolean = Settings.DEFAULT_CUSTOM_SCREEN_LIGHTNESS;
  @State screenLightness: number = Settings.DEFAULT_SCREEN_LIGHTNESS;
  @State autoTransferring: boolean = false;
  @State is24HourClock: boolean = true;
  @State cutoutTopVp: number = 0;
  @State cutoutLeftVp: number = 0;
  @State cutoutRightVp: number = 0;
  @State bottomSafeVp: number = 0;

  private readonly headerShadow: ShadowOptions = new ThemeShadowOptions(2, '#CC000000', 0, 0);
  private autoTransferTimerId: number = -1;
  private startPageSaveTimer: number = -1;
  private pendingStartPage: number = -1;

  private providerKind: ProviderKind = ProviderKind.NONE;
  private dirFilename: string | null = null;
  private archiveUri: string | null = null;
  private readonly archiveSessionId: number = ++GalleryReaderPage.nextSessionSeq;

  private readonly coordinator: ReaderEngineCoordinator = new ReaderEngineCoordinator();
  private readonly touchBridge: TouchEventBridge = new TouchEventBridge();
  private xcController: XComponentController = new XComponentController();
  private glController: GLRootViewController | null = null;
  private galleryView: GalleryView | null = null;
  private simpleAdapter: ReaderSimpleAdapter | null = null;
  private activeProvider: GalleryProvider2 | null = null;
  private providerStarted: boolean = false;
  private watchdogTimerId: number = -1;
  private glRetryTimerIds: number[] = [];
  private lastSurfaceWidthPx: number = 0;
  private lastSurfaceHeightPx: number = 0;
  private vpToPxRatio: number = 3.0;

  private swiperController: SwiperController = new SwiperController();
  private lastSwiperSwipeMs: number = 0;
  private readonly webtoonScroller: Scroller = new Scroller();
  private webtoonPinchStart: number = 1.0;
  private dataSource: ReaderPageDataSource = new ReaderPageDataSource();
  private spiderQueen: SpiderQueen | null = null;
  private spiderListener: OnSpiderListener | null = null;
  private spiderReady: boolean = false;
  private destroyed: boolean = false;
  private showKey: string = '';
  private perPage: number = 0;

  private readonly pageUrlCache: Map<number, string> = new Map<number, string>();
  private readonly pTokenCache: Map<number, string> = new Map<number, string>();
  private readonly previewSetCache: Map<number, PreviewSet> = new Map<number, PreviewSet>();
  private readonly inFlightPreviewPages: Map<number, Promise<void>> = new Map<number, Promise<void>>();
  private readonly inFlightPages: Map<number, Promise<void>> = new Map<number, Promise<void>>();

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  private readerStatusColor(): string {
    const readerTheme: number = this.themeId === ThemeMode.BLACK ? ThemeMode.BLACK : ThemeMode.DARK;
    return ThemeTokens.of(readerTheme).textSecondary;
  }

  private syncReaderSettingsFromPrefs(): void {
    this.themeId = ThemeTokens.getThemeId();
    const attached: boolean = Settings.isAttached();
    if (!attached) {
      return;
    }
    this.screenRotation = Settings.getScreenRotation();
    this.readingDirection = Settings.getReadingDirection();
    this.pageScaling = Settings.getPageScaling();
    this.fitCover = this.pageScaling === GalleryView.SCALE_FIT_WIDTH;
    this.startPosition = Settings.getStartPosition();
    this.startTransferTime = Settings.getStartTransferTime();
    this.keepScreenOn = Settings.getKeepScreenOn();
    this.showClock = Settings.getShowClock();
    this.showProgress = Settings.getShowProgress();
    this.showBattery = Settings.getShowBattery();
    this.showPageInterval = Settings.getShowPageInterval();
    this.pageTurnAnimation = Settings.getPageTurnAnimation();
    this.volumePage = Settings.getVolumePage();
    this.reverseVolumePage = Settings.getReverseVolumePage();
    this.readingFullscreen = Settings.getReadingFullscreen();
    this.customScreenLightness = Settings.getCustomScreenLightness();
    this.screenLightness = Settings.getScreenLightness();
  }

  private refreshClockFormat(): void {
    try {
      this.is24HourClock = i18n.System.is24HourClock();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'query is24HourClock failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private refreshWindowAvoidAreas(win: window.Window): void {
    try {
      const uiCtx = this.getUIContext();
      const cutout = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const sys = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topPx: number = Math.max(cutout.topRect.height, this.readingFullscreen ? 0 : sys.topRect.height);
      const bottomPx: number = Math.max(nav.bottomRect.height, sys.bottomRect.height);
      this.cutoutTopVp = topPx > 0 ? Math.round(uiCtx.px2vp(topPx)) : 0;
      this.cutoutLeftVp = cutout.leftRect.width > 0 ? Math.round(uiCtx.px2vp(cutout.leftRect.width)) : 0;
      this.cutoutRightVp = cutout.rightRect.width > 0 ? Math.round(uiCtx.px2vp(cutout.rightRect.width)) : 0;
      this.bottomSafeVp = bottomPx > 0 ? Math.round(uiCtx.px2vp(bottomPx)) : 0;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getWindowAvoidArea failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private toWindowOrientation(rotationSetting: number): window.Orientation {
    switch (rotationSetting) {
      case 1:
        return window.Orientation.PORTRAIT;
      case 2:
        return window.Orientation.LANDSCAPE;
      case 3:
        return window.Orientation.AUTO_ROTATION;
      case 0:
      default:
        return window.Orientation.UNSPECIFIED;
    }
  }

  private computeLightnessMaskColor(): string {
    if (!this.customScreenLightness || this.screenLightness > 100) {
      return '#00000000';
    }
    const clamped: number = Math.max(0, Math.min(100, this.screenLightness));
    const alpha: number = Math.round(0xDE * (1 - clamped / 100.0));
    const hex: string = alpha.toString(16).toUpperCase().padStart(2, '0');
    return `#${hex}000000`;
  }

  private isArkUiMode(): boolean {
    return this.engineMode === RenderEngineMode.ARKUI_PRIMARY
      || this.engineMode === RenderEngineMode.SWIPER_FALLBACK;
  }

  aboutToAppear(): void {
    this.destroyed = false;
    this.updateDensityRatio();
    this.syncReaderSettingsFromPrefs();
    this.refreshClockFormat();
    const req: ReaderRouteRequest = this.readRouterParams();
    this.applyWindowReadingAttributes(true);

    if (req.providerPlan.kind === ProviderKind.NONE) {
      this.initializing = false;
      const err: string = GetText.getString('error_reading_failed');
      this.initError = err.length > 0 ? err : 'Invalid gallery source parameters';
      return;
    }

    const useExperimentalGl: boolean = Settings.isAttached() && Settings.getExperimentalGlReader();
    if (!useExperimentalGl) {
      this.coordinator.useArkUiPrimary(this.currentPage, this.totalPages);
      this.engineMode = RenderEngineMode.ARKUI_PRIMARY;
      this.initError = '';
      if (req.providerPlan.kind === ProviderKind.EH) {
        this.bootstrapEhArkUi(req);
      } else {
        this.activeProvider = this.buildProvider(req);
        if (this.activeProvider === null) {
          this.initializing = false;
          const err: string = GetText.getString('error_reading_failed');
          this.initError = err.length > 0 ? err : 'Failed to open gallery source';
          return;
        }
        if (req.providerPlan.kind === ProviderKind.ARCHIVE) {
          void this.bootstrapArchiveSwiper();
        } else if (req.providerPlan.kind === ProviderKind.DIR) {
          void this.bootstrapDirSwiper();
        }
      }
      return;
    }

    this.coordinator.reset(this.currentPage, this.totalPages);
    this.engineMode = RenderEngineMode.GL_PENDING;
    this.activeProvider = this.buildProvider(req);
    if (this.activeProvider === null) {
      this.initializing = false;
      const err: string = GetText.getString('error_reading_failed');
      this.initError = err.length > 0 ? err : 'Failed to open gallery source';
      return;
    }

    this.initializing = true;
    this.startWatchdog();
  }

  aboutToDisappear(): void {
    this.destroyed = true;
    this.lastSwiperSwipeMs = 0;
    this.stopAutoTransfer();
    this.flushStartPageNow();
    this.clearWatchdog();
    this.clearGlRetryTimers();
    this.inFlightPages.clear();
    this.inFlightPreviewPages.clear();
    this.releaseSpiderQueen();
    this.teardownGlStack();
    this.stopProvider();
    this.applyWindowReadingAttributes(false);
  }

  onBackPress(): boolean {
    if (this.settingsDialogOpen) {
      this.settingsDialogOpen = false;
      return true;
    }
    return false;
  }

  onPageShow(): void {
    this.syncReaderSettingsFromPrefs();
    this.refreshClockFormat();
    if (this.destroyed || this.isArkUiMode() || this.initError.length > 0) {
      return;
    }
    const ctrl: GLRootViewController | null = this.glController;
    if (ctrl !== null) {
      ctrl.getRootView().unfreeze();
      ctrl.start();
      ctrl.renderNow();
    }
  }

  onPageHide(): void {
    this.stopAutoTransfer();
    this.flushStartPageNow();
    if (this.isArkUiMode()) {
      return;
    }
    const ctrl: GLRootViewController | null = this.glController;
    if (ctrl !== null) {
      ctrl.getRootView().freeze();
      ctrl.stop();
    }
  }

  private updateDensityRatio(): void {
    try {
      const pxPerVp: number = this.getUIContext().vp2px(1);
      if (pxPerVp > 0 && !Number.isNaN(pxPerVp)) {
        this.vpToPxRatio = pxPerVp;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'vp2px unavailable, keep default ratio: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private applyWindowReadingAttributes(entering: boolean): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return;
    }
    const attached: boolean = Settings.isAttached();
    const fullscreen: boolean = attached ? Settings.getReadingFullscreen() : this.readingFullscreen;
    const keepScreenOn: boolean = attached ? Settings.getKeepScreenOn() : this.keepScreenOn;
    const customLight: boolean = attached ? Settings.getCustomScreenLightness() : this.customScreenLightness;
    const lightness: number = attached ? Settings.getScreenLightness() : this.screenLightness;
    const rotation: number = attached ? Settings.getScreenRotation() : this.screenRotation;
    const privacyMode: boolean = attached ? Settings.getEnabledSecurity() : false;

    window.getLastWindow(ctx).then((win: window.Window): void => {
      if (entering) {
        this.refreshWindowAvoidAreas(win);
        win.setWindowLayoutFullScreen(fullscreen).catch((e: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowLayoutFullScreen failed: %{public}s', e.message);
        });
        win.setWindowSystemBarEnable(fullscreen ? [] : ['status', 'navigation']).catch((e: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowSystemBarEnable failed: %{public}s', e.message);
        });
        win.setWindowKeepScreenOn(keepScreenOn).catch((e: Error): void => {
          hilog.warn(DOMAIN, TAG, 'setWindowKeepScreenOn failed: %{public}s', e.message);
        });
        if (customLight) {
          const brightness: number = lightness > 100
            ? Math.max(0.01, Math.min(1.0, (lightness - 100) / 100.0))
            : 0.01;
          win.setWindowBrightness(brightness).catch((e: Error): void => {
            hilog.warn(DOMAIN, TAG, 'setWindowBrightness failed: %{public}s', e.message);
          });
        } else {
          win.setWindowBrightness(-1).catch((e: Error): void => {
            hilog.warn(DOMAIN, TAG, 'resetWindowBrightness failed: %{public}s', e.message);
          });
        }
        if (rotation !== 0) {
          win.setPreferredOrientation(this.toWindowOrientation(rotation)).catch((e: Error): void => {
            hilog.warn(DOMAIN, TAG, 'setPreferredOrientation failed: %{public}s', e.message);
          });
        }
        applyWindowPrivacyToWindow(win, PrivacySettingsRules.resolveReaderPrivacyMode(privacyMode, true));
        return;
      }

      win.setWindowSystemBarEnable(['status', 'navigation']).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'restore system bars failed: %{public}s', e.message);
      });
      win.setWindowLayoutFullScreen(false).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'restore full screen failed: %{public}s', e.message);
      });
      win.setWindowKeepScreenOn(false).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'restore keepScreenOn failed: %{public}s', e.message);
      });
      win.setWindowBrightness(-1).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'restore brightness failed: %{public}s', e.message);
      });
      win.setPreferredOrientation(window.Orientation.UNSPECIFIED).catch((e: Error): void => {
        hilog.warn(DOMAIN, TAG, 'restore orientation failed: %{public}s', e.message);
      });
      applyWindowPrivacyToWindow(win, PrivacySettingsRules.resolveReaderPrivacyMode(privacyMode, false));
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'getLastWindow failed: %{public}s', e.message);
    });
  }

  private readRouterParams(): ReaderRouteRequest {
    let rec: Record<string, Object> | null = null;
    try {
      const raw: Object = this.getUIContext().getRouter().getParams();
      if (raw !== undefined && raw !== null) {
        rec = raw as Object as Record<string, Object>;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'readRouterParams failed: %{public}s', (e as Error).message);
    }

    const req: ReaderRouteRequest = ReaderRouteRequest.fromParams(rec);
    this.providerKind = req.providerPlan.kind;
    this.dirFilename = req.providerPlan.filename;
    this.archiveUri = req.providerPlan.uri;
    this.gid = req.gid;
    this.token = req.token;
    this.title = req.title;
    this.apiUrl = req.apiUrl;
    this.currentPage = req.page;
    this.totalPages = req.pages;
    if (this.totalPages > 0 && this.currentPage >= this.totalPages) {
      this.currentPage = this.totalPages - 1;
    }
    this.initialSwiperIndex = this.currentPage;
    return req;
  }

  private openUniFile(target: string | null): UniFile | null {
    if (target === null || target.length === 0) {
      return null;
    }
    if (target.startsWith('file://') || target.startsWith('datashare://') || target.startsWith('content://')) {
      return UniFile.fromUri(target);
    }
    return UniFile.fromFile(target);
  }

  private buildProvider(req: ReaderRouteRequest): GalleryProvider2 | null {
    if (req.providerPlan.kind === ProviderKind.ARCHIVE) {
      const file: UniFile | null = this.openUniFile(req.providerPlan.uri);
      if (file === null) {
        return null;
      }
      return new ArchiveGalleryProvider(file);
    }
    if (req.providerPlan.kind === ProviderKind.DIR) {
      const dirFile: UniFile | null = this.openUniFile(req.providerPlan.filename);
      if (dirFile === null) {
        return null;
      }
      return new DirGalleryProvider(dirFile);
    }
    if (req.providerPlan.kind === ProviderKind.EH) {
      const info: GalleryInfo = new GalleryInfo();
      info.gid = req.gid;
      info.token = req.token;
      info.title = req.title;
      info.pages = req.pages;
      return new EhGalleryProvider(info);
    }
    return null;
  }

  private startWatchdog(): void {
    this.clearWatchdog();
    this.watchdogTimerId = setTimeout((): void => {
      this.watchdogTimerId = -1;
      if (this.destroyed) {
        return;
      }
      if (this.coordinator.onWatchdogTimeout()) {
        hilog.warn(DOMAIN, TAG, 'GL surface watchdog timeout after %{public}dms, switching to Swiper fallback',
          ReaderEngineCoordinator.WATCHDOG_MS);
        this.activateSwiperFallback(FallbackReason.WATCHDOG_TIMEOUT);
      }
    }, ReaderEngineCoordinator.WATCHDOG_MS);
  }

  private clearWatchdog(): void {
    if (this.watchdogTimerId >= 0) {
      clearTimeout(this.watchdogTimerId);
      this.watchdogTimerId = -1;
    }
  }

  private clearGlRetryTimers(): void {
    for (let i = 0; i < this.glRetryTimerIds.length; i++) {
      clearTimeout(this.glRetryTimerIds[i]);
    }
    this.glRetryTimerIds = [];
  }

  private resolveSurfaceSizePx(area?: Area): [number, number] {
    try {
      const rect = this.xcController.getXComponentSurfaceRect();
      const sw: number = Math.trunc(rect.surfaceWidth);
      const sh: number = Math.trunc(rect.surfaceHeight);
      if (sw > 0 && sh > 0) {
        this.lastSurfaceWidthPx = sw;
        this.lastSurfaceHeightPx = sh;
        return [sw, sh];
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getXComponentSurfaceRect failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }

    let density: number = 3;
    let dispWidth: number = 0;
    let dispHeight: number = 0;
    try {
      const d = display.getDefaultDisplaySync();
      if (d.densityPixels > 0) {
        density = d.densityPixels;
      }
      dispWidth = Math.trunc(d.width);
      dispHeight = Math.trunc(d.height);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getDefaultDisplaySync failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }

    if (area !== undefined) {
      const aw: number = Math.trunc(Number(area.width) * density);
      const ah: number = Math.trunc(Number(area.height) * density);
      if (aw > 0 && ah > 0) {
        this.lastSurfaceWidthPx = aw;
        this.lastSurfaceHeightPx = ah;
        return [aw, ah];
      }
    }

    if (this.lastSurfaceWidthPx > 0 && this.lastSurfaceHeightPx > 0) {
      return [this.lastSurfaceWidthPx, this.lastSurfaceHeightPx];
    }
    return [dispWidth, dispHeight];
  }

  private scheduleGlReadyRetry(): void {
    this.clearGlRetryTimers();
    const delays: number[] = [50, 150];
    for (let i = 0; i < delays.length; i++) {
      const tid: number = setTimeout((): void => {
        if (this.destroyed || this.engineMode === RenderEngineMode.SWIPER_FALLBACK) {
          return;
        }
        const ctrl: GLRootViewController | null = this.glController;
        if (ctrl === null) {
          return;
        }
        const sizePx: [number, number] = this.resolveSurfaceSizePx();
        if (sizePx[0] > 0 && sizePx[1] > 0) {
          ctrl.notifySurfaceSize(sizePx[0], sizePx[1]);
        }
        ctrl.renderNow();
        if (ctrl.hasCanvas()) {
          this.coordinator.onGlSurfaceReady();
          this.engineMode = RenderEngineMode.GL_ACTIVE;
          this.clearWatchdog();
          this.clearGlRetryTimers();
          this.initializing = false;
        }
      }, delays[i]);
      this.glRetryTimerIds.push(tid);
    }
  }

  private stopProvider(): void {
    const provider: GalleryProvider2 | null = this.activeProvider;
    if (provider !== null) {
      provider.setGLRoot(null);
      provider.setListener(null);
      if (this.providerStarted) {
        try {
          provider.stop();
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'provider.stop failed: %{public}s',
            e instanceof Error ? e.message : String(e));
        }
        this.providerStarted = false;
      }
    }
  }

  private teardownGlStack(): void {
    this.touchBridge.reset();
    const adapter: ReaderSimpleAdapter | null = this.simpleAdapter;
    if (adapter !== null) {
      try {
        adapter.clearUploader();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'adapter.clearUploader failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
      this.simpleAdapter = null;
    }
    const provider: GalleryProvider2 | null = this.activeProvider;
    if (provider !== null) {
      provider.setGLRoot(null);
      provider.setListener(null);
    }
    const ctrl: GLRootViewController | null = this.glController;
    if (ctrl !== null) {
      try {
        ctrl.setContentPane(null);
        ctrl.release();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'glController release failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
      this.glController = null;
    }
    this.galleryView = null;
  }

  private onProviderDataUpdated(size: number, err: string | null): void {
    if (this.destroyed) {
      return;
    }
    if (size === GalleryProvider.STATE_ERROR) {
      this.clearWatchdog();
      this.initializing = false;
      const fallbackMsg: string = GetText.getString('error_reading_failed');
      this.initError = (err !== null && err.length > 0)
        ? err
        : (fallbackMsg.length > 0 ? fallbackMsg : 'Failed to open gallery');
      this.teardownGlStack();
      return;
    }
    if (size >= 0) {
      this.totalPages = size;
      this.coordinator.setTotalPages(size);
      if (this.currentPage >= size && size > 0) {
        this.currentPage = size - 1;
      }
      this.initializing = false;
    }
  }

  private handleXComponentLoad(ctx: object): void {
    if (this.destroyed || this.engineMode === RenderEngineMode.SWIPER_FALLBACK || this.activeProvider === null) {
      return;
    }
    this.teardownGlStack();

    try {
      const ctrl: GLRootViewController = new GLRootViewController(ctx);
      const settingsReady: boolean = Settings.isAttached();
      const refreshHz: number = settingsReady ? Settings.getReadingRefreshRateHz() : 0;
      const layoutMode: number = settingsReady ? Settings.getReadingDirection() : GalleryView.LAYOUT_RIGHT_TO_LEFT;
      const scaleMode: number = settingsReady ? Settings.getPageScaling() : GalleryView.SCALE_FIT;
      const startPosition: number = settingsReady ? Settings.getStartPosition() : GalleryView.START_POSITION_TOP_RIGHT;
      const showPageInterval: boolean = settingsReady ? Settings.getShowPageInterval() : true;

      this.fitCover = scaleMode === GalleryView.SCALE_FIT_WIDTH;
      ctrl.setPreferredRefreshRateHz(refreshHz);

      const probe: GLErr = ctrl.probeBackend();
      if (probe !== GLErr.OK && probe !== GLErr.NOT_READY) {
        ctrl.release();
        this.activateSwiperFallback(FallbackReason.BACKEND_UNAVAILABLE);
        return;
      }

      const provider: GalleryProvider2 = this.activeProvider;
      const adapter: ReaderSimpleAdapter = new ReaderSimpleAdapter(
        ctrl.getRootView(),
        provider,
        (size: number, err: string | null): void => {
          this.onProviderDataUpdated(size, err);
        }
      );

      const gvListener: GalleryViewListener = new ReaderGalleryViewListener(
        provider,
        (index: number): void => {
          if (index >= 0 && index !== this.currentPage) {
            this.currentPage = index;
            this.coordinator.setCurrentPage(index);
          }
        },
        (): void => {
          this.controlsVisible = !this.controlsVisible;
        },
        (): void => {
          this.controlsVisible = !this.controlsVisible;
        },
        (): void => {
          this.controlsVisible = false;
        }
      );

      const intervalPx: number = showPageInterval ? Math.max(12, Math.trunc(16 * this.vpToPxRatio)) : 0;
      const defaultErr: string = GetText.getString('error_reading_failed');
      const emptyStr: string = GetText.getString('empty_result');
      const gv: GalleryView = new GalleryViewBuilder(adapter)
        .setListener(gvListener)
        .setLayoutMode(layoutMode)
        .setScaleMode(scaleMode)
        .setStartPosition(startPosition)
        .setStartPage(this.currentPage)
        .setPagerInterval(intervalPx)
        .setScrollInterval(intervalPx)
        .setDefaultErrorString(defaultErr.length > 0 ? defaultErr : 'Error')
        .setEmptyString(emptyStr.length > 0 ? emptyStr : 'Empty')
        .build();

      ctrl.setOnRenderErrorListener((err: GLErr, consecutiveCount: number): void => {
        if (this.destroyed) {
          return;
        }
        const isFatal: boolean = err === GLErr.PROGRAM_FAILED
          || err === GLErr.OUT_OF_RESOURCES
          || (err === GLErr.NOT_READY && !ctrl.hasCanvas());
        if (this.coordinator.onGlRenderError(consecutiveCount, isFatal)) {
          this.activateSwiperFallback(isFatal ? FallbackReason.SURFACE_INIT_FAILED : FallbackReason.CONSECUTIVE_RENDER_ERRORS);
        }
      });

      this.glController = ctrl;
      this.simpleAdapter = adapter;
      this.galleryView = gv;

      provider.setGLRoot(ctrl.getRootView());
      provider.setListener(adapter);
      if (!this.providerStarted) {
        this.providerStarted = true;
        provider.start();
      }

      ctrl.setContentPane(gv);
      const sizePx: [number, number] = this.resolveSurfaceSizePx();
      const sw: number = sizePx[0];
      const sh: number = sizePx[1];
      if (sw > 0 && sh > 0) {
        ctrl.notifySurfaceSize(sw, sh);
      }
      ctrl.start();
      ctrl.renderNow();

      if (ctrl.hasCanvas()) {
        this.coordinator.onGlSurfaceReady();
        this.engineMode = RenderEngineMode.GL_ACTIVE;
        this.clearWatchdog();
        this.clearGlRetryTimers();
        this.initializing = false;
      } else {
        this.scheduleGlReadyRetry();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'XComponent GL init threw: %{public}s',
        e instanceof Error ? e.message : String(e));
      this.activateSwiperFallback(FallbackReason.SURFACE_INIT_FAILED);
    }
  }

  private handleXComponentAreaChange(area?: Area): void {
    const ctrl: GLRootViewController | null = this.glController;
    if (ctrl === null || this.engineMode === RenderEngineMode.SWIPER_FALLBACK) {
      return;
    }
    try {
      const sizePx: [number, number] = this.resolveSurfaceSizePx(area);
      const sw: number = sizePx[0];
      const sh: number = sizePx[1];
      if (sw > 0 && sh > 0) {
        ctrl.notifySurfaceSize(sw, sh);
        if (ctrl.hasCanvas()) {
          this.coordinator.onGlSurfaceReady();
          this.engineMode = RenderEngineMode.GL_ACTIVE;
          this.clearWatchdog();
          this.clearGlRetryTimers();
          this.initializing = false;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'notifySurfaceSize failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private handleXComponentTouch(ev: TouchEvent): void {
    const ctrl: GLRootViewController | null = this.glController;
    if (ctrl === null || this.engineMode === RenderEngineMode.SWIPER_FALLBACK) {
      return;
    }
    const touches: ArkTouchPoint[] = [];
    for (let i = 0; i < ev.touches.length; i++) {
      touches.push(new TouchPointPayload(ev.touches[i].id, ev.touches[i].x, ev.touches[i].y));
    }
    const changed: ArkTouchPoint[] = [];
    for (let i = 0; i < ev.changedTouches.length; i++) {
      changed.push(new TouchPointPayload(ev.changedTouches[i].id, ev.changedTouches[i].x, ev.changedTouches[i].y));
    }
    const like: ArkTouchEventLike = new TouchEventPayload(ev.type, ev.timestamp, touches, changed);
    const me: MotionEvent | null = this.touchBridge.toMotionEvent(like, this.vpToPxRatio);
    if (me !== null) {
      ctrl.dispatchTouchEvent(me);
    }
  }

  private currentLayoutModeEnum(): LayoutMode {
    const dir: number = Settings.isAttached() ? Settings.getReadingDirection() : this.readingDirection;
    return dir === GalleryView.LAYOUT_LEFT_TO_RIGHT ? LayoutMode.LEFT_TO_RIGHT : LayoutMode.RIGHT_TO_LEFT;
  }

  private handleKeyEvent(ev: KeyEvent): void {
    const galleryCode: number = mapArkKeyCodeToGalleryKeyCode(ev.keyCode);
    if (galleryCode < 0) {
      return;
    }
    const settingsReady: boolean = Settings.isAttached();
    const volumePage: boolean = settingsReady ? Settings.getVolumePage() : this.volumePage;
    const reverseVolume: boolean = settingsReady ? Settings.getReverseVolumePage() : this.reverseVolumePage;

    if (ev.type === KeyType.Up) {
      const upAction: KeyAction = GalleryActivity.keyUpActionFor(galleryCode, volumePage);
      if (upAction === KeyAction.SWALLOW) {
        ev.stopPropagation();
      }
      return;
    }

    if (ev.type !== KeyType.Down) {
      return;
    }

    const layout: LayoutMode = this.currentLayoutModeEnum();
    const action: KeyAction = GalleryActivity.keyActionFor(galleryCode, volumePage, reverseVolume, layout);
    if (action === KeyAction.PASS_THROUGH) {
      return;
    }
    ev.stopPropagation();

    if (action === KeyAction.TAP_MENU) {
      this.controlsVisible = !this.controlsVisible;
      return;
    }

    if (!this.isArkUiMode() && this.galleryView !== null) {
      if (action === KeyAction.PAGE_LEFT) {
        this.galleryView.pageLeft();
      } else if (action === KeyAction.PAGE_RIGHT) {
        this.galleryView.pageRight();
      }
      return;
    }

    const rtl: boolean = layout === LayoutMode.RIGHT_TO_LEFT;
    if (action === KeyAction.PAGE_LEFT) {
      this.goToPage(rtl ? this.currentPage + 1 : this.currentPage - 1);
    } else if (action === KeyAction.PAGE_RIGHT) {
      this.goToPage(rtl ? this.currentPage - 1 : this.currentPage + 1);
    }
  }

  private activateSwiperFallback(reason: FallbackReason): void {
    if (this.engineMode === RenderEngineMode.SWIPER_FALLBACK) {
      return;
    }
    this.coordinator.triggerFallback(reason);
    this.clearWatchdog();
    this.engineMode = RenderEngineMode.SWIPER_FALLBACK;
    this.teardownGlStack();
    this.coordinator.setCurrentPage(this.currentPage);
    this.initialSwiperIndex = this.currentPage;

    try {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.gallery_gl_fallback_toast'),
        duration: 2000
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'fallback showToast failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }

    if (this.providerKind === ProviderKind.EH) {
      const ehProvider: GalleryProvider2 | null = this.activeProvider;
      if (ehProvider !== null && this.providerStarted) {
        try {
          ehProvider.stop();
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'ehProvider.stop failed on fallback: %{public}s',
            e instanceof Error ? e.message : String(e));
        }
        this.providerStarted = false;
      }
      this.bootstrapEhSwiper();
      return;
    }

    if (this.providerKind === ProviderKind.ARCHIVE) {
      this.bootstrapArchiveSwiper();
      return;
    }

    if (this.providerKind === ProviderKind.DIR) {
      this.bootstrapDirSwiper();
      return;
    }

    this.initializing = false;
    this.initError = 'Unsupported reader provider';
  }

  private async bootstrapArchiveSwiper(): Promise<void> {
    const provider: GalleryProvider2 | null = this.activeProvider;
    if (!(provider instanceof ArchiveGalleryProvider)) {
      this.initializing = false;
      this.initError = 'Archive provider unavailable';
      return;
    }
    const archProvider: ArchiveGalleryProvider = provider as ArchiveGalleryProvider;
    if (!this.providerStarted) {
      this.providerStarted = true;
      archProvider.start();
    }
    this.initializing = true;
    this.initError = '';
    const size: number = await archProvider.waitUntilReady();
    if (this.destroyed) {
      return;
    }
    if (size === GalleryProvider.STATE_ERROR) {
      const msg: string = archProvider.getError();
      this.initError = msg.length > 0 ? msg : 'Failed to open archive';
      this.initializing = false;
      return;
    }
    if (size <= 0) {
      const emptyMsg: string = GetText.getString('empty_result');
      this.initError = emptyMsg.length > 0 ? emptyMsg : 'Archive has no readable images';
      this.initializing = false;
      return;
    }
    this.totalPages = size;
    if (this.currentPage >= this.totalPages) {
      this.currentPage = this.totalPages - 1;
    }
    this.initialSwiperIndex = this.currentPage;
    this.dataSource.setTotalPages(this.totalPages);
    this.initializing = false;
    this.schedulePageLoadAndPreload(this.currentPage);
  }

  private async bootstrapDirSwiper(): Promise<void> {
    const provider: GalleryProvider2 | null = this.activeProvider;
    if (!(provider instanceof DirGalleryProvider)) {
      this.initializing = false;
      this.initError = 'Directory provider unavailable';
      return;
    }
    const dirProvider: DirGalleryProvider = provider as DirGalleryProvider;
    if (!this.providerStarted) {
      this.providerStarted = true;
      dirProvider.start();
    }
    this.initializing = true;
    this.initError = '';

    for (let attempt = 0; attempt < 200; attempt++) {
      if (this.destroyed) {
        return;
      }
      const sz: number = dirProvider.size();
      if (sz !== GalleryProvider.STATE_WAIT) {
        break;
      }
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 25);
      });
    }
    if (this.destroyed) {
      return;
    }
    const finalSize: number = dirProvider.size();
    if (finalSize === GalleryProvider.STATE_ERROR) {
      const msg: string = dirProvider.getError();
      this.initError = (msg !== null && msg.length > 0) ? msg : 'Failed to read gallery directory';
      this.initializing = false;
      return;
    }
    if (finalSize <= 0) {
      const emptyMsg: string = GetText.getString('empty_result');
      this.initError = emptyMsg.length > 0 ? emptyMsg : 'Gallery directory is empty';
      this.initializing = false;
      return;
    }
    this.totalPages = finalSize;
    if (this.currentPage >= this.totalPages) {
      this.currentPage = this.totalPages - 1;
    }
    this.initialSwiperIndex = this.currentPage;
    this.dataSource.setTotalPages(this.totalPages);
    this.initializing = false;
    this.schedulePageLoadAndPreload(this.currentPage);
  }

  private async bootstrapEhSwiper(): Promise<void> {
    if (this.gid <= 0 || this.token.length === 0) {
      this.initializing = false;
      this.initError = 'Missing gallery gid or token';
      return;
    }

    if (this.totalPages > 0) {
      if (this.currentPage >= this.totalPages) {
        this.currentPage = this.totalPages - 1;
      }
      this.initialSwiperIndex = this.currentPage;
      this.dataSource.setTotalPages(this.totalPages);
      this.initializing = false;
      this.schedulePageLoadAndPreload(this.currentPage);
      return;
    }

    this.initializing = true;
    this.initError = '';
    try {
      await this.fetchPreviewPage(0, true);
      if (this.destroyed) {
        return;
      }
      if (this.totalPages <= 0) {
        this.initError = 'Gallery has no pages';
        this.initializing = false;
        return;
      }
      if (this.currentPage >= this.totalPages) {
        this.currentPage = this.totalPages - 1;
      }
      this.initialSwiperIndex = this.currentPage;
      this.dataSource.setTotalPages(this.totalPages);
      this.initializing = false;
      this.schedulePageLoadAndPreload(this.currentPage);
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      this.initializing = false;
      this.initError = e instanceof Error && e.message.length > 0 ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'bootstrapEhSwiper failed: %{public}s', this.initError);
    }
  }

  private retryCurrentInit(): void {
    this.initError = '';
    if (this.isArkUiMode()) {
      if (this.providerKind === ProviderKind.ARCHIVE) {
        this.bootstrapArchiveSwiper();
      } else if (this.providerKind === ProviderKind.DIR) {
        this.bootstrapDirSwiper();
      } else if (this.engineMode === RenderEngineMode.ARKUI_PRIMARY) {
        this.releaseSpiderQueen();
        this.bootstrapEhArkUi(this.readRouterParams());
      } else {
        this.bootstrapEhSwiper();
      }
      return;
    }
    this.coordinator.reset(this.currentPage, this.totalPages);
    this.engineMode = RenderEngineMode.GL_PENDING;
    this.initializing = true;
    this.startWatchdog();
  }

  private bootstrapEhArkUi(req: ReaderRouteRequest): void {
    if (req.gid <= 0 || req.token.length === 0) {
      this.initializing = false;
      this.initError = 'Missing gallery gid or token';
      return;
    }

    this.releaseSpiderQueen();
    this.spiderReady = false;
    this.initError = '';

    const info: GalleryInfo = new GalleryInfo();
    info.gid = req.gid;
    info.token = req.token;
    info.title = req.title;
    info.pages = req.pages;

    const queen: SpiderQueen = SpiderQueen.obtainSpiderQueen(info, SpiderQueen.MODE_READ);
    this.spiderQueen = queen;

    const listener: OnSpiderListener = new ArkUiSpiderListener(
      (pages: number): void => {
        if (this.destroyed || this.spiderQueen !== queen) {
          return;
        }
        hilog.info(DOMAIN, TAG, '[ArkUIReader] onGetPages gid=%{public}d pages=%{public}d', this.gid, pages);
        this.onSpiderGetPages(pages);
      },
      (index: number): void => {
        if (this.destroyed || this.spiderQueen !== queen) {
          return;
        }
        hilog.warn(DOMAIN, TAG, '[ArkUIReader] onGet509 gid=%{public}d page=%{public}d', this.gid, index);
        const ps: ReaderPageState | null = this.dataSource.getPageState(index);
        if (ps !== null) {
          ps.errorMessage = 'HTTP 509: Bandwidth Limit Exceeded';
          ps.status = PageLoadStatus.ERROR;
        }
      },
      (index: number, contentLength: number, receivedSize: number, _bytesRead: number): void => {
        if (this.destroyed || this.spiderQueen !== queen) {
          return;
        }
        const ps: ReaderPageState | null = this.dataSource.getPageState(index);
        if (ps !== null && ps.status !== PageLoadStatus.READY) {
          ps.status = PageLoadStatus.LOADING;
          const pct: number = computeSafeDownloadPercent(contentLength, receivedSize);
          if (pct >= 0) {
            ps.progress = pct;
          }
        }
      },
      (index: number, _finished: number, _downloaded: number, _total: number): void => {
        if (this.destroyed || this.spiderQueen !== queen) {
          return;
        }
        const ps: ReaderPageState | null = this.dataSource.getPageState(index);
        if (ps === null) {
          return;
        }
        const uri: string | null = queen.getPageFileUri(index);
        if (uri !== null && uri.length > 0) {
          ps.localPath = uri;
          ps.errorMessage = '';
          ps.progress = 100;
          ps.status = PageLoadStatus.READY;
          hilog.info(DOMAIN, TAG, '[ArkUIReader] pageReady gid=%{public}d page=%{public}d uri=%{public}s',
            this.gid, index, uri);
        } else {
          const msg: string = GetText.getString('error_decoding_failed');
          ps.errorMessage = msg.length > 0 ? msg : 'Image file URI unavailable';
          ps.status = PageLoadStatus.ERROR;
          hilog.warn(DOMAIN, TAG, '[ArkUIReader] pageSuccess but URI null gid=%{public}d page=%{public}d',
            this.gid, index);
        }
      },
      (index: number, error: string, _finished: number, _downloaded: number, _total: number): void => {
        if (this.destroyed || this.spiderQueen !== queen) {
          return;
        }
        hilog.warn(DOMAIN, TAG, '[ArkUIReader] pageFailure gid=%{public}d page=%{public}d err=%{public}s',
          this.gid, index, error);
        const ps: ReaderPageState | null = this.dataSource.getPageState(index);
        if (ps !== null) {
          ps.errorMessage = error;
          ps.status = PageLoadStatus.ERROR;
        }
      },
      (_finished: number, _downloaded: number, _total: number): void => {
        if (this.destroyed || this.spiderQueen !== queen) {
          return;
        }
        if (!this.spiderReady && queen.size() <= 0) {
          const qErr: string = queen.getError();
          const fallbackMsg: string = GetText.getString('error_reading_failed');
          this.initializing = false;
          this.initError = qErr.length > 0 ? qErr : (fallbackMsg.length > 0 ? fallbackMsg : 'Failed to load gallery');
          hilog.warn(DOMAIN, TAG, '[ArkUIReader] init finished without pages gid=%{public}d err=%{public}s',
            this.gid, this.initError);
        }
      }
    );

    this.spiderListener = listener;
    queen.addOnSpiderListener(listener);

    const existingSize: number = queen.size();
    hilog.info(DOMAIN, TAG, '[ArkUIReader] bootstrapEhArkUi gid=%{public}d startPage=%{public}d queenSize=%{public}d',
      this.gid, this.currentPage, existingSize);
    if (existingSize > 0) {
      this.onSpiderGetPages(existingSize);
    } else if (this.totalPages > 0) {
      this.dataSource.setTotalPages(this.totalPages);
      this.initializing = false;
    } else {
      this.initializing = true;
    }
  }

  private onSpiderGetPages(pages: number): void {
    if (pages <= 0) {
      this.initializing = false;
      this.initError = 'Gallery has no pages';
      return;
    }
    this.spiderReady = true;
    this.totalPages = pages;
    this.coordinator.setTotalPages(pages);
    if (this.currentPage >= pages) {
      this.currentPage = pages - 1;
    }
    this.initialSwiperIndex = this.currentPage;
    this.dataSource.setTotalPages(pages);
    this.initializing = false;
    this.schedulePageLoadAndPreload(this.currentPage);
  }

  private requestSpiderPage(index: number, force: boolean): void {
    const queen: SpiderQueen | null = this.spiderQueen;
    if (queen === null || this.destroyed || index < 0 || (this.totalPages > 0 && index >= this.totalPages)) {
      return;
    }
    if (!this.spiderReady && queen.size() <= 0) {
      hilog.info(DOMAIN, TAG, '[ArkUIReader] defer requestSpiderPage until SpiderInfo ready gid=%{public}d page=%{public}d',
        this.gid, index);
      return;
    }
    const ps: ReaderPageState | null = this.dataSource.getPageState(index);
    if (ps !== null) {
      if (!force) {
        if (ps.status === PageLoadStatus.READY && ps.localPath.length > 0) {
          // Already cached in memory; skip blocking stat/access disk probe during page flip
        } else {
          const cachedUri: string | null = queen.getPageFileUri(index);
          if (cachedUri !== null && cachedUri.length > 0) {
            ps.localPath = cachedUri;
            ps.errorMessage = '';
            ps.progress = 100;
            ps.status = PageLoadStatus.READY;
          } else if (ps.status !== PageLoadStatus.LOADING) {
            ps.errorMessage = '';
            ps.progress = -1;
            ps.status = PageLoadStatus.LOADING;
          }
        }
      } else {
        ps.errorMessage = '';
        ps.progress = -1;
        ps.status = PageLoadStatus.LOADING;
      }
    }

    const res: PageRequestResult = force
      ? queen.forceRequestFileOnly(index)
      : queen.requestFileOnly(index);
    if (ps !== null) {
      if (typeof res === 'string') {
        ps.errorMessage = res;
        ps.status = PageLoadStatus.ERROR;
      } else if (typeof res === 'number' && ps.status !== PageLoadStatus.READY) {
        ps.progress = Math.max(0, Math.min(100, Math.round(res * 100)));
      }
    }

    const neighbors: number[] = [index - 1, index + 1, index + 2];
    for (let i = 0; i < neighbors.length; i++) {
      const nIdx: number = neighbors[i];
      if (nIdx >= 0 && (this.totalPages <= 0 || nIdx < this.totalPages)) {
        const nPs: ReaderPageState | null = this.dataSource.getPageState(nIdx);
        if (nPs !== null && (nPs.status !== PageLoadStatus.READY || nPs.localPath.length === 0)) {
          const nUri: string | null = queen.getPageFileUri(nIdx);
          if (nUri !== null && nUri.length > 0) {
            nPs.localPath = nUri;
            nPs.errorMessage = '';
            nPs.progress = 100;
            nPs.status = PageLoadStatus.READY;
          }
        }
      }
    }
  }

  private scheduleSaveStartPage(page: number): void {
    this.pendingStartPage = page;
    if (this.startPageSaveTimer >= 0) {
      clearTimeout(this.startPageSaveTimer);
    }
    this.startPageSaveTimer = setTimeout((): void => {
      this.startPageSaveTimer = -1;
      const queen: SpiderQueen | null = this.spiderQueen;
      if (queen === null || this.pendingStartPage < 0) {
        return;
      }
      const target: number = this.pendingStartPage;
      this.pendingStartPage = -1;
      try {
        queen.putStartPage(target);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'putStartPage failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
    }, 300) as number;
  }

  private flushStartPageNow(): void {
    if (this.startPageSaveTimer >= 0) {
      clearTimeout(this.startPageSaveTimer);
      this.startPageSaveTimer = -1;
    }
    const queen: SpiderQueen | null = this.spiderQueen;
    const pageToWrite: number = this.pendingStartPage >= 0 ? this.pendingStartPage : this.currentPage;
    this.pendingStartPage = -1;
    if (queen !== null && pageToWrite >= 0) {
      try {
        queen.putStartPage(pageToWrite);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'putStartPage failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
    }
  }

  private releaseSpiderQueen(): void {
    this.flushStartPageNow();
    const queen: SpiderQueen | null = this.spiderQueen;
    if (queen !== null) {
      if (this.spiderListener !== null) {
        queen.removeOnSpiderListener(this.spiderListener);
        this.spiderListener = null;
      }
      try {
        SpiderQueen.releaseSpiderQueen(queen, SpiderQueen.MODE_READ);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'releaseSpiderQueen failed: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
      this.spiderQueen = null;
      this.spiderReady = false;
    }
  }

  private getHttpCaller(): HttpCaller {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    return new OkHttpCallerAdapter(EhApplication.getOkHttpClient(ctx === undefined ? null : ctx));
  }

  private getImageDownloader(): PageImageDownloaderImpl {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    const timeoutMs: number = Settings.isAttached() ? Settings.getDownloadTimeout() * 1000 : 0;
    return new PageImageDownloaderImpl(
      EhApplication.getOkHttpClient(ctx === undefined ? null : ctx),
      timeoutMs
    );
  }

  private resolveTempDir(): string {
    const dir: string | null = AppConfig.getTempDir();
    if (dir !== null && dir.length > 0) {
      return dir;
    }
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined && ctx.cacheDir !== undefined && ctx.cacheDir.length > 0) {
      return ctx.cacheDir;
    }
    throw new Error('Temp directory unavailable');
  }

  private getCacheFilePath(index: number): string {
    if (this.providerKind === ProviderKind.ARCHIVE) {
      return `${this.resolveTempDir()}/arch_${this.archiveSessionId}_${index}.img`;
    }
    return `${this.resolveTempDir()}/reader_${this.gid}_${index}.img`;
  }

  private isValidCachedImage(path: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        return false;
      }
      const st: fs.Stat = fs.statSync(path);
      if (st.size <= 0) {
        return false;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buf: ArrayBuffer = new ArrayBuffer(32);
        const readLen: number = fs.readSync(file.fd, buf, { offset: 0, length: 32 });
        if (readLen <= 0) {
          return false;
        }
        const bytes: Uint8Array = new Uint8Array(buf, 0, readLen);
        const isJpeg: boolean = bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xD8;
        const isPng: boolean = bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50
          && bytes[2] === 0x4E && bytes[3] === 0x47;
        const isGif: boolean = bytes.length >= 3 && bytes[0] === 0x47 && bytes[1] === 0x49
          && bytes[2] === 0x46;
        const isWebp: boolean = bytes.length >= 4 && bytes[0] === 0x52 && bytes[1] === 0x49
          && bytes[2] === 0x46 && bytes[3] === 0x46;
        if (isJpeg || isPng || isGif || isWebp) {
          return true;
        }
        if (bytes[0] === 0x3C || bytes[0] === 0x7B) {
          return false;
        }
        return st.size >= 512;
      } finally {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          hilog.warn(DOMAIN, TAG, 'closeSync failed for %{public}s: %{public}s',
            path, (closeErr as Error).message);
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'isValidCachedImage check failed for %{public}s: %{public}s',
        path, (e as Error).message);
      return false;
    }
  }

  private safeUnlink(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'unlinkSync failed for %{public}s: %{public}s',
        path, (e as Error).message);
    }
  }

  private recordPreviewSet(previewPageIndex: number, ps: PreviewSet): void {
    this.previewSetCache.set(previewPageIndex, ps);
    const sz: number = ps.size();
    if (previewPageIndex === 0 && sz > 0 && this.perPage <= 0) {
      this.perPage = sz;
    }
    for (let i = 0; i < sz; i++) {
      const pos: number = ps.getPosition(i);
      const url: string = ps.getPageUrlAt(i);
      if (pos >= 0 && url.length > 0) {
        this.pageUrlCache.set(pos, url);
        const parsed: PageUrlResult | null = GalleryPageUrlParser.parse(url);
        if (parsed !== null && parsed.pToken.length > 0) {
          this.pTokenCache.set(pos, parsed.pToken);
        }
      }
    }
  }

  private async fetchPreviewPage(previewPageIndex: number, useDetailIfFirst: boolean): Promise<void> {
    if (this.previewSetCache.has(previewPageIndex)) {
      return;
    }
    const existing: Promise<void> | undefined = this.inFlightPreviewPages.get(previewPageIndex);
    if (existing !== undefined) {
      return existing;
    }

    const task: Promise<void> = (async (): Promise<void> => {
      const caller: HttpCaller = this.getHttpCaller();
      const detailUrl: string = (previewPageIndex === 0 && this.apiUrl.length > 0)
        ? this.apiUrl
        : EhUrl.getGalleryDetailUrl(this.gid, this.token, previewPageIndex, false);
      if (previewPageIndex === 0 && useDetailIfFirst) {
        const detail: GalleryDetail = await EhEngine.getGalleryDetail(null, caller, detailUrl);
        if (this.destroyed) {
          return;
        }
        if (detail.pages > 0) {
          this.totalPages = detail.pages;
        }
        if (detail.title.length > 0 && this.title.length === 0) {
          this.title = detail.title;
        }
        const ps: PreviewSet | null = detail.previewSet !== null
          ? detail.previewSet : detail.SpiderInfoPreviewSet;
        if (ps !== null) {
          this.recordPreviewSet(0, ps);
        }
      } else {
        const res: PreviewSetResult = await EhEngine.getPreviewSet(null, caller, detailUrl);
        if (this.destroyed) {
          return;
        }
        if (res.previewSet !== null) {
          this.recordPreviewSet(previewPageIndex, res.previewSet);
        }
      }
    })();

    this.inFlightPreviewPages.set(previewPageIndex, task);
    try {
      await task;
    } finally {
      this.inFlightPreviewPages.delete(previewPageIndex);
    }
  }

  private async resolvePageUrl(index: number): Promise<string> {
    const cached: string | undefined = this.pageUrlCache.get(index);
    if (cached !== undefined && cached.length > 0) {
      return cached;
    }

    if (this.perPage <= 0) {
      await this.fetchPreviewPage(0, this.totalPages <= 0);
      if (this.destroyed) {
        throw new Error('Reader destroyed');
      }
      const afterFirst: string | undefined = this.pageUrlCache.get(index);
      if (afterFirst !== undefined && afterFirst.length > 0) {
        return afterFirst;
      }
    }

    const pageSize: number = this.perPage > 0 ? this.perPage : 20;
    const guessPage: number = Math.floor(index / pageSize);
    await this.fetchPreviewPage(guessPage, false);
    if (this.destroyed) {
      throw new Error('Reader destroyed');
    }

    let resolved: string | undefined = this.pageUrlCache.get(index);
    if (resolved !== undefined && resolved.length > 0) {
      return resolved;
    }

    const ps: PreviewSet | undefined = this.previewSetCache.get(guessPage);
    if (ps !== undefined && ps.size() > 0) {
      const firstPos: number = ps.getPosition(0);
      const lastPos: number = ps.getPosition(ps.size() - 1);
      if (index < firstPos && guessPage > 0) {
        await this.fetchPreviewPage(guessPage - 1, false);
      } else if (index > lastPos) {
        await this.fetchPreviewPage(guessPage + 1, false);
      }
      resolved = this.pageUrlCache.get(index);
      if (resolved !== undefined && resolved.length > 0) {
        return resolved;
      }
    }

    throw new Error('Page URL not found for page ' + String(index + 1));
  }

  private loadPageAndPreloadNeighbors(index: number): void {
    if (this.engineMode === RenderEngineMode.ARKUI_PRIMARY && this.providerKind === ProviderKind.EH) {
      this.requestSpiderPage(index, false);
      return;
    }
    this.ensurePageLoaded(index, false);
    if (index + 1 < this.totalPages) {
      this.ensurePageLoaded(index + 1, false);
    }
    if (index - 1 >= 0) {
      this.ensurePageLoaded(index - 1, false);
    }
  }

  private reloadPage(index: number): void {
    if (!this.isArkUiMode() && this.activeProvider !== null) {
      this.activeProvider.forceRequest(index);
      return;
    }
    if (this.engineMode === RenderEngineMode.ARKUI_PRIMARY && this.providerKind === ProviderKind.EH) {
      this.requestSpiderPage(index, true);
      return;
    }
    try {
      const cachePath: string = this.getCacheFilePath(index);
      this.safeUnlink(cachePath);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'reloadPage clear cache failed: %{public}s', (e as Error).message);
    }
    this.ensurePageLoaded(index, true);
  }

  private ensurePageLoaded(index: number, forceReload: boolean): void {
    if (this.destroyed || index < 0 || (this.totalPages > 0 && index >= this.totalPages)) {
      return;
    }
    const pageState: ReaderPageState | null = this.dataSource.getPageState(index);
    if (pageState === null) {
      return;
    }
    if (!forceReload && pageState.status === PageLoadStatus.READY && pageState.localPath.length > 0) {
      return;
    }
    if (this.inFlightPages.has(index)) {
      return;
    }

    const job: Promise<void> = this.executeLoadPage(index, pageState, forceReload);
    this.inFlightPages.set(index, job);
    job.finally(() => {
      this.inFlightPages.delete(index);
    });
  }

  private async executeLoadPage(index: number, pageState: ReaderPageState, forceReload: boolean): Promise<void> {
    if (this.providerKind === ProviderKind.DIR) {
      const provider: GalleryProvider2 | null = this.activeProvider;
      if (provider instanceof DirGalleryProvider) {
        const uri: string | null = (provider as DirGalleryProvider).getPageUri(index);
        if (uri !== null && uri.length > 0) {
          pageState.localPath = uri;
          pageState.errorMessage = '';
          pageState.status = PageLoadStatus.READY;
          return;
        }
      }
      pageState.errorMessage = 'Page file unavailable';
      pageState.status = PageLoadStatus.ERROR;
      return;
    }

    if (this.providerKind === ProviderKind.ARCHIVE) {
      const provider: GalleryProvider2 | null = this.activeProvider;
      if (!(provider instanceof ArchiveGalleryProvider)) {
        pageState.errorMessage = 'Archive provider unavailable';
        pageState.status = PageLoadStatus.ERROR;
        return;
      }
      try {
        const cachePath: string = this.getCacheFilePath(index);
        if (!forceReload && this.isValidCachedImage(cachePath)) {
          if (!this.destroyed) {
            pageState.localPath = cachePath;
            pageState.errorMessage = '';
            pageState.status = PageLoadStatus.READY;
          }
          return;
        }
        if (!this.destroyed) {
          pageState.status = PageLoadStatus.LOADING;
          pageState.errorMessage = '';
        }
        const extracted: boolean = await (provider as ArchiveGalleryProvider).preparePageFileForSwiper(
          index, cachePath
        );
        if (this.destroyed) {
          return;
        }
        if (extracted) {
          pageState.localPath = cachePath;
          pageState.errorMessage = '';
          pageState.status = PageLoadStatus.READY;
        } else {
          pageState.errorMessage = GetText.getString('error_decoding_failed');
          pageState.status = PageLoadStatus.ERROR;
        }
      } catch (e) {
        if (!this.destroyed) {
          pageState.errorMessage = e instanceof Error && e.message.length > 0 ? e.message : String(e);
          pageState.status = PageLoadStatus.ERROR;
        }
      }
      return;
    }

    try {
      const cachePath: string = this.getCacheFilePath(index);
      if (!forceReload && this.isValidCachedImage(cachePath)) {
        if (!this.destroyed) {
          pageState.localPath = cachePath;
          pageState.errorMessage = '';
          pageState.status = PageLoadStatus.READY;
        }
        return;
      }

      if (!this.destroyed) {
        pageState.status = PageLoadStatus.LOADING;
        pageState.errorMessage = '';
      }

      const basePageUrl: string = await this.resolvePageUrl(index);
      if (this.destroyed) {
        return;
      }

      const caller: HttpCaller = this.getHttpCaller();
      const downloader: PageImageDownloaderImpl = this.getImageDownloader();
      const pToken: string = this.pTokenCache.get(index) ?? '';
      const prevPToken: string | null = index > 0 ? (this.pTokenCache.get(index - 1) ?? null) : null;

      let requestPageUrl: string = basePageUrl;
      let skipHathKey: string = '';
      let lastErr: string = 'Image download failed';

      for (let attempt = 0; attempt < 2; attempt++) {
        if (this.destroyed) {
          return;
        }
        let imageUrl: string = '';
        let originUrl: string = '';

        if (attempt === 0 && !forceReload && this.showKey.length > 0 && pToken.length > 0) {
          try {
            const apiRes: GalleryPageApiParserResult = await EhEngine.getGalleryPageApi(
              null, caller, this.gid, index, pToken, this.showKey, prevPToken
            );
            imageUrl = apiRes.imageUrl.length > 0 ? apiRes.imageUrl : apiRes.otherImageUrl;
            originUrl = apiRes.originImageUrl;
            skipHathKey = apiRes.skipHathKey;
          } catch (apiErr) {
            hilog.warn(DOMAIN, TAG, 'getGalleryPageApi fallback to HTML for page %{public}d: %{public}s',
              index, (apiErr as Error).message);
            this.showKey = '';
          }
        }

        if (this.destroyed) {
          return;
        }

        if (imageUrl.length === 0) {
          const htmlRes: GalleryPageParserResult = await EhEngine.getGalleryPage(
            null, caller, requestPageUrl, this.gid, this.token
          );
          if (this.destroyed) {
            return;
          }
          if (htmlRes.showKey.length > 0) {
            this.showKey = htmlRes.showKey;
          }
          if (htmlRes.skipHathKey.length > 0) {
            skipHathKey = htmlRes.skipHathKey;
          }
          imageUrl = htmlRes.imageUrl;
          originUrl = htmlRes.originImageUrl;
          if (imageUrl.length === 0 && this.showKey.length > 0 && pToken.length > 0) {
            const apiFallback: GalleryPageApiParserResult = await EhEngine.getGalleryPageApi(
              null, caller, this.gid, index, pToken, this.showKey, prevPToken
            );
            imageUrl = apiFallback.imageUrl.length > 0 ? apiFallback.imageUrl : apiFallback.otherImageUrl;
            if (originUrl.length === 0) {
              originUrl = apiFallback.originImageUrl;
            }
          }
        }

        if (Settings.isAttached() && Settings.getDownloadOriginImage() && originUrl.length > 0) {
          const resolvedOrigin: string | null = await downloader.resolveRedirectUrl(originUrl, requestPageUrl);
          if (resolvedOrigin === null) {
            throw new Error('GP不足 / Insufficient GP');
          }
          imageUrl = resolvedOrigin;
        }

        if (imageUrl.length === 0) {
          lastErr = 'Empty image URL';
          break;
        }
        if (imageUrl.indexOf('/509.gif') >= 0 || imageUrl.endsWith('509.gif')) {
          lastErr = 'HTTP 509: Image quota exceeded';
          if (attempt === 0 && skipHathKey.length > 0) {
            const sep: string = requestPageUrl.indexOf('?') >= 0 ? '&nl=' : '?nl=';
            requestPageUrl = requestPageUrl + sep + skipHathKey;
            this.showKey = '';
            continue;
          }
          throw new Error(lastErr);
        }

        const tmpPath: string = cachePath + '.tmp';
        this.safeUnlink(tmpPath);
        const pipe: FileOutputStreamPipe = new FileOutputStreamPipe(tmpPath);
        const progressThrottle: ProgressThrottle = new ProgressThrottle();
        let dlResult: DownloadResult;
        try {
          const sink: ByteSink = pipe.open();
          dlResult = await downloader.downloadWithStatus(
            imageUrl,
            sink,
            requestPageUrl,
            (cl: number, rec: number, _br: number): void => {
              if (this.destroyed) {
                return;
              }
              const pct: number = computeSafeDownloadPercent(cl, rec);
              if (pct >= 0 && progressThrottle.shouldEmit(pct, Date.now())) {
                pageState.progress = pct;
              }
            }
          );
        } finally {
          pipe.close();
        }

        if (this.destroyed) {
          this.safeUnlink(tmpPath);
          return;
        }

        if (dlResult.ok && dlResult.received > 0 && this.isValidCachedImage(tmpPath)) {
          this.safeUnlink(cachePath);
          fs.renameSync(tmpPath, cachePath);
          pageState.localPath = cachePath;
          pageState.errorMessage = '';
          pageState.progress = 100;
          pageState.status = PageLoadStatus.READY;
          return;
        }

        this.safeUnlink(tmpPath);
        lastErr = dlResult.error.length > 0 ? dlResult.error : ('HTTP ' + String(dlResult.status));
        if (attempt === 0 && skipHathKey.length > 0) {
          const sep: string = requestPageUrl.indexOf('?') >= 0 ? '&nl=' : '?nl=';
          requestPageUrl = requestPageUrl + sep + skipHathKey;
          this.showKey = '';
          continue;
        }
      }

      throw new Error(lastErr);
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const msg: string = e instanceof Error && e.message.length > 0 ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'executeLoadPage failed: gid=%{public}d page=%{public}d err=%{public}s',
        this.gid, index, msg);
      pageState.errorMessage = msg;
      pageState.status = PageLoadStatus.ERROR;
    }
  }

  private preloadSwiperNeighbors(index: number): void {
    if (!this.isArkUiMode() ||
      this.readingDirection === GalleryView.LAYOUT_TOP_TO_BOTTOM ||
      this.totalPages <= 1) {
      return;
    }
    const candidates: number[] = [index + 1, index + 2, index - 1];
    const valid: number[] = [];
    for (let i = 0; i < candidates.length; i++) {
      const idx: number = candidates[i];
      if (idx >= 0 && idx < this.totalPages) {
        valid.push(idx);
      }
    }
    if (valid.length === 0) {
      return;
    }
    try {
      this.swiperController.preloadItems(valid).catch((e: Error): void => {
        hilog.debug(DOMAIN, TAG, 'preloadItems skipped: %{public}s', e.message);
      });
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'preloadItems threw: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  private schedulePageLoadAndPreload(index: number): void {
    Promise.resolve().then((): void => {
      if (this.destroyed) {
        return;
      }
      this.loadPageAndPreloadNeighbors(index);
      this.preloadSwiperNeighbors(index);
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, 'schedulePageLoadAndPreload failed: %{public}s', e.message);
    });
  }

  private onSwiperPageChanged(newIndex: number): void {
    this.lastSwiperSwipeMs = 0;
    if (newIndex < 0 || (this.totalPages > 0 && newIndex >= this.totalPages)) {
      return;
    }
    if (newIndex === this.currentPage) {
      return;
    }
    if (this.currentPageZoomed || this.zoomed) {
      this.currentPageZoomed = false;
      this.zoomed = false;
      this.zoomResetSeq++;
    }
    this.currentPage = newIndex;
    this.coordinator.setCurrentPage(newIndex);
    this.scheduleSaveStartPage(newIndex);
    this.schedulePageLoadAndPreload(newIndex);
  }

  private onWebtoonScrollIndex(firstIndex: number): void {
    if (firstIndex < 0 || (this.totalPages > 0 && firstIndex >= this.totalPages)) {
      return;
    }
    if (firstIndex !== this.currentPage) {
      this.currentPage = firstIndex;
      this.coordinator.setCurrentPage(firstIndex);
      this.scheduleSaveStartPage(firstIndex);
    }
    this.schedulePageLoadAndPreload(firstIndex);
  }

  private goToPage(target: number): void {
    if (this.totalPages <= 0) {
      return;
    }
    const clamped: number = Math.max(0, Math.min(target, this.totalPages - 1));
    if (clamped === this.currentPage) {
      return;
    }
    if (this.currentPageZoomed || this.zoomed) {
      this.currentPageZoomed = false;
      this.zoomed = false;
      this.zoomResetSeq++;
    }
    this.currentPage = clamped;
    this.coordinator.setCurrentPage(clamped);
    if (!this.isArkUiMode() && this.galleryView !== null) {
      this.scheduleSaveStartPage(clamped);
      this.galleryView.setCurrentPage(clamped);
      return;
    }
    if (this.readingDirection === GalleryView.LAYOUT_TOP_TO_BOTTOM) {
      this.webtoonScroller.scrollToIndex(clamped, false);
    } else {
      this.swiperController.changeIndex(clamped, this.pageTurnAnimation);
    }
    this.scheduleSaveStartPage(clamped);
    this.schedulePageLoadAndPreload(clamped);
  }

  private stepPageVisualLeft(): void {
    if (!this.isArkUiMode() && this.galleryView !== null) {
      this.galleryView.pageLeft();
      return;
    }
    const rtl: boolean = this.readingDirection === LayoutMode.RIGHT_TO_LEFT;
    this.goToPage(rtl ? this.currentPage + 1 : this.currentPage - 1);
  }

  private stepPageVisualRight(): void {
    if (!this.isArkUiMode() && this.galleryView !== null) {
      this.galleryView.pageRight();
      return;
    }
    const rtl: boolean = this.readingDirection === LayoutMode.RIGHT_TO_LEFT;
    this.goToPage(rtl ? this.currentPage - 1 : this.currentPage + 1);
  }

  private stopAutoTransfer(): void {
    if (this.autoTransferTimerId >= 0) {
      clearInterval(this.autoTransferTimerId);
      this.autoTransferTimerId = -1;
    }
    this.autoTransferring = false;
  }

  private toggleAutoTransfer(): void {
    const next: boolean = GalleryActivity.toggleAutoTransfer(this.autoTransferring);
    if (!next) {
      this.stopAutoTransfer();
      return;
    }
    this.autoTransferring = true;
    const intervalSec: number = Math.max(1, this.startTransferTime > 0 ? this.startTransferTime : 2);
    this.autoTransferTimerId = setInterval((): void => {
      if (this.destroyed || !this.autoTransferring) {
        this.stopAutoTransfer();
        return;
      }
      if (this.totalPages > 0 && this.currentPage >= this.totalPages - 1) {
        this.stopAutoTransfer();
        return;
      }
      if (!this.isArkUiMode() && this.galleryView !== null) {
        if (this.readingDirection === LayoutMode.RIGHT_TO_LEFT) {
          this.galleryView.pageLeft();
        } else {
          this.galleryView.pageRight();
        }
        return;
      }
      this.goToPage(this.currentPage + 1);
    }, intervalSec * 1000);
  }

  private zoomLabel(): string {
    return this.zoomed ? '2x' : '1x';
  }

  private headerProgressText(): string {
    if (this.totalPages <= 0 || this.currentPage < 0) {
      return '';
    }
    return `${this.currentPage + 1}/${this.totalPages}`;
  }

  private sliderLeftLabel(): string {
    if (this.totalPages <= 0) {
      return '-';
    }
    return this.readingDirection === LayoutMode.RIGHT_TO_LEFT
      ? `${this.totalPages}`
      : `${this.currentPage + 1}`;
  }

  private sliderRightLabel(): string {
    if (this.totalPages <= 0) {
      return '-';
    }
    return this.readingDirection === LayoutMode.RIGHT_TO_LEFT
      ? `${this.currentPage + 1}`
      : `${this.totalPages}`;
  }

  @Builder
  headerBatterySlot() {
    BatteryView({
      fontSize: ThemeTypography.TEXT_SMALL,
      color: this.readerStatusColor(),
      warningColor: this.palette().errorColor,
      textShadowOptions: this.headerShadow
    })
  }

  @Builder
  headerProgressSlot() {
    Text(this.headerProgressText())
      .fontSize(ThemeTypography.TEXT_SMALL)
      .fontColor(this.readerStatusColor())
      .maxLines(1)
      .textShadow(this.headerShadow)
  }

  @Builder
  headerClockSlot() {
    HippoTextClock({
      is24HourMode: this.is24HourClock,
      fontSize: ThemeTypography.TEXT_SMALL,
      fontColor: this.readerStatusColor(),
      textShadowOptions: this.headerShadow
    })
  }

  @Builder
  topOverlay() {
    Column() {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.palette().white
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .borderRadius(ThemeRadius.NONE)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.getUIContext().getRouter().back();
        })

        Text(this.title)
          .layoutWeight(1)
          .fontSize(ThemeTypography.TEXT_MEDIUM)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().white)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 4, right: 4 })

        Button({ type: ButtonType.Normal }) {
          Text(this.fitCover
            ? $r('app.string.settings_read_page_scaling_fit_to_width')
            : $r('app.string.settings_read_page_scaling_fit_to_screen'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().white)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .height(36)
        .constraintSize({ minWidth: ThemeDimens.TOUCH_TARGET_MIN, maxWidth: 96 })
        .padding({ left: 8, right: 8 })
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(this.palette().readerControlBg)
        .onClick((): void => {
          this.fitCover = !this.fitCover;
          const nextMode: number = this.fitCover ? GalleryView.SCALE_FIT_WIDTH : GalleryView.SCALE_FIT;
          this.pageScaling = nextMode;
          Settings.putPageScaling(nextMode);
          if (!this.isArkUiMode() && this.galleryView !== null) {
            this.galleryView.setScaleMode(nextMode);
          }
        })

        if (this.isArkUiMode()) {
          Button({ type: ButtonType.Normal }) {
            Text(this.zoomLabel())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().white)
          }
          .width(40)
          .height(36)
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(this.zoomed ? this.palette().colorPrimary : this.palette().readerControlBg)
          .onClick((): void => {
            this.zoomed = !this.zoomed;
            this.currentPageZoomed = this.zoomed;
          })
        }

        Button({ type: ButtonType.Normal }) {
          VRefreshDarkX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.palette().white
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .borderRadius(ThemeRadius.NONE)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.reloadPage(this.currentPage);
        })

        Button({ type: ButtonType.Normal }) {
          VSettingsDarkX24({
            iconSize: ThemeDimens.ICON_SIZE_STANDARD,
            fillColor: this.palette().white
          })
        }
        .width(ThemeDimens.TOUCH_TARGET_MIN)
        .height(ThemeDimens.TOUCH_TARGET_MIN)
        .borderRadius(ThemeRadius.NONE)
        .backgroundColor(Color.Transparent)
        .onClick((): void => {
          this.syncReaderSettingsFromPrefs();
          this.settingsDialogOpen = true;
        })
      }
      .width('100%')
      .height(ThemeDimens.TOOLBAR_HEIGHT)
      .padding({ left: 4, right: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: this.cutoutTopVp })
    .backgroundColor(this.palette().readerOverlayScrim)
    .hitTestBehavior(HitTestMode.Default)
    .onClick((): void => {
      // Absorb clicks on empty toolbar area without blocking child buttons or leaking to Swiper
    })
  }

  @Builder
  bottomOverlay() {
    Column() {
      Button({ type: ButtonType.Normal }) {
        if (this.autoTransferring) {
          IcPauseCircle({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().white })
        } else {
          IcStartPlay24({ iconSize: ThemeDimens.ICON_SIZE_STANDARD, fillColor: this.palette().white })
        }
      }
      .width(45)
      .height(45)
      .borderRadius(22.5)
      .backgroundColor(this.autoTransferring ? this.palette().colorPrimary : this.palette().readerOverlayScrim)
      .margin({ right: 16, bottom: 12 })
      .onClick((): void => {
        this.toggleAutoTransfer();
      })

      Column() {
        SeekBarPanel({
          value: this.currentPage,
          min: 0,
          max: Math.max(0, this.totalPages - 1),
          reverse: this.readingDirection === LayoutMode.RIGHT_TO_LEFT,
          selectedColor: this.palette().colorPrimary,
          trackColor: '#4DFFFFFF',
          blockColor: this.palette().colorPrimary,
          panelBackgroundColor: this.palette().gallerySliderBackground,
          textColor: this.palette().white,
          leftText: this.sliderLeftLabel(),
          rightText: this.sliderRightLabel(),
          bottomSafePadding: this.bottomSafeVp,
          onProgressConfirm: (val: number): void => {
            this.goToPage(val);
          },
          onStepLeft: (): void => {
            this.stepPageVisualLeft();
          },
          onStepRight: (): void => {
            this.stepPageVisualRight();
          }
        })
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.Default)
      .onClick((): void => {
        // Absorb clicks on seek panel area without blocking SeekBar drags or step buttons
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  readingSettingsDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Text($r('app.string.settings_read'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        DialogGalleryMenuLayout({
          screenRotation: this.screenRotation,
          readingDirection: this.readingDirection,
          pageScaling: this.pageScaling,
          startPosition: this.startPosition,
          startTransferTime: this.startTransferTime,
          screenLightness: this.screenLightness,
          keepScreenOn: this.keepScreenOn,
          showClock: this.showClock,
          showProgress: this.showProgress,
          showBattery: this.showBattery,
          showPageInterval: this.showPageInterval,
          pageTurnAnimation: this.pageTurnAnimation,
          volumePage: this.volumePage,
          reverseVolumePage: this.reverseVolumePage,
          readingFullscreen: this.readingFullscreen,
          customScreenLightness: this.customScreenLightness,
          textPrimaryColor: this.palette().textPrimary,
          textSecondaryColor: this.palette().textSecondary,
          primaryColor: this.palette().colorPrimary,
          controlActivatedColor: this.palette().controlActivated,
          dividerColor: this.palette().divider,
          popupBgColor: this.palette().popupBackground,
          selectedOptionBgColor: this.palette().cardActivatedBackground,
          onScreenRotationChange: (idx: number): void => {
            this.screenRotation = idx;
            Settings.putScreenRotation(idx);
            this.applyWindowReadingAttributes(true);
          },
          onReadingDirectionChange: (idx: number): void => {
            const dir: number = GalleryView.sanitizeLayoutMode(idx);
            this.readingDirection = dir;
            Settings.putReadingDirection(dir);
            this.initialSwiperIndex = this.currentPage;
            this.currentPageZoomed = false;
            this.zoomed = false;
            this.webtoonScale = 1.0;
            this.zoomResetSeq++;
            if (this.galleryView !== null) {
              this.galleryView.setLayoutMode(dir);
            }
          },
          onPageScalingChange: (idx: number): void => {
            const scale: number = GalleryView.sanitizeScaleMode(idx);
            this.pageScaling = scale;
            this.fitCover = scale === GalleryView.SCALE_FIT_WIDTH;
            Settings.putPageScaling(scale);
            if (this.galleryView !== null) {
              this.galleryView.setScaleMode(scale);
            }
          },
          onStartPositionChange: (idx: number): void => {
            const pos: number = GalleryView.sanitizeStartPosition(idx);
            this.startPosition = pos;
            Settings.putStartPosition(pos);
            if (this.galleryView !== null) {
              this.galleryView.setStartPosition(pos);
            }
          },
          onStartTransferTimeChange: (value: number): void => {
            this.startTransferTime = value;
            Settings.putStartTransferTime(value);
          },
          onKeepScreenOnChange: (checked: boolean): void => {
            this.keepScreenOn = checked;
            Settings.putKeepScreenOn(checked);
            this.applyWindowReadingAttributes(true);
          },
          onShowClockChange: (checked: boolean): void => {
            this.showClock = checked;
            Settings.putShowClock(checked);
          },
          onShowProgressChange: (checked: boolean): void => {
            this.showProgress = checked;
            Settings.putShowProgress(checked);
          },
          onShowBatteryChange: (checked: boolean): void => {
            this.showBattery = checked;
            Settings.putShowBattery(checked);
          },
          onShowPageIntervalChange: (checked: boolean): void => {
            this.showPageInterval = checked;
            Settings.putShowPageInterval(checked);
            if (this.galleryView !== null) {
              const px: number = checked ? Math.max(12, Math.trunc(16 * this.vpToPxRatio)) : 0;
              this.galleryView.setPagerInterval(px);
              this.galleryView.setScrollInterval(px);
            }
          },
          onPageTurnAnimationChange: (checked: boolean): void => {
            this.pageTurnAnimation = checked;
            Settings.putPageTurnAnimation(checked);
          },
          onVolumePageChange: (checked: boolean): void => {
            this.volumePage = checked;
            Settings.putVolumePage(checked);
          },
          onReverseVolumePageChange: (checked: boolean): void => {
            this.reverseVolumePage = checked;
            Settings.putReverseVolumePage(checked);
          },
          onReadingFullscreenChange: (checked: boolean): void => {
            this.readingFullscreen = checked;
            Settings.putReadingFullscreen(checked);
            this.applyWindowReadingAttributes(true);
          },
          onCustomScreenLightnessChange: (checked: boolean): void => {
            this.customScreenLightness = checked;
            Settings.putCustomScreenLightness(checked);
            this.applyWindowReadingAttributes(true);
          },
          onScreenLightnessChange: (value: number): void => {
            this.screenLightness = value;
            Settings.putScreenLightness(value);
            this.applyWindowReadingAttributes(true);
          }
        })

        Row({ space: 8 }) {
          Blank().layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().colorPrimary)
          }
          .height(36)
          .constraintSize({ minWidth: 64 })
          .padding({ left: 16, right: 16 })
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.settingsDialogOpen = false;
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('90%')
      .constraintSize({ maxWidth: 400, maxHeight: '85%' })
      .borderRadius(ThemeRadius.DIALOG)
      .backgroundColor(this.palette().popupBackground)
      .shadow(ThemeElevation.dialog())
      .hitTestBehavior(HitTestMode.Default)
      .onClick((): void => {
        // Consume clicks inside dialog card
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#80000000')
    .hitTestBehavior(HitTestMode.Default)
    .onClick((): void => {
      this.settingsDialogOpen = false;
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.initError.length > 0) {
        Column({ space: 12 }) {
          Text($r('app.string.load_failed'))
            .fontSize(ThemeTypography.TEXT_MEDIUM)
            .fontColor(this.palette().errorColor)
            .fontWeight(FontWeight.Bold)
          Text(this.initError)
            .fontSize(12)
            .fontColor('#FFDDDDDD')
            .textAlign(TextAlign.Center)
          Row({ space: 12 }) {
            Button($r('app.string.gallery_gl_fallback_action_close'), { type: ButtonType.Normal })
              .height(40)
              .padding({ left: 20, right: 20 })
              .borderRadius(ThemeRadius.BUTTON)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.palette().readerControlBg)
              .fontColor(Color.White)
              .onClick(() => { this.getUIContext().getRouter().back(); })
            Button($r('app.string.retry'), { type: ButtonType.Normal })
              .height(40)
              .padding({ left: 20, right: 20 })
              .borderRadius(ThemeRadius.BUTTON)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(this.palette().colorPrimary)
              .fontColor(Color.White)
              .onClick(() => { this.retryCurrentInit(); })
          }
        }
        .width('100%')
        .height('100%')
        .padding(24)
        .justifyContent(FlexAlign.Center)
      } else if (!this.isArkUiMode()) {
        XComponent({
          id: 'gallery_reader_gl',
          type: XComponentType.SURFACE,
          libraryname: 'native-lib',
          controller: this.xcController
        })
          .width('100%')
          .height('100%')
          .onLoad((ctx: object) => {
            this.handleXComponentLoad(ctx);
          })
          .onDestroy(() => {
            const ctrl: GLRootViewController | null = this.glController;
            if (ctrl !== null) {
              ctrl.onSurfaceDestroyed();
            }
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.handleXComponentAreaChange(newArea);
          })
          .onTouch((ev: TouchEvent) => {
            this.handleXComponentTouch(ev);
          })

        if (this.initializing) {
          Column({ space: 16 }) {
            LoadingProgress()
              .width(56)
              .height(56)
              .color(this.palette().colorPrimary)
            Text($r('app.string.loading'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor('#FFCCCCCC')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
      } else if (this.initializing) {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(56)
            .height(56)
            .color(this.palette().colorPrimary)
          Text($r('app.string.loading'))
            .fontSize(ThemeTypography.TEXT_SMALL)
            .fontColor('#FFCCCCCC')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.controlsVisible = !this.controlsVisible;
        })
      } else if (this.readingDirection === GalleryView.LAYOUT_TOP_TO_BOTTOM) {
        List({
          space: this.showPageInterval ? 8 : 0,
          initialIndex: this.currentPage,
          scroller: this.webtoonScroller
        }) {
          LazyForEach(this.dataSource, (ps: ReaderPageState) => {
            ListItem() {
              ReaderWebtoonPageView({
                pageState: ps,
                primaryColor: this.palette().colorPrimary,
                errorColor: this.palette().errorColor,
                progressTrackColor: this.palette().readerControlBg,
                onRetry: (): void => { this.reloadPage(ps.index); },
                onToggleControls: (): void => { this.controlsVisible = !this.controlsVisible; }
              })
            }
            .width('100%')
          }, (ps: ReaderPageState) => String(this.gid) + '_' + String(this.archiveSessionId) + '_wt_' + String(ps.index))
        }
        .width('100%')
        .height('100%')
        .cachedCount(3)
        .edgeEffect(EdgeEffect.Spring)
        .scale({ x: this.webtoonScale, y: this.webtoonScale })
        .onScrollIndex((start: number): void => {
          this.onWebtoonScrollIndex(start);
        })
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionStart((): void => {
              this.webtoonPinchStart = this.webtoonScale;
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.webtoonScale = Math.max(1.0, Math.min(3.0, this.webtoonPinchStart * event.scale));
            })
            .onActionEnd((): void => {
              if (this.webtoonScale <= 1.05) {
                this.getUIContext().animateTo({ duration: 150, curve: Curve.FastOutSlowIn }, (): void => {
                  this.webtoonScale = 1.0;
                });
              }
            })
        )
      } else {
        Swiper(this.swiperController) {
          LazyForEach(this.dataSource, (ps: ReaderPageState) => {
            ReaderSlideView({
              pageState: ps,
              fitCover: this.fitCover,
              zoomMultiplier: this.zoomed ? 2.0 : 1.0,
              zoomResetSeq: this.zoomResetSeq,
              primaryColor: this.palette().colorPrimary,
              errorColor: this.palette().errorColor,
              progressTrackColor: this.palette().readerControlBg,
              onRetry: (): void => { this.reloadPage(ps.index); },
              onToggleControls: (): void => {
                if (Date.now() - this.lastSwiperSwipeMs >= 250) {
                  this.controlsVisible = !this.controlsVisible;
                }
              },
              onTapLeft: (): void => { this.stepPageVisualLeft(); },
              onTapRight: (): void => { this.stepPageVisualRight(); },
              onZoomStateChange: (isZoomed: boolean): void => {
                this.currentPageZoomed = isZoomed;
              }
            })
          }, (ps: ReaderPageState) => String(this.gid) + '_' + String(this.archiveSessionId) + '_' + String(ps.index))
        }
        .index(this.initialSwiperIndex)
        .cachedCount(3)
        .loop(false)
        .indicator(false)
        .vertical(false)
        .duration(160)
        .curve(Curve.FastOutSlowIn)
        .disableSwipe(this.currentPageZoomed)
        .direction(this.readingDirection === GalleryView.LAYOUT_RIGHT_TO_LEFT ? Direction.Rtl : Direction.Ltr)
        .width('100%')
        .height('100%')
        .onGestureSwipe((): void => {
          this.lastSwiperSwipeMs = Date.now();
        })
        .onAnimationEnd((): void => {
          this.lastSwiperSwipeMs = 0;
        })
        .onChange((index: number) => {
          this.onSwiperPageChanged(index);
        })
      }

      if (!this.initializing && this.initError.length === 0 && !this.controlsVisible && !this.settingsDialogOpen) {
        Column() {
          GalleryHeader({
            marginH: ThemeDimens.GALLERY_WIDGET_MARGIN_H,
            marginV: ThemeDimens.GALLERY_WIDGET_MARGIN_V,
            cutoutTopOffset: this.cutoutTopVp,
            cutoutLeftOffset: this.cutoutLeftVp,
            cutoutRightOffset: this.cutoutRightVp,
            showBattery: this.showBattery,
            showProgress: this.showProgress,
            showClock: this.showClock,
            batteryBuilder: (): void => {
              this.headerBatterySlot();
            },
            progressBuilder: (): void => {
              this.headerProgressSlot();
            },
            clockBuilder: (): void => {
              this.headerClockSlot();
            }
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.controlsVisible && !this.initializing && this.initError.length === 0) {
        Column() {
          this.topOverlay()
          Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None)
          this.bottomOverlay()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.settingsDialogOpen) {
        this.readingSettingsDialog()
      }

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.computeLightnessMaskColor())
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().readerBackground)
    .focusable(true)
    .defaultFocus(true)
    .onKeyEvent((ev: KeyEvent) => {
      this.handleKeyEvent(ev);
    })
  }
}
