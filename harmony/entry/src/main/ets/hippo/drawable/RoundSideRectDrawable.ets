/**
 * 迁移自 app/src/main/java/com/hippo/drawable/RoundSideRectDrawable.java（inventory S0030，上游 73 行）
 *
 * 上游 onBoundsChange 的三种情形（逐条保留，包括"宽度<高度时什么都不画"这个上游的 TODO 现状）：
 *   width > height：height/2 为半径的"胶囊"——
 *       moveTo(right-radius, top)
 *       arcTo(RectF(right-height, top, right, bottom), -90, 180)   // 右端半圆
 *       lineTo(left+radius, bottom)
 *       arcTo(RectF(left, top, left+height, bottom), 90, 180)      // 左端半圆
 *       lineTo(right-radius, top)
 *   width == height：addCircle(center, width/2)
 *   width <  height：// TODO（上游什么都不加 → 空 path → 不绘制）
 *
 * ArkUI 对位：onBoundsChange ≡ onAreaChange；路径用 SVG 命令重建到 @State pathCmd：
 *   胶囊：M(left+r,top) L(right-r,top) A r,r 0 0 1 (right-r),bottom L(left+r,bottom) A r,r 0 0 1 (left+r),top Z
 *         （与上游两段 arcTo(-90,180) / (90,180) 的几何一致，sweep=1 对应顺时针）
 *   正方形：同样用两段半圆（等价 addCircle）
 *   宽<高：pathCmd 置空 → Path 不绘制任何东西（与上游空 path 一致，保留 TODO 语义且不擅自补实现）
 */
@Component
export struct RoundSideRectDrawable {
  @Prop color: ResourceColor = '#FF000000';
  @Prop alpha: number = 1.0;
  @State pathCmd: string = '';
  @State boxW: number = 0;
  @State boxH: number = 0;

  /** 上游 onBoundsChange：按当前 bounds 重建 path */
  private rebuild(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      this.pathCmd = '';
      return;
    }
    if (width > height) {
      const r: number = height / 2;
      const left: number = 0;
      const top: number = 0;
      const right: number = width;
      const bottom: number = height;
      this.pathCmd = `M${right - r},${top} L${right - r},${top} `
        + `A${r},${r} 0 0 1 ${right - r},${bottom} `
        + `L${left + r},${bottom} `
        + `A${r},${r} 0 0 1 ${left + r},${top} Z`;
    } else if (width === height) {
      const r: number = width / 2;
      const cx: number = width / 2;
      const cy: number = height / 2;
      this.pathCmd = `M${cx - r},${cy} a${r},${r} 0 1,0 ${2 * r},0 a${r},${r} 0 1,0 ${-2 * r},0`;
    } else {
      // 上游此处是 TODO：宽 < 高 时不绘制（保留同语义，不擅自补）
      this.pathCmd = '';
    }
  }

  build() {
    Shape() {
      if (this.pathCmd.length > 0) {
        Path()
          .commands(this.pathCmd)
          .fill(this.color)
          .stroke(Color.Transparent)
          .strokeWidth(0)
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.alpha)
    .antiAlias(true)
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.boxW = newValue.width as number;
      this.boxH = newValue.height as number;
      this.rebuild(this.boxW, this.boxH);
    })
  }
}
