/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0487   上游: com/hippo/util/FastBlur.java（245 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/FastBlur.ets
 *
 * 【算法等价 · 容器不同】
 *   上游 `doBlur(Bitmap, radius, canReuseInBitmap)` 用 `bitmap.getPixels(int[] pix,...)` 取
 *   **ARGB int 数组** 做 Stack Blur（Stack Blur v1.0, Mario Klingemann），最后
 *   `(0xff000000 & pix[yi]) | (dv[rsum]<<16) | (dv[gsum]<<8) | dv[bsum]` 写回并保留 alpha。
 *   ArkTS 侧没有 `Bitmap.getPixels/setPixels` 的等价原地契约（PixelMap 要走
 *   `readPixelsToBuffer/writeBufferToPixels`，同步性也不同），故本实现：
 *     · 输入 **RGBA8888 字节数组**（`Uint8ClampedArray`，行优先）
 *     · 内部转成 **ARGB int 数组**后**逐行照搬**上游算法（`dv[]` 查表、`stack[div][3]`、
 *       `vmin[]` 复用、alpha 保留全部一致）
 *     · 结果再写回字节数组
 *   调用方负责 "PixelMap → 字节数组 → PixelMap" 的搬运。
 *
 * 上游三个重载：
 *   `doBlur(Context, View, View)`          —— 纯 UI（背景 View 截图）→ **不移植**，归 ui-widget
 *   `doBlur(Context, Bitmap, View, bool)`  —— 半 UI（截图 + downscale + 应用到 View）→ **不移植**
 *   `doBlur(Bitmap, int, boolean)`         —— **纯算法 → 本文件**
 *
 * 平台差异：
 *  1. `canReuseInBitmap`（是否拷贝输入）在本实现里**总是原地修改传入数组**；
 *     需要保留原件请调用方先 copy。
 *  2. 上游 `radius < 1` 返回 `null`；本实现返回 `false`（未做模糊），语义等价。
 *  3. `divsum = ((div + 1) >> 1)^2`、`dv` 表大小 `256 * divsum`，逐字照搬。
 */

export class FastBlur {

