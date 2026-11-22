/*
 * download-sync 纯逻辑单测：速度平滑与剩余时间估算（`SpeedReminder.run()`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 这两条公式直接决定用户看到的"速度"和"剩余时间"。写错了既不报错也不崩，
 * 只是**数字看着不对** —— 真机验收也看不出 1.3 倍偏差，所以只能靠断言。
 *
 * 上游口径（`SpeedReminder.run()`）：
 *   1. 一秒两次采样 → `newSpeed = bytesRead / 2`；首次直接用，之后 `lerp(old, new, 0.75)`
 *   2. `total <= 0` → remaining = -1（UI 显示"--"）
 *   3. `speed == 0` → remaining = 占位值（不是无穷大也不是 -1）
 *   4. 剩余字节 = Σ(contentLength - receivedSize)
 *      + Σ(contentLength) * (total - downloaded - n) / n
 *      ← 最后这项按"当前 n 页的平均大小"外推剩余页，去掉会让剩余时间系统性偏小
 */

import { SpeedMath } from '../../main/ets/hippo/ehviewer/download/DownloadManager';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function near(name: string, got: number, want: number, eps: number): void {
  if (Math.abs(got - want) <= eps) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${got}\n    want ~${want} (±${eps})`);
  }
}

function main(): void {
  // ------------------------------------------------------ 1) 速度平滑
  eq('首次采样（oldSpeed = -1）：直接用 bytesRead / 2', SpeedMath.nextSpeed(-1, 2000), 1000);
  eq('首次采样 bytesRead = 0 → 0', SpeedMath.nextSpeed(-1, 0), 0);

  // lerp(old, raw, 0.75)：更靠近新值
  near('平滑系数 0.75：old=1000, raw=2000 → 1750',
    SpeedMath.nextSpeed(1000, 4000), 1750, 0.001);
  near('平滑系数 0.75：old=1000, raw=0 → 250（不是 0，衰减而非跳变）',
    SpeedMath.nextSpeed(1000, 0), 250, 0.001);
  near('若写成 0.25 会得 1250 —— 断言把这个差别钉住',
    SpeedMath.nextSpeed(1000, 4000) === 1250 ? 1250 : SpeedMath.nextSpeed(1000, 4000), 1750, 0.001);

  // 收敛性：连续相同的原始速度，最终趋近该值
  let speed: number = 0;
  for (let i = 0; i < 12; i++) {
    speed = SpeedMath.nextSpeed(i === 0 ? -1 : speed, 2000);
  }
  near('连续 12 次采样后收敛到 1000', speed, 1000, 1);

  // ------------------------------------------------------ 2) 剩余时间：退化情形
  eq('total <= 0（长度未知）→ -1', SpeedMath.remaining(0, 0, 1000, [], [], 1800000), -1);
  eq('total = -1 → -1', SpeedMath.remaining(-1, 5, 1000, [], [], 1800000), -1);
  eq('速度 0 → 占位值（不是 -1、不是 Infinity）',
    SpeedMath.remaining(1000, 100, 0, [10], [5], 1800000), 1800000);

  // ------------------------------------------------------ 3) 剩余时间：正常估算
  //
  // 1 页正在下：contentLength=1000, received=400 → 该页还剩 600
  // total=10, downloaded=1 → 剩余 9 页，其中 1 页在下载列表里
  //   ΣcontentLength = 1000 → 外推 (10 - 1 - 1)/1 * 1000 = 8000
  //   totalSize = 600 + 8000 = 8600
  //   speed = 860 → remaining = 8600/860*1000 = 10000 ms
  near('1 页在下载时的剩余时间', SpeedMath.remaining(10, 1, 860, [1000], [400], 1800000), 10000, 0.5);

  // 2 页在下载：contentLength 各 500,1000；received 各 100,400
  //   ΣcontentLength = 1500 → 外推 (10 - 2 - 2)/2 * 1500 = 4500
  //   totalSize = (500-100)+(1000-400) = 1000 → 5500
  //   speed = 1100 → 5500/1100*1000 = 5000 ms
  near('2 页在下载时的剩余时间', SpeedMath.remaining(10, 2, 1100, [500, 1000], [100, 400], 1800000),
    5000, 0.5);

  // 已经下完（total - downloaded - n = 0）：只算当前页剩余
  //   contentLength=1000, received=900 → 100；外推项 (5-4-1)/1*1000 = 0
  //   speed=100 → 100/100*1000 = 1000 ms
  near('最后一页时的剩余时间', SpeedMath.remaining(5, 4, 100, [1000], [900], 1800000), 1000, 0.5);

  // 正在下载列表为空（n=0）→ -1（没有可估算的量）
  eq('没有在下载的页 → -1', SpeedMath.remaining(10, 3, 1000, [], [], 1800000), -1);

  // 负的剩余字节（received > contentLength，服务端返回比声明多）不应产生负时间
  const odd: number = SpeedMath.remaining(3, 0, 1000, [100], [200], 1800000);
  eq('received > contentLength 时不崩（数值有限即可）', isFinite(odd), true);

  // ------------------------------------------------------ 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('speed test failed');
  }
  console.log(`✓ speed: ${pass} 条断言全部通过`);
}

main();
