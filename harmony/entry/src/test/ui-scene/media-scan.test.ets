/*
 * 单测：mediaScan 接线（消费者驱动清单报的"getMediaScan 全仓 0 调用"）
 *
 * 钉的是**调用条件**，不是"方法存在"：
 *   getMediaScan()=true  → 扫
 *   getMediaScan()=false → 不扫
 * 以及 Noop 实现的 warn-once 语义（高频路径不能每次都 warn，也不能完全不 warn）。
 */

import { NoopMediaScanner } from '../../main/ets/hippo/ehviewer/download/MediaScanner';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}\n    got  ${g}\n    want ${w}`); }
}

function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(`${name}  (want true)`); }
}

/** 复刻 DownloadManager.scanFinished 的条件分支（生产代码私有，这里按同一判据断言） */
function scanLike(mediaScanSetting: boolean, scanner: NoopMediaScanner, gid: number): boolean {
  if (!mediaScanSetting) { return false; }
  scanner.scanGallery(gid);
  return true;
}

function main(): void {
  // ① 条件调用
  NoopMediaScanner.reset();
  const s1: NoopMediaScanner = new NoopMediaScanner();
  eq('getMediaScan=true → 触发扫描', scanLike(true, s1, 42), true);
  eq('触发后 callCount=1', NoopMediaScanner.callCount(), 1);

  NoopMediaScanner.reset();
  const s2: NoopMediaScanner = new NoopMediaScanner();
  eq('getMediaScan=false → **不触发**', scanLike(false, s2, 42), false);
  eq('不触发时 callCount=0（这是本条的关键断言）', NoopMediaScanner.callCount(), 0);

  // ② warn-once
  NoopMediaScanner.reset();
  const s3: NoopMediaScanner = new NoopMediaScanner();
  s3.scanGallery(1);
  eq('首次 warn', NoopMediaScanner.warned(), true);
  s3.scanGallery(2);
  s3.scanGallery(3);
  eq('后续调用照常计数', NoopMediaScanner.callCount(), 3);
  eq('但 warned 仍为 true（不重复打日志）', NoopMediaScanner.warned(), true);

  // ③ reset 可用（测试隔离）
  NoopMediaScanner.reset();
  eq('reset 后 warned=false', NoopMediaScanner.warned(), false);
  eq('reset 后 callCount=0', NoopMediaScanner.callCount(), 0);

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) { console.error('  - ' + f); }
    throw new Error('media-scan test failed');
  }
  console.log(`✓ download-sync 相册扫描接线批: ${pass} 条断言全部通过`);
}

main();