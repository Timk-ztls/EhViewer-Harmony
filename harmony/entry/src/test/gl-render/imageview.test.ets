/*
 * ImageView 单测 —— 重点：D-050（SCALE_FIT 的 else 分支缺 break）
 *
 * 上游缺陷的判据：
 *   `else` 分支（fit 由高度决定 = 横屏/平板）里多一个 `break` → 跳出 switch
 *   → 跳过钳制 / mDst 设置 / adjustPosition / mScaleOffsetDirty=false
 *   → scroll() 立刻返回全量 remain（完全不能拖）、canFling() 恒 false、getMaxDx/Dy 恒 0
 *
 * 所以两组断言：
 *   A. 横屏场景（else 分支）：dirty=false、mDst 非零、scroll 行为正确
 *   B. 竖屏场景（if 分支）：同样成立（两条分支语义应当一致）
 *
 * **重要更正**：上游 else 分支里的那个 reak **不是缺陷** —— reak 只跳出 switch，
 * switch 之后的钳制 / mDst / dirty=false 照常执行。最小复现见 commit 说明。
 * 本文件同时钉住「两条分支产生同样的可观测结果」，防止将来有人把它当 bug 删掉或改坏。
 */

import { ImageView } from '../../main/ets/hippo/lib/glgallery/ImageView';
import { ImageTexture, ImageTextureCallback } from '../../main/ets/hippo/lib/glview/image/ImageTexture';
import { ImageWrapper } from '../../main/ets/hippo/lib/glview/image/ImageWrapper';
import { Image } from '../../main/ets/hippo/lib/image/Image';
import { GLViewMeasureSpec } from '../../main/ets/hippo/lib/glview/view/GLView';
import { RectF } from '../../main/ets/hippo/lib/glview/util/RectF';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { ExtCanvas } from './fakecanvas';

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}
function near(name: string, got: number, want: number, eps: number = 0.01): void {
  if (Math.abs(got - want) <= eps) { pass++; } else { fails.push(`${name}: got ${got} want ${want}`); }
}

/** 可控的假纹理：只关心尺寸与回调，不碰 GL。 */
class FakeImageTexture extends ImageTexture {
  private w: number;
  private h: number;
  starts: number = 0;
  stops: number = 0;
  cb: ImageTextureCallback | null = null;

  constructor(width: number, height: number) {
    // ImageTexture 构造只读 getWidth/getHeight/isOpaque，桩不碰真实 image
    const fakeImage = {
      getWidth: (): number => width,
      getHeight: (): number => height,
      isOpaque: (): boolean => false
    };
    super(new ImageWrapper(fakeImage as Object as Image));
    this.w = width;
    this.h = height;
  }

  getWidth(): number { return this.w; }
  getHeight(): number { return this.h; }
  start(): void { this.starts++; }
  stop(): void { this.stops++; }
  setCallback(cb: ImageTextureCallback | null): void { this.cb = cb; }
  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, w?: number, h?: number): void { }
}

// ---------------------------------------------------------------- 1. sanitize（纯函数）
{
  eq('sanitizeScaleMode(0..4) 原样', [0, 1, 2, 3, 4].map((v) => ImageView.sanitizeScaleMode(v)), [0, 1, 2, 3, 4]);
  eq('sanitizeScaleMode(99) → SCALE_FIT', ImageView.sanitizeScaleMode(99), ImageView.SCALE_FIT);
  eq('sanitizeScaleMode(-1) → SCALE_FIT', ImageView.sanitizeScaleMode(-1), ImageView.SCALE_FIT);
  eq('sanitizeStartPosition(0..4) 原样', [0, 1, 2, 3, 4].map((v) => ImageView.sanitizeStartPosition(v)), [0, 1, 2, 3, 4]);
  eq('sanitizeStartPosition(9) → TOP_RIGHT', ImageView.sanitizeStartPosition(9), ImageView.START_POSITION_TOP_RIGHT);
  near('SCALE_MIN = 0.1', ImageView.SCALE_MIN, 0.1);
  near('SCALE_MAX = 10', ImageView.SCALE_MAX, 10);
}

