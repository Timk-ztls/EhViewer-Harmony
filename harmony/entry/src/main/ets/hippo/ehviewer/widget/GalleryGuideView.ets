/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/GalleryGuideView.java（inventory S0295，上游 177 行）
 *
 * 上游：画廊详情页的**两步引导遮罩**（ViewGroup + 自绘分隔线 + 5 个提示 TextView）
 *   mStep：0 → 左右翻页/菜单/进度提示，分隔线在 w/3 与 2w/3；1 → 长按提示，分隔线在屏幕中线
 *   onClick → mStep++：`>= 2` 时结束并隐藏；否则 bind() 重建对应步骤
 *   绘制：`mPaint` 用 `guideTitleColor`、`stroke`、`gallery_guide_divider_width`；
 *         背景 `guideBackgroundColor`；`mPoints` 为 3*4 个 float（两条竖线或一条横线）
 *
 * ============================ 一手核对：本类**不负责"只显示一次" ============================
 * 类里没有 SharedPreferences / Settings 读取 —— **是否显示由调用方（GalleryDetailScene）决定**，
 * 本类只负责"点到第几步"。所以移植时不能把持久化塞进组件（那会与调用方重复判断）。
 *
 * 但调用方判"是否已看过"时会遇到三个状态，必须区分（Lead 陷阱 65：返回空串比返回 null 更隐蔽）：
 *   KEY_ABSENT   —— 键不存在（首次启动）→ **应该显示**
 *   READ_FAILED  —— 真读错误 → **报错，不要当作"已看过"或"未看过"**
 *   VALUE_READ   —— 读到了值 → 按值决定
 * 故提供 `GuideFlagDecision` 纯函数把三态映射成"显示/隐藏/报错"，由调用方使用。
 *
 * ArkUI 对位：Stack + Column/Row 渲染提示文字；分隔线用 `Divider` 或 Canvas 画线
 *   （上游 mPoints 是 2 条竖线的 6 点 + 1 条横线的 6 点，本实现按 step 直接排版）
 *   点击推进：整层点击 → nextStep()
 *
 * 差异（已登记 MR）：
 *   1) 上游 5 个 TextView 从两个 XML 布局 inflate 并按比例 layout；ArkUI 用 Flex/百分比宽度，
 *      实测需在 P5 截图比对文字换行位置（上游按 width/3 硬切，窄屏可能截断）
 *   2) 自绘分隔线（Paint.STROKE）→ `Divider`（颜色/宽度对位）；若截图有 1px 差异再改 Canvas
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.GalleryGuideView';

/**
 * 引导是否显示。
 *
 * ⚠ **三态已收敛（裁定 A）**：此前这里有 `GuideReadState { KEY_ABSENT, READ_FAILED, VALUE_READ }`
 * 与 `GuideFlagDecision { SHOW, HIDE, ERROR }` 六个枚举值 —— **上游不存在"读失败"这个可表示状态**：
 * ```
 * EhApplication.java:276   Settings.putGuideGallery(true);          // 升级后重置
 * GalleryActivity.java:457 if (Settings.getGuideGallery()) { … }    // 唯一的"要不要显示"判断
 * Settings.java:1339       getBoolean(KEY_GUIDE_GALLERY, DEFAULT_GUIDE_GALLERY)  // 读失败 → 返回默认值
 * GalleryGuideView.java    grep 'Settings' → 0 命中（它自己一次都不读）
 * ```
 * ⇒ 上游只有 `true/false`；`getBoolean` 读失败**返回默认值**（= 显示）。
 * 我们新增的 `ERROR` 第三态后果是实打实的：调用方按 `=== SHOW` 写 ⇒ 读失败时引导**永远不显示**，
 * 而上游此时**必然显示**。**为"上游不可表示"的状态新增枚举 = 改变默认行为，不是防御性编程。**
 *
 * 现在：`shouldShow(seen)` —— `seen` 的默认值由调用方按上游 `DEFAULT_GUIDE_GALLERY` 取（true = 显示）。
 */
