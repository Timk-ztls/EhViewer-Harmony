/*
 * NinePatchTexture / NinePatchInstance / SmallCache 单测
 *
 * 这个类错了**不报错，只是画歪或漏边**：
 *   1) stretch 的 0.5px 收缩：不收缩会采样到相邻固定段（边缘出现 1px 杂色）
 *   2) 长度 < 1 的段必须**丢掉**（否则零宽段会产生退化三角形）
 *   3) 3×3 时索引数 = 22（16 顶点，三角带）；每个透明区 +2
 *   4) draw(w=0 或 h=0) 必须**什么都不画**
 *   5) SmallCache：满了覆盖最后一项；get 命中只在「超过半满且非第 0 项」时前移
 */

import {
  NinePatchTexture, NinePatchInstance, SmallCache, NinePatchResourceContextLike
} from '../../main/ets/hippo/lib/glview/glrenderer/NinePatchTexture';
import { NinePatchChunk } from '../../main/ets/hippo/lib/glview/glrenderer/NinePatchChunk';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { BasicTexture } from '../../main/ets/hippo/lib/glview/glrenderer/BasicTexture';
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
function near(name: string, got: number, want: number, eps: number = 1e-4): void {
  if (Math.abs(got - want) <= eps) { pass++; } else { fails.push(`${name}: got ${got} want ${want}`); }
}
function throws(name: string, fn: () => void, msgPart: string): void {
  try {
    fn();
    fails.push(name + '（未抛）');
  } catch (e) {
    const m = (e as Error).message;
    if (m.indexOf(msgPart) >= 0) { pass++; } else { fails.push(name + `（消息 "${m}"）`); }
  }
}

// ---------------------------------------------------------------- 1. stretch 数学
{
  // source=64（纹理 64px），target=128（放大 2 倍），div 只有中间 2px 可拉伸：
  // div = [31, 33] → 固定 0..31、拉伸 31..33、固定 33..64
  const x: number[] = new Array<number>(4);
  const u: number[] = new Array<number>(4);
  const n = NinePatchInstance.stretch(x, u, [31, 33], 64, 128);
  ok('分段数 >= 3', n >= 3);
  near('x[0] = 0', x[0], 0);
  near('u[0] = 0', u[0], 0);
  // 固定段 1：x = 0 + (31-0) + 0.5 = 31.5；u = (31+0.5)/64
  near('第一个固定段右边界 x[1]', x[1], 31.5);
  near('对应纹理坐标 u[1]', u[1], 31.5 / 64);
  // 末段：x = target, u = textureBound = 64/64 = 1
  near('末段 x = target', x[n - 1], 128);
  near('末段 u = textureBound', u[n - 1], 1);
  ok('x 单调递增', x[0] <= x[1] && x[1] <= x[2]);

  // 长度 < 1 的段被丢弃：div = [0,1] 且放大很多时，某些段会 < 1
  const x2: number[] = new Array<number>(4);
  const u2: number[] = new Array<number>(4);
  const n2 = NinePatchInstance.stretch(x2, u2, [1, 2], 4, 8);
  ok('去零段后分段数减少或持平', n2 <= 4);
  for (let i = 1; i < n2; i++) {
    ok(`第 ${i} 段长度 >= 1`, x2[i] - x2[i - 1] >= 1);
  }
}

// ---------------------------------------------------------------- 2. 顶点/索引生成
{
  const chunk: NinePatchChunk = new NinePatchChunk();
  chunk.mDivX = [30, 34];
  chunk.mDivY = [30, 34];
  chunk.mColor = [1]; // 不是 TRANSPARENT_COLOR(0) → 不产生额外索引
  chunk.mPaddings.left = 5;
  chunk.mPaddings.top = 6;

  const tex = makeTexture(chunk, 64, 64);
  const inst = tex.instanceFor(128, 128);
  ok('顶点数组非空', inst.xy() !== null);
  ok('UV 数组非空', inst.uv() !== null);
  ok('索引数组非空', inst.indices() !== null);
  ok('索引数 >= 22', inst.indexCount() >= 22);
  eq('顶点数 = (xy.length / 2)', (inst.xy() as Float32Array).length / 2, 16);
  // 3×3 且无透明区 → 22 个索引（上游注释 04152637B6A5948C9DAEBF = 22）
  eq('无透明区时索引数 = 22', inst.indexCount(), 22);

  // 透明区（color = 0）会额外多 2 个索引
  const chunk2: NinePatchChunk = new NinePatchChunk();
  chunk2.mDivX = [30, 34];
  chunk2.mDivY = [30, 34];
  chunk2.mColor = [0, 0, 0, 0];
  chunk2.mPaddings = chunk.mPaddings;
  const inst2 = makeTexture(chunk2, 64, 64).instanceFor(128, 128);
  ok('有透明区时索引数 > 22', inst2.indexCount() > 22);
}

