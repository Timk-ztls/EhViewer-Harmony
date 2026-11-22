import { Rect } from '../../main/ets/hippo/lib/glview/util/Rect';
import { RectF } from '../../main/ets/hippo/lib/glview/util/RectF';
import { Color } from '../../main/ets/hippo/lib/glview/util/Color';
import { Matrix } from '../../main/ets/hippo/lib/glview/util/Matrix';
import { GLMath } from '../../main/ets/hippo/lib/glview/util/GLMath';
import { MotionEvent, PointerCoords } from '../../main/ets/hippo/lib/glview/util/MotionEvent';
import { GalleryUtils } from '../../main/ets/hippo/lib/glview/util/GalleryUtils';

let pass = 0; const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = typeof got === 'number' ? got.toFixed(6) : JSON.stringify(got);
  const w = typeof want === 'number' ? (want as number).toFixed(6) : JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void { if (cond) { pass++; } else { fails.push(name); } }

// --- Rect: AOSP 语义 ---
const r = new Rect(10, 20, 30, 40);
eq('Rect.width', r.width(), 20);
eq('Rect.height', r.height(), 20);
eq('Rect.centerX', r.centerX(), 20);
ok('Rect.isEmpty false', !r.isEmpty());
const empty = new Rect(5, 5, 5, 9);
ok('Rect.isEmpty left==right', empty.isEmpty());
const a = new Rect(0, 0, 100, 100);
ok('Rect.intersect hit', a.intersect(new Rect(50, 50, 200, 200)));
eq('Rect.intersect.left', a.left, 50);
eq('Rect.intersect.right', a.right, 100);
const b = new Rect(0, 0, 10, 10);
ok('Rect.intersect miss', !b.intersect(new Rect(20, 20, 30, 30)));
const u = new Rect(0, 0, 10, 10); u.union(new Rect(20, 20, 30, 30));
// AOSP union 是"扩展当前矩形"，不相交时得到 0,0,30,30
eq('Rect.union', [u.left, u.top, u.right, u.bottom], [0, 0, 30, 30]);
const srt = new Rect(30, 40, 10, 20); srt.sort();
eq('Rect.sort', [srt.left, srt.top, srt.right, srt.bottom], [10, 20, 30, 40]);
ok('Rect.contains', r.contains(15, 25) && !r.contains(30, 25));
const off = new Rect(0, 0, 10, 10); off.offset(5, -3);
eq('Rect.offset', [off.left, off.top, off.right, off.bottom], [5, -3, 15, 7]);

// --- RectF ---
const rf = new RectF(0, 0, 10, 20);
eq('RectF.centerY', rf.centerY(), 10);
const rfSub = new RectF(); rfSub.set(rf);
ok('RectF.set(RectF)', rfSub.equalsRectF(rf));
const rr = new Rect(); new RectF(-1.4, 2.5, 3.6, 4.5).round(rr);
eq('RectF.round', [rr.left, rr.top, rr.right, rr.bottom], [-1, 3, 4, 5]);

// --- Color ---
eq('Color.argb', Color.argb(255, 0x12, 0x34, 0x56), 0xFF123456 | 0);
eq('Color.alpha', Color.alpha(0xFF123456), 255);
eq('Color.red', Color.red(0xFF123456), 0x12);
eq('Color.lerp', Color.lerp(0xFF000000, 0xFFFFFFFF, 0.5), 0xFF808080 | 0);
eq('Color.setAlpha', Color.setAlpha(0xFF123456|0, 0x80), 0x80123456 | 0);

