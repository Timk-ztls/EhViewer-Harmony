/*
 * TextureUploader 单测
 *
 * 这个类错了**不报错，只是画面慢/卡/纹理永远不出现**：
 *   1) 配额 = 1 张/帧（不是"全部上完"），否则一次上床太多会掉帧
 *   2) 入队时若 `isContentValid()` 直接丢弃；出队后再判一次（可能被别的路径上过）
 *   3) 出队后「已有效」的分支**不消耗配额**
 *   4) 后台纹理上完立刻 `draw(canvas, 0, 0)` 热身
 *   5) clear() 必须把两个队列的 uploading 标记都清掉
 */

import { TextureUploader } from '../../main/ets/hippo/lib/glview/glrenderer/TextureUploader';
import { UploadedTexture } from '../../main/ets/hippo/lib/glview/glrenderer/UploadedTexture';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { GLIdleListener } from '../../main/ets/hippo/lib/glview/glrenderer/TiledTexture';
import { image } from '@kit.ImageKit';
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

/** 可控的假纹理：能记录 updateContent / draw 次数，并能切换「内容是否有效」。 */
class FakeTexture extends UploadedTexture {
  updates: number = 0;
  draws: number = 0;
  valid: boolean = false;
  name: string;

  constructor(name: string) {
    super(false);
    this.name = name;
  }

  protected onGetBitmap(): image.PixelMap {
    return {
      width: 1,
      height: 1,
      getImageInfoSync: (): Object => ({ size: { width: 1, height: 1 } }),
      release: (): void => { }
    } as Object as image.PixelMap;
  }

  protected onFreeBitmap(bitmap: image.PixelMap): void { }

  /** 覆盖 updateContent：只记次数并把内容标为有效（不碰 GL）。 */
  updateContent(canvas: GLCanvas): void {
    this.updates++;
    this.valid = true;
  }

  isContentValid(): boolean {
    return this.valid;
  }

  draw(canvas: GLCanvas, a: number | Object, b?: number | Object, c?: number, d?: number): void {
    this.draws++;
  }

  onBind(canvas: GLCanvas): boolean {
    return true;
  }

  getTarget(): number {
    return 0x0DE1;
  }

  isOpaque(): boolean {
    return false;
  }
}

/** 记录 requestRender / 监听注册的假 GLRoot。 */
class FakeRoot {
  renders: number = 0;
  listeners: GLIdleListener[] = [];

  addOnGLIdleListener(l: GLIdleListener): void {
    this.listeners.push(l);
  }

  requestRender(): void {
    this.renders++;
  }
}

// ---------------------------------------------------------------- 1. 入队与配额
{
  const root = new FakeRoot();
  const up = new TextureUploader(root);
  const canvas = new ExtCanvas() as Object as GLCanvas;

  const a = new FakeTexture('a');
  const b = new FakeTexture('b');
  up.addFgTexture(a);
  up.addFgTexture(b);
  eq('前台队列 2 个', up.fgSize(), 2);
  eq('已挂上 idle 监听', root.listeners.length, 1);
  eq('入队即标记 uploading', [a.isUploading(), b.isUploading()], [true, true]);

  // 一帧只上 1 张
  const keep = up.onGLIdle(canvas, false);
  eq('一帧只上 1 张', [a.updates, b.updates], [1, 0]);
  eq('上完的那张取消 uploading', a.isUploading(), false);
  eq('还在队列的保持 uploading', b.isUploading(), true);
  eq('前台还剩 1 张', up.fgSize(), 1);
  eq('消耗了配额 → requestRender 一次', root.renders, 1);
  eq('队列非空 → 返回 true（别摘监听）', keep, true);

  // 第二帧上完
  const keep2 = up.onGLIdle(canvas, false);
  eq('第二帧上完剩下的', b.updates, 1);
  eq('队列空 → 返回 false', keep2, false);
  ok('队列空后 isQueued = false', !up.isQueued());
}

// ---------------------------------------------------------------- 2. 内容已有效：入队就丢弃
{
  const root = new FakeRoot();
  const up = new TextureUploader(root);
  const t = new FakeTexture('valid');
  t.valid = true;
  up.addFgTexture(t);
  eq('内容已有效 → 不入队', up.fgSize(), 0);
  eq('也不挂监听', root.listeners.length, 0);
  eq('不标记 uploading', t.isUploading(), false);
}

// ---------------------------------------------------------------- 3. 出队后才发现已有效 → 不消耗配额
{
  const root = new FakeRoot();
  const up = new TextureUploader(root);
  const canvas = new ExtCanvas() as Object as GLCanvas;

  const stale = new FakeTexture('stale');
  const real = new FakeTexture('real');
  up.addFgTexture(stale);
  up.addFgTexture(real);
  // 模拟「别的路径先把它上完了」
  stale.valid = true;

  up.onGLIdle(canvas, false);
  eq('stale 被跳过（未 update）', stale.updates, 0);
  eq('配额没有浪费：real 也在同一帧上完', real.updates, 1);
  eq('队列清空', up.fgSize(), 0);
}

// ---------------------------------------------------------------- 4. 后台纹理：上床后立刻热身 draw
{
  const root = new FakeRoot();
  const up = new TextureUploader(root);
  const canvas = new ExtCanvas() as Object as GLCanvas;

  const fg = new FakeTexture('fg');
  const bg = new FakeTexture('bg');
  up.addFgTexture(fg);
  up.addBgTexture(bg);
  eq('前台 1 / 后台 1', [up.fgSize(), up.bgSize()], [1, 1]);

  // 第一帧：前台用掉唯一配额，后台没动
  up.onGLIdle(canvas, false);
  eq('第一帧只上前台', [fg.updates, bg.updates], [1, 0]);
  eq('后台还在队列', up.bgSize(), 1);

  // 第二帧：前台空了，配额给后台
  up.onGLIdle(canvas, false);
  eq('第二帧上后台', bg.updates, 1);
  eq('后台纹理上床后被热身 draw 一次', bg.draws, 1);
  eq('前台纹理不热身（draws 仍 0）', fg.draws, 0);
  eq('后台队列空', up.bgSize(), 0);

  // 没有任何消耗的帧不触发 requestRender
  const before = root.renders;
  up.onGLIdle(canvas, false);
  eq('空队列帧不 requestRender', root.renders, before);
}

// ---------------------------------------------------------------- 5. clear：两个队列的标记都清
{
  const root = new FakeRoot();
  const up = new TextureUploader(root);
  const fg = new FakeTexture('fg');
  const bg = new FakeTexture('bg');
  up.addFgTexture(fg);
  up.addBgTexture(bg);
  up.clear();
  eq('clear 后前台空', up.fgSize(), 0);
  eq('clear 后后台空', up.bgSize(), 0);
  eq('clear 取消 fg 的 uploading 标记', fg.isUploading(), false);
  eq('clear 取消 bg 的 uploading 标记', bg.isUploading(), false);
}

// ---------------------------------------------------------------- 6. 常量
{
  eq('QUOTA_PER_FRAME = 1', TextureUploader.QUOTA_PER_FRAME, 1);
  eq('INIT_CAPACITY = 64', TextureUploader.INIT_CAPACITY, 64);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('textureuploader 断言失败：' + fails.length);
}