  /**
   * 对应上游 `doBlur(Bitmap, int, boolean)` 的算法部分。
   *
   * @param pixels RGBA8888 像素（行优先，长度 = w*h*4）；**原地修改**
   * @param w 宽（像素）
   * @param h 高（像素）
   * @param radius 模糊半径（< 1 不做任何事）
   * @returns 是否执行了模糊
   */
  static doBlur(pixels: Uint8ClampedArray, w: number, h: number, radius: number): boolean {
    if (radius < 1) {
      return false;
    }
    if (w <= 0 || h <= 0 || pixels.length < w * h * 4) {
      return false;
    }

    const wm: number = w - 1;
    const hm: number = h - 1;
    const wh: number = w * h;
    const div: number = radius + radius + 1;

    // RGBA8888 → ARGB int（上游 pix 的布局）
    const pix: number[] = new Array<number>(wh);
    for (let i = 0; i < wh; i++) {
      const p4: number = i * 4;
      pix[i] = (pixels[p4 + 3] << 24) | (pixels[p4] << 16) | (pixels[p4 + 1] << 8) | pixels[p4 + 2];
    }

    const r: number[] = new Array<number>(wh);
    const g: number[] = new Array<number>(wh);
    const b: number[] = new Array<number>(wh);
    const vmin: number[] = new Array<number>(Math.max(w, h));

    let divsum: number = (div + 1) >> 1;
    divsum *= divsum;
    const dv: number[] = new Array<number>(256 * divsum);
    for (let i = 0; i < 256 * divsum; i++) {
      dv[i] = Math.trunc(i / divsum);
    }

    let yw: number = 0;
    let yi: number = 0;

    const stack: number[][] = [];
    for (let i = 0; i < div; i++) {
      stack.push([0, 0, 0]);
    }
    let stackpointer: number;
    let stackstart: number;
    let sir: number[];
    let rbs: number;
    const r1: number = radius + 1;
    let routsum: number;
    let goutsum: number;
    let boutsum: number;
    let rinsum: number;
    let ginsum: number;
    let binsum: number;
    let rsum: number;
    let gsum: number;
    let bsum: number;
    let p: number;
    let yp: number;

    // ── 横向 ──
    for (let y = 0; y < h; y++) {
      rinsum = 0;
      ginsum = 0;
      binsum = 0;
      routsum = 0;
      goutsum = 0;
      boutsum = 0;
      rsum = 0;
      gsum = 0;
      bsum = 0;

      for (let i = -radius; i <= radius; i++) {
        p = pix[yi + Math.min(wm, Math.max(i, 0))];
        sir = stack[i + radius];
        sir[0] = (p & 0xff0000) >> 16;
        sir[1] = (p & 0x00ff00) >> 8;
        sir[2] = (p & 0x0000ff);
        rbs = r1 - Math.abs(i);
        rsum += sir[0] * rbs;
        gsum += sir[1] * rbs;
        bsum += sir[2] * rbs;
        if (i > 0) {
          rinsum += sir[0];
          ginsum += sir[1];
          binsum += sir[2];
        } else {
          routsum += sir[0];
          goutsum += sir[1];
          boutsum += sir[2];
        }
      }
      stackpointer = radius;

      for (let x = 0; x < w; x++) {
        r[yi] = dv[rsum];
        g[yi] = dv[gsum];
        b[yi] = dv[bsum];

        rsum -= routsum;
        gsum -= goutsum;
        bsum -= boutsum;

        stackstart = stackpointer - radius + div;
        sir = stack[stackstart % div];

        routsum -= sir[0];
        goutsum -= sir[1];
        boutsum -= sir[2];

        if (y === 0) {
          vmin[x] = Math.min(x + radius + 1, wm);
        }
        p = pix[yw + vmin[x]];

        sir[0] = (p & 0xff0000) >> 16;
        sir[1] = (p & 0x00ff00) >> 8;
        sir[2] = (p & 0x0000ff);

        rinsum += sir[0];
        ginsum += sir[1];
        binsum += sir[2];

        rsum += rinsum;
        gsum += ginsum;
        bsum += binsum;

        stackpointer = (stackpointer + 1) % div;
        sir = stack[stackpointer % div];

        routsum += sir[0];
        goutsum += sir[1];
        boutsum += sir[2];

        rinsum -= sir[0];
        ginsum -= sir[1];
        binsum -= sir[2];

        yi++;
      }
      yw += w;
    }

    // ── 纵向 ──
    for (let x = 0; x < w; x++) {
      rinsum = 0;
      ginsum = 0;
      binsum = 0;
      routsum = 0;
      goutsum = 0;
      boutsum = 0;
      rsum = 0;
      gsum = 0;
      bsum = 0;
      yp = -radius * w;

      for (let i = -radius; i <= radius; i++) {
        yi = Math.max(0, yp) + x;

        sir = stack[i + radius];

        sir[0] = r[yi];
        sir[1] = g[yi];
        sir[2] = b[yi];

        rbs = r1 - Math.abs(i);

        rsum += r[yi] * rbs;
        gsum += g[yi] * rbs;
        bsum += b[yi] * rbs;

        if (i > 0) {
          rinsum += sir[0];
          ginsum += sir[1];
          binsum += sir[2];
        } else {
          routsum += sir[0];
          goutsum += sir[1];
          boutsum += sir[2];
        }

        if (i < hm) {
          yp += w;
        }
      }
      yi = x;
      stackpointer = radius;

      for (let y = 0; y < h; y++) {
        // Preserve alpha channel: (0xff000000 & pix[yi])
        pix[yi] = (0xff000000 & pix[yi]) | (dv[rsum] << 16) | (dv[gsum] << 8) | dv[bsum];

        rsum -= routsum;
        gsum -= goutsum;
        bsum -= boutsum;

        stackstart = stackpointer - radius + div;
        sir = stack[stackstart % div];

        routsum -= sir[0];
        goutsum -= sir[1];
        boutsum -= sir[2];

        if (x === 0) {
          vmin[y] = Math.min(y + r1, hm) * w;
        }
        p = x + vmin[y];

        sir[0] = r[p];
        sir[1] = g[p];
        sir[2] = b[p];

        rinsum += sir[0];
        ginsum += sir[1];
        binsum += sir[2];

        rsum += rinsum;
        gsum += ginsum;
        bsum += binsum;

        stackpointer = (stackpointer + 1) % div;
        sir = stack[stackpointer];

        routsum += sir[0];
        goutsum += sir[1];
        boutsum += sir[2];

        rinsum -= sir[0];
        ginsum -= sir[1];
        binsum -= sir[2];

        yi += w;
      }
    }

    // ARGB int → RGBA8888 写回
    for (let i = 0; i < wh; i++) {
      const v: number = pix[i];
      const p4: number = i * 4;
      pixels[p4] = (v >> 16) & 0xff;
      pixels[p4 + 1] = (v >> 8) & 0xff;
      pixels[p4 + 2] = v & 0xff;
      pixels[p4 + 3] = (v >> 24) & 0xff;
    }
    return true;
  }
  // ── 上游**半 UI 重载**的合成配方（仅供 ui-widget 复刻观感，本文件不实现 UI）──────
  //
  // 上游 `doBlur(Context, Bitmap, View, boolean isDownScale)` 里除模糊算法外还有一段**合成参数**：
  // ```java
  // float scaleFactor = 1;  float radius = 20;
  // if (isDownScale) { scaleFactor = 8; radius = 2; }
  // Bitmap overlay = createBitmap(view.getMeasuredWidth()/scaleFactor, view.getMeasuredHeight()/scaleFactor, ARGB_8888);
  // canvas.translate(-view.getLeft()/scaleFactor, -view.getTop()/scaleFactor);
  // canvas.scale(1/scaleFactor, 1/scaleFactor);
  // paint.setFlags(Paint.FILTER_BITMAP_FLAG);
  // canvas.drawBitmap(bkg, 0, 0, paint);
  // ... blur(overlay, radius) ... view.setBackground(new BitmapDrawable(res, overlay));
  // ```
  // 即：**缩小 1/8 → 用 radius=2 模糊 → 再放大回视图尺寸当背景**。
  // 缩小再放大本身就是一次强降采样模糊，所以 radius 只需 2；这是"看起来糊且不慢"的关键配方。
  //
  // 这些常量放在这里而不是 ui-widget，是因为它们**与算法共同决定观感**；
  // ui-widget 若自行改数字，最终效果会与上游不一致（用户能看出来"模糊得太轻/太重"）。

