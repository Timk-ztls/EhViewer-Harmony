/*
 * download-sync 纯逻辑单测：标签列表移动/重命名（`DownloadManager.moveLabel/renameLabel`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 标签顺序是用户可见的（下载页左栏）。`moveLabel` 的坑在**先删后插**的下标语义：
 * 从前面删掉一条，后面的下标全部前移。写错了不报错，只是"拖到第 2 位却排到了第 3 位"，
 * 用户会觉得"这个拖拽不好用"，但没人能说清哪里错。
 */

import { LabelListOps } from '../../main/ets/hippo/ehviewer/download/DownloadManager';

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
  const base: string[] = ['default', 'A', 'B', 'C', 'D'];

  // -------------------------------------------------- 1) 向后移动
  eq('把 A(1) 移到位置 3', LabelListOps.move(base, 1, 3), ['default', 'B', 'C', 'A', 'D']);
  eq('把 A(1) 移到末尾(4)', LabelListOps.move(base, 1, 4), ['default', 'B', 'C', 'D', 'A']);

  // -------------------------------------------------- 2) 向前移动
  eq('把 D(4) 移到位置 1', LabelListOps.move(base, 4, 1), ['default', 'D', 'A', 'B', 'C']);
  eq('把 D(4) 移到位置 0', LabelListOps.move(base, 4, 0), ['D', 'default', 'A', 'B', 'C']);

  // -------------------------------------------------- 3) 原地与相邻
  eq('原地移动（from == to）不变', LabelListOps.move(base, 2, 2), ['default', 'A', 'B', 'C', 'D']);
  eq('相邻交换（1 → 2）', LabelListOps.move(base, 1, 2), ['default', 'B', 'A', 'C', 'D']);

  // -------------------------------------------------- 4) 越界
  eq('from 越界 → 原样返回（上游 remove 返回 null 后直接 return）',
    LabelListOps.move(base, 99, 1), ['default', 'A', 'B', 'C', 'D']);
  eq('from 为负 → 原样返回', LabelListOps.move(base, -1, 1), ['default', 'A', 'B', 'C', 'D']);
  eq('to 越界 → 追加到末尾（splice 语义）',
    LabelListOps.move(base, 1, 99), ['default', 'B', 'C', 'D', 'A']);

  // -------------------------------------------------- 5) 不改入参
  const original: string[] = ['default', 'A', 'B'];
  const moved: string[] = LabelListOps.move(original, 1, 2);
  eq('返回新数组，入参不被修改', original, ['default', 'A', 'B']);
  eq('返回的是移动后的结果', moved, ['default', 'B', 'A']);

  // -------------------------------------------------- 6) 删除后的下标修正（供调用方参考）
  eq('from < to 时目标下标前移一位', LabelListOps.adjustIndexAfterRemoval(1, 3), 2);
  eq('from > to 时不变', LabelListOps.adjustIndexAfterRemoval(4, 1), 1);
  eq('from == to 时不变', LabelListOps.adjustIndexAfterRemoval(2, 2), 2);

  // -------------------------------------------------- 7) 重命名查找
  const names: string[] = ['default', 'A', 'B'];
  eq('找到 A 下标 1', LabelListOps.indexOfLabel(names, 'A'), 1);
  eq('找不到 → -1（上游 found=false 直接 return，不改任何记录）',
    LabelListOps.indexOfLabel(names, 'Z'), -1);
  eq('默认标签也能被找到（上游不排除 default）', LabelListOps.indexOfLabel(names, 'default'), 0);

  // -------------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('label list test failed');
  }
  console.log(`✓ label-list: ${pass} 条断言全部通过`);
}

main();