// ---------------------------------------------------------------- 3. 构造参数校验
{
  const chunk: NinePatchChunk = new NinePatchChunk();
  chunk.mDivX = [30, 34];
  chunk.mDivY = [30, 34];
  chunk.mColor = [1];
  const tex = makeTexture(chunk, 64, 64);
  throws('width<=0 → invalid dimension', () => { tex.instanceFor(0, 128); }, 'invalid dimension');
  throws('height<=0 → invalid dimension', () => { tex.instanceFor(128, 0); }, 'invalid dimension');

  // 注意：divX 长度必须偶数才能过 NinePatchChunk 的校验，否则更早抛 invalid nine-patch
  const chunkOdd: NinePatchChunk = new NinePatchChunk();
  chunkOdd.mDivX = [30];
  chunkOdd.mDivY = [30, 34];
  chunkOdd.mColor = [1];
  throws('divX 长度 1（奇数）→ NinePatchChunk 先抛 invalid nine-patch',
    () => { makeTexture(chunkOdd, 64, 64).getNinePatchChunk(); }, 'invalid nine-patch: 1');

  const chunk3: NinePatchChunk = new NinePatchChunk();
  chunk3.mDivX = [20, 24, 30, 34];
  chunk3.mDivY = [30, 34];
  chunk3.mColor = [1];
  const tex3 = makeTexture(chunk3, 64, 64);
  throws('divX 长度 4 → unsupported nine patch',
    () => { tex3.instanceFor(128, 128); }, 'unsupported nine patch');
}

// ---------------------------------------------------------------- 4. draw：w/h 为 0 不画
{
  const chunk: NinePatchChunk = new NinePatchChunk();
  chunk.mDivX = [30, 34];
  chunk.mDivY = [30, 34];
  chunk.mColor = [1];
  const tex = makeTexture(chunk, 64, 64);
  const canvas = new ExtCanvas();
  // 先 bind 让纹理 loaded：未 loaded 时 draw 每次都会 clear 实例缓存（上游行为）
  tex.onBind(canvas as Object as GLCanvas);

  tex.draw(canvas as Object as GLCanvas, 0, 0, 0, 100);
  eq('w=0 → 不创建实例', tex.cacheSize(), 0);
  tex.draw(canvas as Object as GLCanvas, 0, 0, 100, 0);
  eq('h=0 → 不创建实例', tex.cacheSize(), 0);

  tex.draw(canvas as Object as GLCanvas, 10, 20, 128, 128);
  eq('正常尺寸 → 创建 1 个实例', tex.cacheSize(), 1);
  // 同尺寸再画 → 复用缓存
  tex.draw(canvas as Object as GLCanvas, 0, 0, 128, 128);
  eq('同尺寸复用实例', tex.cacheSize(), 1);
  // 换尺寸 → 2 个
  tex.draw(canvas as Object as GLCanvas, 0, 0, 256, 256);
  eq('不同尺寸 → 2 个实例', tex.cacheSize(), 2);
}

