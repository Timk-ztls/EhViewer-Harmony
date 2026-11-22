/**
 * 迁移自 app/src/main/java/com/hippo/widget/AvatarImageView.java（inventory S0511，上游 540 行）
 *
 * ============================ 先说一个会影响 BitmapPool 结论的事实 ============================
 * **上游 AvatarImageView 根本不使用 BitmapPool**。它每次 onDraw 直接 `Bitmap.createBitmap` 三次：
 *   drawableToBitmap() → reSizeImage()/reSizeImageC() → createCircleImage()/createRoundImage()
 * 即「每个头像、每一帧」分配 3 个 w×h×ARGB_8888 的中间位图（540×540 时 ≈1.17 MB/个 → 约 3.5 MB/帧），
 * 且这些中间位图在方法返回后即可回收 —— 这是上游的既有实现，也是它 GC 压力的来源之一。
 *
 * ArkUI 对位：**一个中间位图都不需要**。圆角/圆形由渲染层的裁剪完成：
 *   mIsCircle → `.clipShape(new Circle())`；否则 → `.borderRadius(mRadius)`
 * 于是本控件对 BitmapPool 的占用是 **0**（不是"容量 4 够不够"的问题，而是这条路径不分配）。
 *
 * ============================ 状态机 ============================
 * 与 LoadImageViewNew 完全同构（retryType / clip / attach-detach 重发 / 失败占位 / 300ms 淡入），
 * 故直接**组合** `LoadImageControllerNew`（它是 LoadImageController 的能力子集），不复制状态机。
 *
 * 差异（已登记 MR）：
 *   1) 上游 `attrs android:src` 直接 decode 成 mSrcBitmap 作为占位图 → ArkUI 用 `@Prop placeholderSrc`
 *      （资源由 ui-scene 以 `$r('app.media.xxx')` 传入），语义一致（占位图先显示，加载完成后替换）。
 *   2) 上游圆形/圆角是**位图级裁剪**（生成新 Bitmap）；ArkUI 是**渲染级裁剪**（不改像素）。
 *      视觉等价，但 ArkUI 版不产生中间位图 → 内存与 GC 行为优于上游（这是平台红利，不是偷懒）。
 *   3) 上游 onDraw 里 `super.onDraw(canvas)` 的兜底（drawable 为 null 时）→ 本实现显示占位图/失败图。
 */
import { ThemeTokens } from '../../common/theme/ThemeTokens';
import { LoadImageControllerNew } from './LoadImageViewNew';
import { LoadImageHostBridge, ImageRequestHost } from './LoadImageView';
import { PreviewTarget } from '../ehviewer/client/data/PreviewSet';

@Component
export struct AvatarImageView {
  /** 复用 New 版状态机（retryType/clip/淡入/失败 全在其中） */
  controller: LoadImageControllerNew = new LoadImageControllerNew();
  /** 上游 R.styleable.LoadImageView_image_radius（dp） */
  @Prop imageRadius: number = 0;
  /** 上游 R.styleable.LoadImageView_image_circle */
  @Prop imageCircle: boolean = false;
  /** 上游 attrs android:src 的占位图（资源由调用方传入） */
  @Prop placeholderSrc: string = '';
  @Prop failureText: string = '!';
  @Prop failureTextColor: ResourceColor = '';
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

  /** 占位图 / 实际图 / 失败图 三态（对位上游 onDraw 的 drawable 判定） */
  @Builder
  contentBuilder(): void {
    if (this.showFailure) {
      Text(this.failureText)
        .fontSize(24)
        .fontColor(this.effectiveFailureColor())
    } else if (this.imageSrc.length > 0) {
      Image(this.imageSrc)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(this.imageAlpha)
    } else if (this.placeholderSrc.length > 0) {
      Image(this.placeholderSrc)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
  }

  build() {
    Stack() {
      this.contentBuilder()
    }
    .width('100%')
    .height('100%')
    .clipShape(this.imageCircle ? new Circle({ width: '100%', height: '100%' }) : new Rect({ width: '100%', height: '100%' }).radius(this.imageRadius))
  }
}