export class GuideFlagDecision {
  /** 上游 `DEFAULT_GUIDE_GALLERY`：键缺失/读失败时的默认值 = **显示** */
  static readonly DEFAULT_SEEN: boolean = false;

  /** @param seen 是否已看过（键缺失或读失败 → 传 `GuideFlagDecision.DEFAULT_SEEN`） */
  static shouldShow(seen: boolean): boolean {
    return !seen;
  }
}

export class GalleryGuideState {
  /** 上游 mStep（0 / 1） */
  step: number = 0;
  /** 走到该步之后结束（上游 mStep >= 2 隐藏） */
  static readonly MAX_STEP: number = 1;

  /** 上游 onClick：推进；返回 true 表示引导结束（调用方隐藏并记录"已看过"） */
  nextStep(): boolean {
    this.step = this.step + 1;
    return this.step > GalleryGuideState.MAX_STEP;
  }

  isFinished(): boolean {
    return this.step > GalleryGuideState.MAX_STEP;
  }
}

@Component
export struct GalleryGuideView {
  state: GalleryGuideState = new GalleryGuideState();
  @Prop bgColor: ResourceColor = '#CC000000';
  @Prop titleColor: ResourceColor = '#FFFFFFFF';
  /** 分隔线颜色（上游 Paint.STROKE 用 titleColor 同色系；此处单列便于截图比对） */
  @Prop dividerColor: ResourceColor = '#FFFFFFFF';
  /** 引导结束后通知调用方（调用方据此隐藏 + 持久化"已看过"） */
  onFinish: () => void = () => {
  };
  @State rev: number = 0;

  aboutToAppear(): void {
    // 装配期检查（陷阱 52）：onFinish 未注入 → 引导点完不会消失也不会被记录，用户每次进来都看到
    if (this.onFinish === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG,
        '%{public}s', 'onFinish not injected — guide will never complete or be persisted');
    }
  }

  build() {
    Stack() {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.bgColor)

      if (this.state.step === 0) {
        // step 0：四宫格（上游 bind1 取 4 个子视图）
        //   left(0,0,w/3,h)  right(2w/3,0,w,h)  menu(w/3,0,2w/3,h/2)  progress(w/3,h/2,2w/3,h)
        // 文案全部走资源键（修 P1：此前硬编码中文，非中文用户看到中文且文案与上游不同）
        Stack() {
          // 三条分隔线（修 P2：上游 onDraw 里 drawLines(mPoints)，w/3 竖线、2w/3 竖线、h/2 横线）
          Divider().vertical(true).strokeWidth(1).color(this.dividerColor)
            .height('100%').position({ x: '33.3%', y: 0 })
          Divider().vertical(true).strokeWidth(1).color(this.dividerColor)
            .height('100%').position({ x: '66.6%', y: 0 })
          Divider().vertical(false).strokeWidth(1).color(this.dividerColor)
            .width('33.4%').position({ x: '33.3%', y: '50%' })

          Row() {
            Column() {
              Text($r('app.string.guide_gallery_left')).fontSize(14).fontColor(this.titleColor)
            }
            .width('33.3%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)

            Column() {
              // 中列**拆成上下两块**（修 P2：此前 menu 与 progress 共用一个 Text）
              Column() {
                Text($r('app.string.guide_gallery_menu')).fontSize(14).fontColor(this.titleColor)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height('50%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column() {
                Text($r('app.string.guide_gallery_progress')).fontSize(14).fontColor(this.titleColor)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height('50%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
            .width('33.4%')
            .height('100%')

            Column() {
              Text($r('app.string.guide_gallery_right')).fontSize(14).fontColor(this.titleColor)
            }
            .width('33.3%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
      } else if (this.state.step === 1) {
        // step 1：长按提示（分隔线在屏幕中线）
        Stack() {
          Divider().vertical(false).strokeWidth(1).color(this.dividerColor)
            .width('100%').position({ x: 0, y: '50%' })
          Column() {
            Text($r('app.string.guide_gallery_long_click')).fontSize(14).fontColor(this.titleColor)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (this.state.nextStep()) {
        this.onFinish();
      }
      this.rev = this.rev + 1;
    })
  }
}
