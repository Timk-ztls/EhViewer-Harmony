/**
 * 迁移自 app/src/main/java/com/hippo/widget/ShadowLinearLayout.java（inventory S0543，上游 82 行）
 *
 * ============================ 一手核对：两条路径，其中一条是死代码 ============================
 * `init()`：
 *   `if (Build.VERSION.SDK_INT >= LOLLIPOP) { setOutlineProvider(BOUNDS); setElevation(dp2pix(2)); }`
 *   `else { setShadow((NinePatchDrawable) R.drawable.shadow_2dp); }`
 * ⇒ 在 API ≥ 21（本项目 minSdk 已远高于此）上，本类**就是"elevation = 2dp 的 LinearLayout"**。
 *   nine-patch 分支（mShadow / mShadowPaddings / updateShadowBounds / draw(canvas) 先画阴影）
 *   是 API < 21 的兼容路径 —— **鸿蒙没有该缺陷路径可兜**，属"平台缺陷路径不存在"（同 SafeCoordinatorLayout 的空 try/catch）。
 *
 * ============================ 判据：**完全重复 → 别名 + shadow 属性** ============================
 * 现代路径 = 线性布局 + elevation 2dp ⇒ ArkUI：`Column`/`Row`（按 orientation）+ `.shadow({...})`。
 * **不重写任何绘制**（nine-patch 路径不需要，elevation 由平台渲染）。
 *
 * 一处上游自承的缺陷（保留，A 类）：
 *   `// TODO not only 2dp` —— 高度写死 2dp，不跟主题/层级走。属显示层，照搬（改了不会更"对"，
 *   因为没有上游基准值可比；真要改应等主题体系落地后统一处理）。
 *
 * 差异（已登记 MR）：
 *   1) `setElevation(2dp)` → ArkUI `.shadow({ radius: 2vp, offsetY: 2vp })`。
 *      **视觉非严格等价**：像素级对齐需 P5 截图比对（两平台阴影扩散算法不同）—— 已知差异，待验证。
 *   2) `setOutlineProvider(BOUNDS)` → ArkUI 由组件 `clip` / 背景决定轮廓，无显式 API。
 *   3) nine-patch 兼容路径不移植（API<21 专用）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.ShadowLinearLayout';

export class ShadowLinearLayoutConst {
  /** 上游 `LayoutUtils.dp2pix(context, 2)` 的 dp 值（源码里写死 2，有 TODO 注明不只 2dp） */
  static readonly ELEVATION_DP: number = 2;
  /** 上游只有 VERTICAL/HORIZONTAL 两向（LinearLayout 的 orientation） */
  static readonly ORIENTATION_VERTICAL: number = 1;
  static readonly ORIENTATION_HORIZONTAL: number = 0;
}

/** 对位 LayoutUtils.dp2pix：dp × density → px（ArkUI 侧同式，便于断言） */
export class LayoutUtils {
  static dp2pix(dp: number, density: number): number {
    return dp * density;
  }
}

export class ShadowLinearLayoutState {
  orientation: number = ShadowLinearLayoutConst.ORIENTATION_VERTICAL;
  /** 上游 setElevation 的值（px）；构造期由 density 算出 */
  elevationPx: number = ShadowLinearLayoutConst.ELEVATION_DP;
  density: number = 1;

  init(density: number): void {
    this.density = density;
    this.elevationPx = LayoutUtils.dp2pix(ShadowLinearLayoutConst.ELEVATION_DP, density);
  }

  /** 阴影半径（vp）：用 elevation 的 dp 值，非 px（ArkUI 的 shadow 用 vp 表达） */
  shadowRadius(): number {
    return ShadowLinearLayoutConst.ELEVATION_DP;
  }

  /** 阴影 Y 偏移（vp）：Material elevation 的阴影主要向下扩散 */
  shadowOffsetY(): number {
    return ShadowLinearLayoutConst.ELEVATION_DP;
  }
}

@Component
export struct ShadowLinearLayout {
  state: ShadowLinearLayoutState = new ShadowLinearLayoutState();
  /** 对位 LinearLayout orientation：'vertical' / 'horizontal' */
  @Prop vertical: boolean = true;
  /** 上游写死 2dp 的阴影（TODO not only 2dp，见文件头） */
  @Prop shadowColor: ResourceColor = '#33000000';
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty(): void {
  }

  aboutToAppear(): void {
    if (this.content === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'content builder not provided — layout will be empty');
    }
  }

  build() {
    if (this.vertical) {
      Column() {
        this.content()
      }
      .width('100%')
      .shadow({
        radius: this.state.shadowRadius(),
        color: this.shadowColor,
        offsetX: 0,
        offsetY: this.state.shadowOffsetY()
      })
    } else {
      Row() {
        this.content()
      }
      .width('100%')
      .shadow({
        radius: this.state.shadowRadius(),
        color: this.shadowColor,
        offsetX: 0,
        offsetY: this.state.shadowOffsetY()
      })
    }
  }
}