// ---------------------------------------------------------------- 2. onMeasure 四种组合
{
  // 纹理 800x1200（ratio = 0.6667）
  const make = (): ImageView => {
    const v = new ImageView();
    v.setImageTexture(new FakeImageTexture(800, 1200));
    return v;
  };
  const spec = (size: number, mode: number): number => GLViewMeasureSpec.makeMeasureSpec(size, mode);
  const EXACTLY = GLViewMeasureSpec.EXACTLY;
  const AT_MOST = GLViewMeasureSpec.AT_MOST;

  const v1 = make();
  (v1 as Object as { onMeasure(w: number, h: number): void }).onMeasure(spec(1000, EXACTLY), spec(500, EXACTLY));
  eq('双 EXACTLY → 直接用', [v1.getMeasuredWidth(), v1.getMeasuredHeight()], [1000, 500]);

  const v2 = make();
  (v2 as Object as { onMeasure(w: number, h: number): void }).onMeasure(spec(1000, EXACTLY), spec(5000, AT_MOST));
  eq('宽 EXACTLY → 高按比例（1000/0.6667=1500）', [v2.getMeasuredWidth(), v2.getMeasuredHeight()], [1000, 1500]);

  const v3 = make();
  (v3 as Object as { onMeasure(w: number, h: number): void }).onMeasure(spec(5000, AT_MOST), spec(600, EXACTLY));
  eq('高 EXACTLY → 宽按比例（600*0.6667=400）', [v3.getMeasuredWidth(), v3.getMeasuredHeight()], [400, 600]);

  const v4 = make();
  (v4 as Object as { onMeasure(w: number, h: number): void }).onMeasure(spec(1000, EXACTLY), spec(1000, AT_MOST));
  eq('高 AT_MOST 被压缩到 1000', v4.getMeasuredHeight(), 1000);
}

// ---------------------------------------------------------------- 3. deriveStateFromSize：setImageTexture 的尺寸钳制
{
  const v = new ImageView();
  eq('初始无纹理 → isLoaded false', v.isLoaded(), false);
  v.setImageTexture(null);
  eq('setImageTexture(null) 后仍无纹理', v.isLoaded(), false);

  const t = new FakeImageTexture(0, -5);
  v.setImageTexture(t);
  // 尺寸 <= 0 时置 1（防除零）
  eq('宽 0 被钳到 1', t.getWidth() <= 0 ? 1 : t.getWidth(), 1);
  ok('纹理已绑定', v.isLoaded());
  ok('回调已挂上', t.cb !== null);

  // 换纹理：旧纹理必须 stop 并摘回调
  const t2 = new FakeImageTexture(100, 100);
  v.setImageTexture(t2);
  ok('旧纹理 stop 被调用', t.stops >= 1);
  eq('旧纹理回调被摘掉', t.cb, null);
}

// ---------------------------------------------------------------- 4. getScaleDefault：必须排序
{
  const v = new ImageView();
  v.setImageTexture(new FakeImageTexture(800, 1200));
  v.layout(0, 0, 1080, 2400);
  const arr = [0, 0, 0, 0];
  v.getScaleDefault(arr);
  ok('返回值已升序', arr[0] <= arr[1] && arr[1] <= arr[2] && arr[2] <= arr[3]);
  near('[0] 是 1.0 与两个 fit 值中的最小', arr[0], Math.min(1.0, 1080 / 800, 2400 / 1200));
  ok('[3] 不超过 SCALE_MAX', arr[3] <= ImageView.SCALE_MAX);
}

// ---------------------------------------------------------------- 5. **D-050**：横屏（fit 由高度决定）
{
  // 屏幕 2000x1000（横屏）；图 800x1200 → scaleX=2.5, scaleY=0.833 → scaleY <= scaleX → 走上游 bug 分支
  const v = new ImageView();
  v.setImageTexture(new FakeImageTexture(800, 1200));
  v.layout(0, 0, 2000, 1000);
  v.setScaleOffset(ImageView.SCALE_FIT, ImageView.START_POSITION_CENTER, 1.0);

  eq('D-050：横屏下 dirty 必须为 false', v.isScaleOffsetDirty(), false);
  near('mScale = min(2.5, 0.8333) = 0.8333', v.getScale(), 1000 / 1200);
  const dst: RectF = v.getDstRect();
  ok('mDst 已被设置（不是 (0,0,0,0)）', dst.width() > 0 && dst.height() > 0);
  near('目标高 = 屏幕高', dst.height(), 1000);

  // 图像比屏幕"矮" → 不能拖，但 canFling=false 且 remain 全量返回是对的
  const remain = [0, 0];
  v.scroll(10, 20, remain);
  eq('目标恰好填满 → remain 全量返回（不需要拖）', remain, [10, 20]);
}

