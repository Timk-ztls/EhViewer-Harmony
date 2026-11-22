/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/GalleryHeader.java（inventory S0296，上游 171 行）
 *
 * 上游：ViewGroup 里放三个子视图 battery / progress / clock，wrap_content 高度贴顶显示：
 *   battery  → 左对齐（marginLeft=12dp, marginTop=12dp）
 *   progress → 水平居中（marginTop=12dp）
 *   clock    → 右对齐（marginRight=12dp, marginTop=12dp）
 *   支持 DisplayCutout 安全区偏移与纯逻辑 GalleryHeaderLayout 单测辅助类。
 */
import { ThemeDimens } from '../../../common/theme/ThemeTokens';

export class NotchRect {
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
}

/** 单个子视图的布局结果（对位上游 Rect） */
export class ChildLayout {
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
}

/** 上游 measureChild + offsetVertically/getOffsetLeft/getOffsetRight 的纯算术（可单测） */
export class GalleryHeaderLayout {
  static readonly SLOT_BATTERY: number = 0;
  static readonly SLOT_PROGRESS: number = 1;
  static readonly SLOT_CLOCK: number = 2;

  notches: NotchRect[] = [];
  parentOffsetX: number = 0;
  parentOffsetY: number = 0;

  /** 上游 measureChild */
  measureChild(slot: number, childW: number, childH: number, width: number,
               paddingLeft: number, paddingRight: number,
               leftMargin: number, rightMargin: number, topMargin: number): ChildLayout {
    const out: ChildLayout = new ChildLayout();
    let left: number;
    if (slot === GalleryHeaderLayout.SLOT_BATTERY) {
      left = paddingLeft + leftMargin;
    } else if (slot === GalleryHeaderLayout.SLOT_PROGRESS) {
      left = paddingLeft + Math.floor((width - paddingLeft - paddingRight) / 2) - Math.floor(childW / 2);
    } else {
      left = width - paddingRight - rightMargin - childW;
    }
    out.left = left;
    out.top = topMargin;
    out.width = childW;
    out.height = childH;
    return out;
  }

  /** 上游 offsetVertically：与 notch 相交时整体下移 */
  offsetVertically(rect: ChildLayout): boolean {
    const screenLeft: number = rect.left + this.parentOffsetX;
    const screenTop: number = rect.top + this.parentOffsetY;
    const screenRight: number = screenLeft + rect.width;
    const screenBottom: number = screenTop + rect.height;
    let offset: number = 0;
    for (let i = 0; i < this.notches.length; i++) {
      const n: NotchRect = this.notches[i];
      const intersect: boolean = !(screenRight <= n.left || screenLeft >= n.right
        || screenBottom <= n.top || screenTop >= n.bottom);
      if (intersect) {
        const candidate: number = n.bottom - this.parentOffsetY;
        if (candidate > offset) {
          offset = candidate;
        }
      }
    }
    if (offset !== 0) {
      rect.top = offset;
      return true;
    }
    return false;
  }

  /** 上游 getOffsetLeft（与左侧 notch 相交时的水平内缩量） */
  getOffsetLeft(rect: ChildLayout): number {
    const screenLeft: number = rect.left + this.parentOffsetX;
    const screenTop: number = rect.top + this.parentOffsetY;
    const screenRight: number = screenLeft + rect.width;
    const screenBottom: number = screenTop + rect.height;
    let offset: number = 0;
    for (let i = 0; i < this.notches.length; i++) {
      const n: NotchRect = this.notches[i];
      const intersect: boolean = !(screenRight <= n.left || screenLeft >= n.right
        || screenBottom <= n.top || screenTop >= n.bottom);
      if (intersect) {
        const candidate: number = n.right - this.parentOffsetX;
        if (candidate > offset) {
          offset = candidate;
        }
      }
    }
    return offset;
  }

  /** 上游 getOffsetRight（与右侧 notch 相交时的水平内缩量） */
  getOffsetRight(rect: ChildLayout, width: number): number {
    const screenLeft: number = rect.left + this.parentOffsetX;
    const screenTop: number = rect.top + this.parentOffsetY;
    const screenRight: number = screenLeft + rect.width;
    const screenBottom: number = screenTop + rect.height;
    let offset: number = 0;
    for (let i = 0; i < this.notches.length; i++) {
      const n: NotchRect = this.notches[i];
      const intersect: boolean = !(screenRight <= n.left || screenLeft >= n.right
        || screenBottom <= n.top || screenTop >= n.bottom);
      if (intersect) {
        const candidate: number = this.parentOffsetX + width - n.left;
        if (candidate > offset) {
          offset = candidate;
        }
      }
    }
    return offset;
  }
}

@Component
export struct GalleryHeader {
  layout: GalleryHeaderLayout = new GalleryHeaderLayout();
  /** 保留既有尺寸 Prop 兼容外部/旧调用 */
  @Prop batteryWidth: number = 24;
  @Prop batteryHeight: number = 12;
  @Prop progressWidth: number = 100;
  @Prop progressHeight: number = 24;
  @Prop clockWidth: number = 48;
  @Prop clockHeight: number = 12;
  @Prop paddingLeftValue: number = 0;
  @Prop paddingRightValue: number = 0;

  /** 上游 activity_gallery.xml: gallery_widget_margin_h=12, gallery_widget_margin_v=12 + 刘海避让 */
  @Prop marginH: number = ThemeDimens.GALLERY_WIDGET_MARGIN_H;
  @Prop marginV: number = ThemeDimens.GALLERY_WIDGET_MARGIN_V;
  @Prop cutoutTopOffset: number = 0;
  @Prop cutoutLeftOffset: number = 0;
  @Prop cutoutRightOffset: number = 0;
  @Prop showBattery: boolean = true;
  @Prop showProgress: boolean = true;
  @Prop showClock: boolean = true;

  @BuilderParam batteryBuilder: () => void = this.empty;
  @BuilderParam progressBuilder: () => void = this.empty;
  @BuilderParam clockBuilder: () => void = this.empty;

  @Builder
  empty(): void {
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.showBattery) {
        Row() {
          this.batteryBuilder()
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({
          left: this.paddingLeftValue + this.cutoutLeftOffset + this.marginH,
          top: this.marginV + this.cutoutTopOffset
        })
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.showProgress) {
        Row() {
          this.progressBuilder()
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({
          top: this.marginV + this.cutoutTopOffset
        })
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.showClock) {
        Row() {
          this.clockBuilder()
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({
          right: this.paddingRightValue + this.cutoutRightOffset + this.marginH,
          top: this.marginV + this.cutoutTopOffset
        })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