// --- Matrix (opengl 4x4) ---
const m: number[] = new Array<number>(16).fill(0);
Matrix.setIdentityM(m, 0);
eq('identity', m.join(','), '1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1');
Matrix.translateM(m, 0, 3, 4, 0);
eq('translate', [m[12], m[13], m[14]], [3, 4, 0]);
const ortho: number[] = new Array<number>(16).fill(0);
Matrix.orthoM(ortho, 0, 0, 100, 0, 200, -1, 1);
eq('ortho x', ortho[0], 0.02); eq('ortho y', ortho[5], 0.01);
eq('ortho tx', ortho[12], -1); eq('ortho ty', ortho[13], -1);
// multiplyMM: identity * translate == translate
const t: number[] = new Array<number>(16).fill(0); Matrix.setIdentityM(t, 0); Matrix.translateM(t, 0, 5, 6, 0);
const id: number[] = new Array<number>(16).fill(0); Matrix.setIdentityM(id, 0);
const out: number[] = new Array<number>(16).fill(0);
Matrix.multiplyMM(out, 0, t, 0, id, 0);
eq('multiplyMM id', [out[12], out[13]], [5, 6]);
// setRotateM 90° around Z: (1,0) -> (0,1)
const rot: number[] = new Array<number>(16).fill(0); Matrix.setRotateM(rot, 0, 90, 0, 0, 1);
const v: number[] = [1, 0, 0, 1]; const vr: number[] = new Array<number>(4).fill(0);
Matrix.multiplyMV(vr, 0, rot, 0, v, 0);
eq('rotate90 x', vr[0], 0); eq('rotate90 y', vr[1], 1);
// GLES20Canvas.translate 的内联优化必须与 Matrix.translateM 等价
const m1: number[] = new Array<number>(16).fill(0); Matrix.setIdentityM(m1, 0);
Matrix.translateM(m1, 0, 7, 9, 0);
const m2: number[] = new Array<number>(16).fill(0); Matrix.setIdentityM(m2, 0);
m2[12] += m2[0]*7 + m2[4]*9; m2[13] += m2[1]*7 + m2[5]*9;
eq('inline translate parity', [m2[12], m2[13]], [m1[12], m1[13]]);

// --- GLMath ---
eq('positiveModulo 350,360', GLMath.positiveModulo(350, 360), 350);
eq('positiveModulo -10,360', GLMath.positiveModulo(-10, 360), 350);
eq('nextPowerOf2 1000', GLMath.nextPowerOf2(1000), 1024);
eq('prevPowerOf2 1000', GLMath.prevPowerOf2(1000), 512);
eq('radians 180 (truncated pi)', GLMath.radians(180), 3.1415926);
// 上游圆顶点表：sin(radians(90/n*i)) 的 n=30 第一段必须与 Java float 一致
eq('circle vertex sin0', Math.sin(GLMath.radians(0)) / 2, 0);

// --- MotionEvent + GalleryUtils ---
const e = MotionEvent.obtainSimple(1000, 1016, MotionEvent.ACTION_DOWN | (1 << 8), 12.5, 33.5, 0);
eq('MotionEvent.getActionMasked', e.getActionMasked(), MotionEvent.ACTION_DOWN);
eq('MotionEvent.getActionIndex', e.getActionIndex(), 1);
eq('GalleryUtils roundtrip', GalleryUtils.floatARGBArrayTointColor(GalleryUtils.intColorToFloatARGBArray(0xFF123456|0)), 0xFF123456 | 0);
ok('GalleryUtils assert throws before set', (() => { try { GalleryUtils.assertInRenderThread(); return false; } catch (err) { return true; } })());
GalleryUtils.setRenderThread();
ok('GalleryUtils assert ok after set', (() => { GalleryUtils.assertInRenderThread(); return true; })());


// --- multiplyMM 与参考实现逐元素对比（随机矩阵，含平移/旋转/缩放） ---
function refMul(a: number[], b: number[]): number[] {
  const out = new Array<number>(16).fill(0);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) {
    let s = 0; for (let j = 0; j < 4; j++) s += a[j * 4 + r] * b[c * 4 + j];
    out[c * 4 + r] = s;
  }
  return out;
}
let seed = 12345;
function rnd(): number { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return (seed / 0x7fffffff) * 8 - 4; }
for (let iter = 0; iter < 200; iter++) {
  const A = new Array<number>(16).fill(0).map(() => rnd());
  const B = new Array<number>(16).fill(0).map(() => rnd());
  const got = new Array<number>(16).fill(0);
  Matrix.multiplyMM(got, 0, A, 0, B, 0);
  const want = refMul(A, B);
  let bad = -1;
  for (let k = 0; k < 16; k++) if (Math.abs(got[k] - want[k]) > 1e-9) { bad = k; break; }
  if (bad >= 0) { fails.push(`multiplyMM/ref iter=${iter} k=${bad} got=${got[bad]} want=${want[bad]}`); break; }
}
if (fails.length === 0) pass += 200;

