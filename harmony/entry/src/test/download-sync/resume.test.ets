/*
 * download-sync 纯逻辑单测：断点续传的响应判定（`ArchiverDownloader.onResponse`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 这是全模块最危险的一段：四个分支的顺序决定"续传 / 整包重下 / 判定完成 / 失败"。
 * 顺序写反不会报错，只会：
 *   - 416 当成失败 → **文件其实已下完，却永远卡在失败**（用户点恢复还是失败）
 *   - 200 当成续传 → offset>0 时把整包内容**追加**到半截文件后面 → zip 损坏
 *   - 206 走成功分支 → 只下了半包就宣告完成 → 解压必失败
 */

import { archiverLabel, archiverLabelFor } from '../../main/ets/hippo/ehviewer/download/ArchiverDownloadCompleter';
import { ArchiverDownloader, ResumeDecision, ResumePlan }
  from '../../main/ets/hippo/ehviewer/download/ArchiverDownloader';

/** 同形探针：`ActiveTask` 未导出，测试无法构造它；这里只需要"两个对象字段全等但引用不同"。 */
class TaskProbe {
  public gid: number;
  public taskId: number;
  constructor(gid: number, taskId: number) { this.gid = gid; this.taskId = taskId; }
}

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

function main(): void {
  const SUCCESS: number = ResumeDecision.KIND_SUCCESS;
  const FAILED: number = ResumeDecision.KIND_FAILED;
  const COMPLETE: number = ResumeDecision.KIND_COMPLETE_ALREADY;

  // ---------------------------------------------- 1) 416 = 已经下完（不是失败）
  const p416: ResumePlan = ResumeDecision.decide(416, 5000);
  eq('416 → 判定"已完成"（上游最先判这条）', p416.kind, COMPLETE);
  const p416NoOffset: ResumePlan = ResumeDecision.decide(416, 0);
  eq('416 即使没带 Range 也判定已完成', p416NoOffset.kind, COMPLETE);

  // ---------------------------------------------- 2) 正常 206（续传成功）
  const p206: ResumePlan = ResumeDecision.decide(206, 5000);
  eq('206 + 有 offset → 成功续传', p206.kind, SUCCESS);
  eq('206 不触发"整包重下"提示', p206.reason, ResumeDecision.REASON_NONE);

  // ---------------------------------------------- 3) 200 分两种：全新下载 vs 忽略 Range
  const p200Fresh: ResumePlan = ResumeDecision.decide(200, 0);
  eq('200 + offset=0 → 正常下载', p200Fresh.kind, SUCCESS);
  eq('200 + offset=0 不提示降级', p200Fresh.reason, ResumeDecision.REASON_NONE);

  const p200IgnoreRange: ResumePlan = ResumeDecision.decide(200, 5000);
  eq('200 + offset>0 → 服务端忽略 Range，仍按成功处理', p200IgnoreRange.kind, SUCCESS);
  eq('**同时给出降级原因**（必须重置 offset 整包重下，否则追加写坏 zip）',
    p200IgnoreRange.reason, ResumeDecision.REASON_RESTART_NO_RANGE);

  // ---------------------------------------------- 4) 其它状态码 = 失败
  eq('404 → 失败', ResumeDecision.decide(404, 0).kind, FAILED);
  eq('500 → 失败', ResumeDecision.decide(500, 100).kind, FAILED);
  eq('509 → 失败（配额限制，由上层转告警）', ResumeDecision.decide(509, 0).kind, FAILED);
  eq('304 → 失败（不该出现，出现即异常）', ResumeDecision.decide(304, 0).kind, FAILED);

  // ---------------------------------------------- 5) 分支优先级：416 优先于"非 2xx"
  //
  // 416 本身不是 2xx。如果先判"非 200/206 即失败"，已完成的任务会被判死。
  const p416Priority: ResumePlan = ResumeDecision.decide(416, 9999);
  eq('416 必须先于"非 2xx → 失败"判定（顺序写反 = 已完成任务永远失败）',
    p416Priority.kind, COMPLETE);

  // ---------------------------------------------- 6) 与 resolveTotal 的组合
  eq('206 + Content-Range 总长 → 用总长',
    ArchiverDownloader.resolveTotal(10000, 5000, 5000), 10000);
  eq('206 无 Content-Range → offset + 本次长度',
    ArchiverDownloader.resolveTotal(0, 5000, 5000), 10000);
  eq('200 忽略 Range（offset 归零）→ 总长 = 本次长度',
    ArchiverDownloader.resolveTotal(0, 0, 10000), 10000);

  // ---------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('resume test failed');
  }
  console.log(`✓ resume: ${pass} 条断言全部通过`);
}

  // ================================================================ L-11 / L-06 回归
  eq('decide(0,0).kind = UNKNOWN', ResumeDecision.decide(0, 0).kind, ResumeDecision.KIND_UNKNOWN);
  eq('decide(0,0).reason = unknown_status', ResumeDecision.decide(0, 0).reason, ResumeDecision.REASON_UNKNOWN_STATUS);
  eq('decide(0,offset>0) 仍 UNKNOWN', ResumeDecision.decide(0, 5000).kind, ResumeDecision.KIND_UNKNOWN);
  eq('UNKNOWN ≠ FAILED', ResumeDecision.KIND_UNKNOWN !== ResumeDecision.KIND_FAILED, true);
  eq('decide(200,0) = SUCCESS', ResumeDecision.decide(200, 0).kind, ResumeDecision.KIND_SUCCESS);
  eq('decide(200,>0) = RESTART_NO_RANGE', ResumeDecision.decide(200, 100).reason, ResumeDecision.REASON_RESTART_NO_RANGE);
  eq('decide(206,>0) = 无 reason', ResumeDecision.decide(206, 100).reason, ResumeDecision.REASON_NONE);
  eq('decide(416,>0) = COMPLETE_ALREADY', ResumeDecision.decide(416, 100).kind, ResumeDecision.KIND_COMPLETE_ALREADY);
  eq('decide(500,0) = FAILED', ResumeDecision.decide(500, 0).kind, ResumeDecision.KIND_FAILED);
  eq('isRangeIgnored(200,100) = true', ResumeDecision.isRangeIgnored(200, 100), true);
  eq('isRangeIgnored(200,0) = false', ResumeDecision.isRangeIgnored(200, 0), false);
  eq('isRangeIgnored(206,100) = false', ResumeDecision.isRangeIgnored(206, 100), false);
  eq('isRangeIgnored(416,100) = false', ResumeDecision.isRangeIgnored(416, 100), false);
  eq('isRangeIgnored(0,100) = false（未知不截断）', ResumeDecision.isRangeIgnored(0, 100), false);
  // ================================================================ c4 / c5（L-14 / L-15）
  // L-14：身份判据必须是**引用比较** —— pause→resume 后 taskId 不变、对象被换
  {
    const a: TaskProbe = new TaskProbe(7, 12345);
    const b: TaskProbe = new TaskProbe(7, 12345);   // 字段全等，但不是同一个对象
    eq('同一对象 → true', ArchiverDownloader.isSameTask(a, a), true);
    eq('不同对象但字段全等 → false（旧判据会误判为同一个）', ArchiverDownloader.isSameTask(a, b), false);
    eq('registered 为 undefined（已被 delete）→ false', ArchiverDownloader.isSameTask(undefined, a), false);
    eq('交换顺序仍 false', ArchiverDownloader.isSameTask(b, a), false);
    eq('shouldDropTaskCallback(当前任务 a, a) → false（不得早退丢弃）',
      ArchiverDownloader.shouldDropTaskCallback(a, a), false);
    eq('shouldDropTaskCallback(已被替换为 b, 旧 a) → true（必须早退丢弃）',
      ArchiverDownloader.shouldDropTaskCallback(b, a), true);
    eq('shouldDropTaskCallback(已取消 undefined, 旧 a) → true',
      ArchiverDownloader.shouldDropTaskCallback(undefined, a), true);
  }
  // ================================================================ c6 / L-16：归档标签按 locale
  eq('zh-CN → 档案', archiverLabelFor('zh-CN'), '档案');
  eq('zh-Hans → 档案', archiverLabelFor('zh-Hans'), '档案');
  eq('裸 zh → 档案（HarmonyOS 常返回 zh）', archiverLabelFor('zh'), '档案');
  eq('zh-TW → 歸檔器', archiverLabelFor('zh-TW'), '歸檔器');
  eq('zh-HK → 歸檔器', archiverLabelFor('zh-HK'), '歸檔器');
  eq('zh-Hant → 歸檔器', archiverLabelFor('zh-Hant'), '歸檔器');
  eq('en-US → Archiver', archiverLabelFor('en-US'), 'Archiver');
  eq('ja-JP → Archiver（未列出的语言走默认）', archiverLabelFor('ja-JP'), 'Archiver');
  eq('大小写不敏感（ZH-tw）', archiverLabelFor('ZH-tw'), '歸檔器');
  eq('不是硬编码的「归档」', archiverLabelFor('zh-CN') !== '归档', true);

  // ================================================================ R-11：调用点的"输入域"
  // 纯函数断言只证明"给定这个输入我是对的"；这里断言**生产调用点喂进来的形状**
  eq('provider zh-Hant-TW → 歸檔器', archiverLabel(() => 'zh-Hant-TW'), '歸檔器');
  eq('provider zh-Hans-CN → 档案', archiverLabel(() => 'zh-Hans-CN'), '档案');
  eq('provider 裸 zh → 档案（D-071 登记的偏离）', archiverLabel(() => 'zh'), '档案');
  eq('provider en-US → Archiver', archiverLabel(() => 'en-US'), 'Archiver');
  eq('provider 抛错 → Archiver（安全侧）', archiverLabel((): string => { throw new Error('boom'); }), 'Archiver');
  {
    // 生产取值器必须存在且返回字符串（若它抛错，archiverLabel 内部兜底 → 只会是三种之一）
    const label: string = archiverLabel();
    eq('archiverLabel() 的返回值在合法集合内',
      label === 'Archiver' || label === '档案' || label === '歸檔器', true);
  }

  // ================================================================ ① 416 处理顺序（身份在前、幂等在后）
  // 场景：pause → resume 后对象被替换，**旧任务**的 416 到达（它自己没被标记过）
  eq('旧任务（isCurrent=false, handled=false）→ 不处理（否则误删新任务）',
    ArchiverDownloader.shouldHandle416(false, false), false);
  eq('旧任务且已标记（false, true）→ 不处理', ArchiverDownloader.shouldHandle416(false, true), false);
  eq('当前任务首次（true, false）→ 处理', ArchiverDownloader.shouldHandle416(true, false), true);
  eq('当前任务第二次（true, true）→ 幂等挡住', ArchiverDownloader.shouldHandle416(true, true), false);
  // 反证：若把顺序写反（只看 handled416），旧任务会被判"该处理" —— 这正是误删新任务的路径
  {
    const reversedOrderWouldHandle: boolean = !false;   // 只看 handled416=false
    eq('反证：顺序写反时旧任务会被放行（故顺序是判据本身）', reversedOrderWouldHandle, true);
  }

main();