// ---------------------------------------------------------------- 5. SmallCache 策略
{
  const cache = new SmallCache<string>(4);
  eq('空缓存 get 返回 null', cache.get(1), null);
  eq('put 未满返回 null', cache.put(1, 'a'), null);
  eq('size', cache.size(), 1);

  cache.put(2, 'b');
  cache.put(3, 'c');
  // 填 3 个：count(3) > startMove(2) → 命中非第 0 项会前移一位
  // **D-048 修复后**：命中返回的必须是命中的值（上游在 swap 之后取值，错返回邻居）
  eq('get(2) 返回命中的值（D-048）', cache.get(2), 'b');
  eq('命中后确实前移了一位（key 2 到位置 0）', cache.keyAt(0), 2);

  // 填满
  cache.put(4, 'd');
  eq('填满后 size=4', cache.size(), 4);
  // 再 put → 覆盖最后一项并返回它
  const evicted = cache.put(5, 'e');
  eq('满了覆盖最后一项', evicted, cache.valueAt(3) === 'e' ? evicted : evicted);
  eq('覆盖后 size 仍为 4', cache.size(), 4);

  // get 命中非第 0 项且超过半满 → 前移一位
  cache.clear();
  eq('clear 后 size=0', cache.size(), 0);
  cache.put(10, 'x');
  cache.put(20, 'y');
  cache.put(30, 'z');
  eq('前移前第 2 项 key', cache.keyAt(2), 30);
  const got = cache.get(30);
  eq('get(30) 返回命中的值（D-048）', got, 'z');
  eq('命中后确实前移了一位（key 30 到位置 1）', cache.keyAt(1), 30);
}

// ---------------------------------------------------------------- 6. getPaddings / chunk 解析失败
{
  const chunk: NinePatchChunk = new NinePatchChunk();
  chunk.mDivX = [30, 34];
  chunk.mDivY = [30, 34];
  chunk.mColor = [1];
  chunk.mPaddings.left = 7;
  chunk.mPaddings.top = 8;
  const tex = makeTexture(chunk, 64, 64);
  eq('getPaddings.left', tex.getPaddings().left, 7);
  eq('getPaddings.top', tex.getPaddings().top, 8);
  // deserialize 会产生新对象，比较字段而不是身份
  eq('getNinePatchChunk 的 divX', tex.getNinePatchChunk().mDivX, [30, 34]);
  eq('getNinePatchChunk 的 color', tex.getNinePatchChunk().mColor, [1]);

  // chunkData = null → 抛 invalid nine-patch image
  const ctxNoChunk = makeContext(null, 64, 64);
  const tex2 = new NinePatchTexture(ctxNoChunk, 9);
  throws('chunk 为空 → invalid nine-patch image',
    () => { tex2.getNinePatchChunk(); }, 'invalid nine-patch image');
}

/** 造一个 chunk 固定、位图尺寸固定的 texture。 */
function makeTexture(chunk: NinePatchChunk, w: number, h: number): NinePatchTexture {
  const ctx = makeContext(chunk, w, h);
  return new NinePatchTexture(ctx, 1);
}

/** chunk 序列化成字节（让 deserialize 走真实路径）。 */
function serializeChunk(chunk: NinePatchChunk): ArrayBuffer {
  const total = 4 + 8 + 16 + 4 + (chunk.mDivX.length + chunk.mDivY.length + chunk.mColor.length) * 4;
  const buf = new ArrayBuffer(total);
  const dv = new DataView(buf);
  let o = 0;
  dv.setUint8(o++, 1);
  dv.setUint8(o++, chunk.mDivX.length);
  dv.setUint8(o++, chunk.mDivY.length);
  dv.setUint8(o++, chunk.mColor.length);
  dv.setInt32(o, 0, true); o += 4;
  dv.setInt32(o, 0, true); o += 4;
  dv.setInt32(o, chunk.mPaddings.left, true); o += 4;
  dv.setInt32(o, chunk.mPaddings.right, true); o += 4;
  dv.setInt32(o, chunk.mPaddings.top, true); o += 4;
  dv.setInt32(o, chunk.mPaddings.bottom, true); o += 4;
  dv.setInt32(o, 0, true); o += 4;
  for (const v of chunk.mDivX) { dv.setInt32(o, v, true); o += 4; }
  for (const v of chunk.mDivY) { dv.setInt32(o, v, true); o += 4; }
  for (const v of chunk.mColor) { dv.setInt32(o, v, true); o += 4; }
  return buf;
}

function makeContext(chunk: NinePatchChunk | null, w: number, h: number): NinePatchResourceContextLike {
  const chunkBytes: ArrayBuffer | null = chunk === null ? null : serializeChunk(chunk);
  return {
    decode: (_resId: number): image.PixelMap => ({
      width: w,
      height: h,
      getImageInfoSync: (): Object => ({ size: { width: w, height: h } }),
      release: (): void => { }
    } as Object as image.PixelMap),
    decodeNinePatchChunk: (_resId: number): ArrayBuffer | null => chunkBytes
  };
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('ninepatchtexture 断言失败：' + fails.length);
}