// --- rotateM 原地左乘 = multiplyMM(R, m) ---
{
  const m = new Array<number>(16).fill(0); Matrix.setIdentityM(m, 0); Matrix.translateM(m, 0, 10, 20, 0);
  const m2 = m.slice();
  Matrix.rotateM(m, 0, 45, 0, 0, 1);
  const R = new Array<number>(16).fill(0); Matrix.setRotateM(R, 0, 45, 0, 0, 1);
  // AOSP rotateM 是**右乘**：m = m · R（不是 R · m）。
  // 依据：GLES20Canvas.rotate 里 Matrix.multiplyMM(temp,16, m,off, temp,0) 的结果拷贝回 m，
  // multiplyMM(result,lhs,rhs)=lhs·rhs，所以 temp16 = m·R。
  const want = refMul(m2, R);
  let okAll = true;
  for (let k = 0; k < 16; k++) if (Math.abs(m[k] - want[k]) > 1e-9) okAll = false;
  ok('rotateM == m*R', okAll);
}

// --- 3x3 仿射：postTranslate 与 mapPoints 一致 ---
{
  const mm = new Matrix(); mm.setRotate(30, 0, 0); mm.postTranslate(5, 7);
  const pts = [1, 0];
  mm.mapPoints(pts);
  const rad = 30 * Math.PI / 180;
  eq('affine mapPoints x', pts[0], Math.cos(rad) * 1 - Math.sin(rad) * 0 + 5);
  eq('affine mapPoints y', pts[1], Math.sin(rad) * 1 + Math.cos(rad) * 0 + 7);
  const inv = new Matrix();
  ok('affine invert ok', mm.invert(inv));
  const back = [pts[0], pts[1]];
  inv.mapPoints(back);
  ok('affine invert roundtrip', Math.abs(back[0] - 1) < 1e-9 && Math.abs(back[1]) < 1e-9);
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
// ---------- 3x3 post/pre 命名语义（AOSP：postX => M' = X·M，preX => M' = M·X） ----------
{
  const p = { x: 1, y: 0 };
  // postTranslate：平移落在设备空间 => 等效于 mapPoints 后再加 (dx,dy)
  const m1 = new Matrix(); m1.setRotate(30, 0, 0); m1.postTranslate(5, 7);
  const a = [p.x, p.y]; m1.mapPoints(a);
  const rad = 30 * Math.PI / 180;
  eq('postTranslate x', a[0], Math.cos(rad) + 5);
  eq('postTranslate y', a[1], Math.sin(rad) + 7);

  // preTranslate：平移落在输入空间 => 等效于先把点平移再映射
  const m2 = new Matrix(); m2.setRotate(30, 0, 0); m2.preTranslate(5, 7);
  const b = [p.x, p.y]; m2.mapPoints(b);
  eq('preTranslate x', b[0], Math.cos(rad) * (1 + 5) - Math.sin(rad) * (0 + 7));
  eq('preTranslate y', b[1], Math.sin(rad) * (1 + 5) + Math.cos(rad) * (0 + 7));

  // postScale 以支点缩放：支点自身不动
  const m3 = new Matrix(); m3.setTranslate(0, 0); m3.postScale(2, 2, 10, 10);
  const c = [10, 10]; m3.mapPoints(c);
  eq('postScale keeps pivot x', c[0], 10);
  eq('postScale keeps pivot y', c[1], 10);
  const d = [0, 0]; m3.mapPoints(d);
  eq('postScale about pivot x', d[0], -10);
  eq('postScale about pivot y', d[1], -10);

  // postRotate 以支点旋转 90°：支点不动，(pivot.x+10, pivot.y) -> (pivot.x, pivot.y+10)
  const m4 = new Matrix(); m4.postRotate(90, 10, 10);
  const e = [20, 10]; m4.mapPoints(e);
  eq('postRotate about pivot x', e[0], 10);
  eq('postRotate about pivot y', e[1], 20);

  // postConcat vs preConcat：左乘/右乘不可交换
  const t = new Matrix(); t.setTranslate(5, 0);
  const r = new Matrix(); r.setRotate(90, 0, 0);
  const post = new Matrix(); post.setTranslate(5, 0); post.postConcat(r);   // M' = R·T
  const pre = new Matrix(); pre.setTranslate(5, 0); pre.preConcat(r);   // M' = T·R
  const q1 = [0, 0]; post.mapPoints(q1);
  const q2 = [0, 0]; pre.mapPoints(q2);
  ok('postConcat != preConcat', Math.abs(q1[1] - q2[1]) > 1e-6);
}
