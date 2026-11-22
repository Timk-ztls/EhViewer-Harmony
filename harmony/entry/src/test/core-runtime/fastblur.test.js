// FastBlur 运行时应断言（纯算法：字节数组进、字节数组出）
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out7');
const { FastBlur } = require(path.join(OUT, 'FastBlur.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// 造一张 w*h 的图：fill(r,g,b,a)
const mk = (w, h, r, g, b, a) => {
  const px = new Uint8ClampedArray(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = a;
  }
  return px;
};

// 1) radius < 1 → 不做事，返回 false，像素不变
const px0 = mk(4, 4, 10, 20, 30, 255);
const before0 = Array.from(px0);
eq(FastBlur.doBlur(px0, 4, 4, 0), false, 'radius=0 → 返回 false（对应上游 return null）');
eq(Array.from(px0), before0, 'radius=0 → 像素不变');

// 2) 纯色图模糊后仍是同一颜色（Stack Blur 的定点性质）
const px1 = mk(8, 8, 120, 60, 200, 255);
eq(FastBlur.doBlur(px1, 8, 8, 3), true, 'radius=3 → 返回 true');
let same = true;
for (let i = 0; i < 64; i++) {
  if (px1[i * 4] !== 120 || px1[i * 4 + 1] !== 60 || px1[i * 4 + 2] !== 200 || px1[i * 4 + 3] !== 255) same = false;
}
eq(same, true, '纯色图模糊后颜色不变（R/G/B/A 全等）');

// 3) alpha 通道被保留（上游 `0xff000000 & pix[yi]` 的语义）
const px2 = mk(6, 6, 200, 100, 50, 255);
FastBlur.doBlur(px2, 6, 6, 2);
let alphaOk = true;
for (let i = 0; i < 36; i++) if (px2[i * 4 + 3] !== 255) alphaOk = false;
eq(alphaOk, true, '模糊后 alpha 保持 255（上游保留 alpha 通道）');

// 4) 黑白分界处的像素被"拉近"：左半黑、右半白的 1D 图，中间像素 r 应介于 0..255 之间
const w = 8, h = 1;
const px3 = new Uint8ClampedArray(w * h * 4);
for (let x = 0; x < w; x++) {
  const v = x < 4 ? 0 : 255;
  px3[x * 4] = v; px3[x * 4 + 1] = v; px3[x * 4 + 2] = v; px3[x * 4 + 3] = 255;
}
FastBlur.doBlur(px3, w, h, 2);
const mid = px3[3 * 4];       // x=3（黑区最后一位）
const mid2 = px3[4 * 4];      // x=4（白区第一位）
eq(mid > 0 && mid < 255, true, '分界像素被平滑（x=3 的 R 介于 0..255），实际=' + mid);
eq(mid2 > 0 && mid2 < 255, true, '分界像素被平滑（x=4 的 R 介于 0..255），实际=' + mid2);
eq(mid < mid2, true, '黑侧仍比白侧暗（梯度方向正确）');

// 5) 输入长度不足 → 直接返回 false（防御）
eq(FastBlur.doBlur(new Uint8ClampedArray(4), 4, 4, 2), false, '像素数组长度不足 → 返回 false 不崩');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