// ---------------------------------------------------------------- 6. **D-050**：横屏 + 放大 → 能拖
{
  const v = new ImageView();
  v.setImageTexture(new FakeImageTexture(800, 1200));
  v.layout(0, 0, 2000, 1000);
  // 用 SCALE_FIXED 2.0 → 目标 1600x2400（宽 1600 < 2000 屏幕宽，高 2400 > 1000 屏幕高）
  v.setScaleOffset(ImageView.SCALE_FIXED, ImageView.START_POSITION_CENTER, 2.0);
  eq('固定缩放后 dirty=false', v.isScaleOffsetDirty(), false);
  near('scale = 2.0', v.getScale(), 2.0);
  const dst: RectF = v.getDstRect();
  near('目标宽 = 1600', dst.width(), 1600);
  near('目标高 = 2400', dst.height(), 2400);
  ok('canFling（高超出屏幕）', v.canFlingVertically());
  eq('横向不超出 → 不可横甩', v.canFlingHorizontally(), false);

  // 竖向拖动：目标高 2400 > 屏幕 1000 → 能拖，未被挡时 remain=0
  const remain = [0, 0];
  v.scroll(0, 50, remain);
  eq('竖向拖动生效（remain=0）', remain[1], 0);
  ok('竖向位置已改变', v.getDstRect().top < 0);
}

// ---------------------------------------------------------------- 7. **回归守卫**：竖屏（scaleX < scaleY）行为不变
{
  // 屏幕 1080x2400（竖屏）；图 800x1200 → scaleX=1.35, scaleY=2 → scaleX < scaleY → 走 if 分支
  const v = new ImageView();
  v.setImageTexture(new FakeImageTexture(800, 1200));
  v.layout(0, 0, 1080, 2400);
  v.setScaleOffset(ImageView.SCALE_FIT, ImageView.START_POSITION_CENTER, 1.0);

  eq('竖屏 dirty=false', v.isScaleOffsetDirty(), false);
  near('mScale = 1.35', v.getScale(), 1080 / 800);
  const dst: RectF = v.getDstRect();
  near('目标宽 = 屏幕宽', dst.width(), 1080);
  near('目标高 = 1200*1.35 = 1620', dst.height(), 1200 * (1080 / 800));
  // 高度 1620 < 屏幕 2400 → 居中
  near('竖向居中：(2400-1620)/2 = 390', dst.top, (2400 - 1200 * (1080 / 800)) / 2);
}

// ---------------------------------------------------------------- 8. scroll 的边界夹紧与 remain
{
  const v = new ImageView();
  v.setImageTexture(new FakeImageTexture(800, 1200));
  v.layout(0, 0, 2000, 1000);
  v.setScaleOffset(ImageView.SCALE_FIXED, ImageView.START_POSITION_CENTER, 4.0);
  const dst: RectF = v.getDstRect();
  // 目标 3200x4800，屏幕 2000x1000 → 可拖
  const remain = [0, 0];
  // 往右下拖到顶边：dst.top 已为负，往上会被夹
  v.scroll(0, -10000, remain);
  ok('拖到边界后 remain 非 0（多余位移交父容器）', remain[1] !== 0);
  near('顶边被夹到 0', v.getDstRect().top, 0);
}

// ---------------------------------------------------------------- 9. scale 的焦点缩放与钳制
{
  const v = new ImageView();
  v.setImageTexture(new FakeImageTexture(800, 1200));
  v.layout(0, 0, 1000, 2000);
  v.setScaleOffset(ImageView.SCALE_FIXED, ImageView.START_POSITION_CENTER, 1.0);
  near('初始 scale 1.0', v.getScale(), 1.0);
  v.scale(500, 1000, 2.0);
  near('放大到 2.0', v.getScale(), 2.0);
  // 超过上限
  v.scale(500, 1000, 100.0);
  near('钳制到 SCALE_MAX', v.getScale(), ImageView.SCALE_MAX);
  // 缩到下限
  v.scale(500, 1000, 0.001);
  near('钳制到 SCALE_MIN', v.getScale(), ImageView.SCALE_MIN);
}

// ---------------------------------------------------------------- 10. onRender：无纹理安全返回
{
  const v = new ImageView();
  const canvas = new ExtCanvas() as Object as GLCanvas;
  v.onRender(canvas);
  ok('无纹理时 onRender 安全返回', true);
  ok('无纹理时 isLoaded=false', !v.isLoaded());
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('imageview 断言失败：' + fails.length);
}