  /** 上游 `isDownScale=false` 时的模糊半径 */
  static readonly COMPOSITE_RADIUS_FULL: number = 20;
  /** 上游 `isDownScale=true` 时的模糊半径 */
  static readonly COMPOSITE_RADIUS_DOWNSCALED: number = 2;
  /** 上游 `isDownScale=true` 时的缩小倍数（1/8） */
  static readonly COMPOSITE_SCALE_FACTOR: number = 8;
  /** 上游 `isDownScale=false` 时的缩小倍数（不缩） */
  static readonly COMPOSITE_SCALE_FACTOR_FULL: number = 1;

  /**
   * 给定 `isDownScale`，返回 `{scaleFactor, radius}` —— 上游那两个分支的**唯一**取值来源。
   * ui-widget 拼合成流程时应当调它，而不是自己写字面量。
   */
  static getCompositeParams(isDownScale: boolean): CompositeParams {
    if (isDownScale) {
      return new CompositeParams(8, 2);
    }
    return new CompositeParams(1, 20);
  }
}

/** 上游半 UI 重载里的两个合成参数 */
export class CompositeParams {
  /** 背景图缩小倍数 */
  scaleFactor: number;
  /** 缩小后使用的模糊半径 */
  radius: number;

  constructor(scaleFactor: number, radius: number) {
    this.scaleFactor = scaleFactor;
    this.radius = radius;
  }
}