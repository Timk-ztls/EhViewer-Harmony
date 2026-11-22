/**
 * 迁移自 app/src/main/java/com/hippo/drawable/WrapDrawable.java（inventory S0033，上游 118 行）
 *
 * 上游是一个**纯委托包装器**：持有 mDrawable，把 setBounds/setAlpha/setColorFilter/
 * setDither/setFilterBitmap/setChangingConfigurations 等全部转发给它，draw 时直接画内层；
 * updateBounds() = setBounds(0, 0, intrinsicWidth, intrinsicHeight)。
 *
 * ArkUI 对位：ArkTS 侧没有 Drawable 体系，等价物是「持有子绘制器/图片源的包装类」：
 *   本文件保留 **同一个转发契约**（setDrawable/getDrawable/updateBounds/alpha/colorFilter 状态），
 *   渲染由包装组件 `WrapDrawable` 把子内容铺满自身（`@BuilderParam content`）。
 *   这样 UnikeryDrawable（下一个文件）里的"setDrawable(null) 清空"等语义可以 1:1 表达。
 *
 * 差异：上游能包装任意 Drawable 并参与 View 的 setBackground/setImageDrawable；
 *   ArkUI 无该容器概念，包装的是"内容槽"，与渲染层解耦（已登记 MR）。
 */
export class WrapDrawableModel {
  /** 上游 mDrawable 的存在性 */
  hasDrawable: boolean = false;
  /** 上游 setBounds 的四个值（转发给子 drawable） */
  left: number = 0;
  top: number = 0;
  right: number = 0;
  bottom: number = 0;
  alpha: number = 255;
  dither: boolean = true;
  filterBitmap: boolean = false;

  setDrawable(present: boolean): void {
    this.hasDrawable = present;
  }

  getDrawablePresent(): boolean {
    return this.hasDrawable;
  }

  setBounds(left: number, top: number, right: number, bottom: number): void {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
  }

  /** 上游 updateBounds()：用 intrinsic 尺寸重设 bounds */
  updateBounds(intrinsicWidth: number, intrinsicHeight: number): void {
    this.setBounds(0, 0, intrinsicWidth, intrinsicHeight);
  }

  boundsWidth(): number {
    return this.right - this.left;
  }

  boundsHeight(): number {
    return this.bottom - this.top;
  }
}

@Component
export struct WrapDrawable {
  model: WrapDrawableModel = new WrapDrawableModel();
  @BuilderParam content: () => void = this.empty;
  /** 上游 getOpacity() = TRANSLUCENT 的等价：允许半透明层 */
  @Prop translucent: boolean = true;

  @Builder
  empty(): void {
  }

  build() {
    Stack() {
      if (this.model.getDrawablePresent()) {
        this.content()
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.model.alpha / 255)
  }
}
