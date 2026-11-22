/*
 * download-sync 纯逻辑单测：通知任务的分派决策（`NotifyDispatch`，18 格）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 为什么要有这一层：`NotifyIdentity.shouldApply` 本身已有 12 条断言，但
 * **"`applyNotifyTask` 有没有调用它"没人测** —— 这正是 `legacy` 那类 bug 的形状：
 * **函数对、接缝错**。把分派抽成纯函数后，"509 永远放行 / 其余按 gid 校验"变成可断言的事实。
 *
 * 6 种 type × 3 种 gid 关系 = 18 格。
 * type 编号与 `NotifyTask` 保持一致（该类是文件内私有，本测试用字面量并在首格钉住编号）：
 *   0 ON_GET_PAGES / 1 ON_GET_509 / 2 ON_PAGE_DOWNLOAD / 3 ON_PAGE_SUCCESS / 4 ON_PAGE_FAILURE / 5 ON_FINISH
 */

import { NotifyDispatch, NotifyIdentity } from '../../main/ets/hippo/ehviewer/download/DownloadManager';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: string, want: string): void {
  if (got === want) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${got}\n    want ${want}`);
  }
}

const TYPE_NAMES: string[] = ['ON_GET_PAGES', 'ON_GET_509', 'ON_PAGE_DOWNLOAD', 'ON_PAGE_SUCCESS',
  'ON_PAGE_FAILURE', 'ON_FINISH'];

// gid 关系三种：匹配 / 不匹配（旧任务 vs 新任务）/ 任一侧为空
const GID_CASES: string[] = ['match', 'mismatch', 'empty'];

function planFor(type: number, gidCase: string): string {
  switch (gidCase) {
    case 'match':
      return NotifyDispatch.plan(type, 1001, 1001);
    case 'mismatch':
      return NotifyDispatch.plan(type, 1001, 2002);
    default:
      // 任务已停止：currentGid = -1
      return NotifyDispatch.plan(type, 1001, -1);
  }
}

function main(): void {
  // ---------------------------------------------- 0) 编号钉住（防止 NotifyTask 改了编号这里不知道）
  eq('TYPE_ON_GET_509 的编号是 1（全局事件，分派里按字面量判断）',
    NotifyDispatch.plan(1, -1, -1), NotifyDispatch.APPLY);

  // ---------------------------------------------- 1) 18 格全表
  //
  // 期望：除 509 外，只有 match 才 apply；mismatch / empty 一律 drop。
  const expected: string[][] = [
    // ON_GET_PAGES
    ['apply', 'drop', 'drop'],
    // ON_GET_509（全局事件：三种 gid 关系都放行，与 gid 无关）
    ['apply', 'apply', 'apply'],
    // ON_PAGE_DOWNLOAD
    ['apply', 'drop', 'drop'],
    // ON_PAGE_SUCCESS
    ['apply', 'drop', 'drop'],
    // ON_PAGE_FAILURE
    ['apply', 'drop', 'drop'],
    // ON_FINISH
    ['apply', 'drop', 'drop']
  ];

  let cells: number = 0;
  for (let t = 0; t < 6; t++) {
    for (let g = 0; g < GID_CASES.length; g++) {
      cells++;
      eq(`[${TYPE_NAMES[t]} × ${GID_CASES[g]}]`, planFor(t, GID_CASES[g]), expected[t][g]);
    }
  }
  eq('矩阵规模 = 6 × 3 = 18 格', String(cells), '18');

  // ---------------------------------------------- 2) 跨格不变量
  eq('509 是唯一与 gid 无关的分支（三种关系都 apply）',
    `${planFor(1, 'match')}/${planFor(1, 'mismatch')}/${planFor(1, 'empty')}`,
    'apply/apply/apply');

  eq('非 509 分支在 gid 不匹配时**一律** drop（不存在"某个 type 忘了校验"）',
    [0, 2, 3, 4, 5].map((t: number): string => planFor(t, 'mismatch')).join(','),
    'drop,drop,drop,drop,drop');

  eq('非 509 分支在任务已停止时**一律** drop',
    [0, 2, 3, 4, 5].map((t: number): string => planFor(t, 'empty')).join(','),
    'drop,drop,drop,drop,drop');

  // ---------------------------------------------- 3) 分派与校验函数的对应关系
  //
  // 保证 NotifyDispatch 没有"自己另写一套判断"（否则 Identity 改了它不跟）。
  eq('非 509 的 apply 判定 == NotifyIdentity.shouldApply',
    `${NotifyDispatch.plan(0, 1001, 1001) === NotifyDispatch.APPLY}`,
    `${NotifyIdentity.shouldApply(1001, 1001)}`);
  eq('非 509 的 drop 判定 == !NotifyIdentity.shouldApply',
    `${NotifyDispatch.plan(0, 1001, 2002) === NotifyDispatch.DROP}`,
    `${!NotifyIdentity.shouldApply(1001, 2002)}`);

  // ---------------------------------------------- 4) 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 格不符 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('notify dispatch test failed');
  }
  console.log(`✓ notify-dispatch: ${pass} 条断言全部通过（含 18 格）`);
}

main();
