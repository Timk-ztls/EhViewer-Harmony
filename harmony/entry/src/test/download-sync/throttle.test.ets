/*
 * download-sync 纯逻辑单测：归档下载的进度节流与速度换算（`ArchiverDownloader.publishProgress`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 这段决定"通知栏多久刷新一次"和"速度数字从哪来"：
 *   1. 500ms 节流写成 `<=` / `<` 的差别会多刷或少刷；漏掉 `force` 会让
 *      "开始 / 暂停 / 完成"这些关键时刻也被压在节流里 → 用户看到通知停在旧进度；
 *   2. 速度用**本窗口**平均（`bytesSinceSpeed * 1000 / elapsed`），写成全程平均会越下越迟钝；
 *   3. `elapsed <= 0`（同一毫秒内两次调用）不能除零，否则速度变 Infinity → 通知栏显示 "Infinity B/S"。
 */

import { ProgressThrottle } from '../../main/ets/hippo/ehviewer/download/ArchiverDownloader';

const INTERVAL: number = 500;

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
    fails.push(`${name}\n    got  ${got}\n    want ~${want}`);
  }
}

function main(): void {
  // -------------------------------------------------- 1) force 永远上报
  eq('force=true 时立刻上报（开始/暂停/完成不能被节流掉）',
    ProgressThrottle.shouldNotify(true, 1000, 999, INTERVAL), true);

  // -------------------------------------------------- 2) 节流窗口
  eq('距上次 499ms → 不上报', ProgressThrottle.shouldNotify(false, 1000, 501, INTERVAL), false);
  eq('距上次恰好 500ms → 上报（>= 语义）',
    ProgressThrottle.shouldNotify(false, 1000, 500, INTERVAL), true);
  eq('距上次 501ms → 上报', ProgressThrottle.shouldNotify(false, 1000, 499, INTERVAL), true);
  eq('首次上报（lastNotifyAt=0，now 很大）→ 上报',
    ProgressThrottle.shouldNotify(false, 1700000000000, 0, INTERVAL), true);

  // -------------------------------------------------- 3) 速度换算（本窗口平均）
  near('1 秒内 1024 字节 → 1024 B/s', ProgressThrottle.speed(1024, 1000, false), 1024, 0.01);
  near('500ms 内 512 字节 → 1024 B/s（按窗口折算成每秒）',
    ProgressThrottle.speed(512, 500, false), 1024, 0.01);
  eq('暂停时速度为 0（不是保留旧值）', ProgressThrottle.speed(999999, 1000, true), 0);
  eq('elapsed=0 不除零 → 0', ProgressThrottle.speed(1024, 0, false), 0);
  eq('elapsed<0（时钟回拨）→ 0', ProgressThrottle.speed(1024, -5, false), 0);
  eq('无字节 → 0', ProgressThrottle.speed(0, 1000, false), 0);

  // -------------------------------------------------- 4) 剩余时间
  eq('暂停 → -1（UI 显示"--"）',
    ProgressThrottle.remainingMillis(true, 1000, 100, 100), -1);
  eq('长度未知（total<=0）→ -1',
    ProgressThrottle.remainingMillis(false, 0, 0, 100), -1);
  eq('速度未知（speed<=0）→ -1',
    ProgressThrottle.remainingMillis(false, 1000, 0, 0), -1);
  eq('已下完（downloaded >= total）→ 0（不是负数）',
    ProgressThrottle.remainingMillis(false, 1000, 1000, 100), 0);
  eq('超出（downloaded > total）→ 0',
    ProgressThrottle.remainingMillis(false, 1000, 1200, 100), 0);
  near('剩 900 字节 @ 100B/s → 9000ms',
    ProgressThrottle.remainingMillis(false, 1000, 100, 100), 9000, 0.01);

  // -------------------------------------------------- 5) 组合：一个 500ms 窗口的完整推算
  //
  // 窗口内收到 250000 字节 → 速度 500000 B/s；total=1MB，已下 512KB → 剩 512KB → 约 1.05 秒
  const speed: number = ProgressThrottle.speed(250000, 500, false);
  near('窗口速度 500000 B/s', speed, 500000, 1);
  near('剩余 ≈ 1048.6ms',
    ProgressThrottle.remainingMillis(false, 1048576, 524288, speed), 1048.576, 0.01);

  // -------------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('throttle test failed');
  }
  console.log(`✓ throttle: ${pass} 条断言全部通过`);
}

main();
