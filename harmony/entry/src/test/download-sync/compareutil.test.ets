/*
 * download-sync / storage-db 交叉单测：CompareUtil（storage-db c7）
 *
 * 为什么单独一批：Java 的 `String.compareTo` / `compareToIgnoreCase` 是**逐 UTF-16 码元**比较，
 * 而 JS 的 `localeCompare` 走 locale 规则。本项目已有一处误用（`ArchiverDownloadCompleter.planImportOrder`
 * 的 `byEntryOrder=false` 分支），这里把语义钉住，防止再被"顺手改成 localeCompare"。
 *
 * 断言覆盖：
 *   ① `compareCodeUnits` 与 Java 一致：首差异处返回**差值**、前缀相同返回**长度差**、相等返回 0
 *   ② 码元序 vs locale 序的**真实分歧**：`"B" < "a"`（码元序 B=66 < a=97），
 *      而 locale 规则通常 `"a" < "B"` —— 这条就是"localeCompare 是错误等价物"的证据
 *   ③ 数字文件名序：`1.jpg, 10.jpg, 2.jpg` 的码元序（这正是上游 `compareTo` 的实际效果）
 *   ④ `compareIgnoreCase`：大小写无关、但仍是码元序（`"ABC" < "abd"`）
 *   ⑤ 空串 / 前缀关系
 *
 * 运行：pwsh -File harmony/entry/src/test/download-sync/run.ps1 -Filter compareutil
 */

import { CompareUtil } from '../../main/ets/hippo/util/CompareUtil';

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

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}\n    条件为 false`);
  }
}

function sign(n: number): number {
  return n < 0 ? -1 : (n > 0 ? 1 : 0);
}

function main(): void {
  // ---------- ① 与 Java compareTo 的精确语义 ----------
  eq('相等 → 0', CompareUtil.compareCodeUnits('abc', 'abc'), 0);
  eq('首差异返回差值（"a" vs "c" → -2）', CompareUtil.compareCodeUnits('a', 'c'), -2);
  eq('首差异返回差值（"c" vs "a" → 2）', CompareUtil.compareCodeUnits('c', 'a'), 2);
  eq('前缀相同返回长度差（"ab" vs "abc" → -1）', CompareUtil.compareCodeUnits('ab', 'abc'), -1);
  eq('前缀相同返回长度差（"abc" vs "ab" → 1）', CompareUtil.compareCodeUnits('abc', 'ab'), 1);
  eq('空串 < 非空（"" vs "a" → -1）', CompareUtil.compareCodeUnits('', 'a'), -1);
  eq('非空 > 空串（"a" vs "" → 1）', CompareUtil.compareCodeUnits('a', ''), 1);
  eq('两个空串 → 0', CompareUtil.compareCodeUnits('', ''), 0);
  // 中间位差异（不是首字符）
  eq('中段差异（"abz" vs "aby" → 1）', sign(CompareUtil.compareCodeUnits('abz', 'aby')), 1);

  // ---------- ② 码元序 vs locale 序：真实分歧 ----------
  // Java: 'B'(66) < 'a'(97) → "B" 排在 "a" 前
  ok('★码元序下 "B" < "a"（这就是不能用 localeCompare 的原因）',
    CompareUtil.compareCodeUnits('B', 'a') < 0);
  ok('码元序下 "a" > "B"', CompareUtil.compareCodeUnits('a', 'B') > 0);
  // 对照：locale 规则通常是 "a" < "B"，与上游相反（这里只断言两者不一致，不断言具体 locale 行为）
  const localeSign: number = sign('a'.localeCompare('B'));
  const codeUnitSign: number = sign(CompareUtil.compareCodeUnits('a', 'B'));
  ok('码元序与 localeCompare 在这一对上结论相反（证明等价物选错会改变排序）',
    localeSign !== codeUnitSign);

  // ---------- ③ 数字文件名序（上游 compareTo 的实际效果）----------
  const names: string[] = ['2.jpg', '10.jpg', '1.jpg'];
  names.sort((a: string, b: string): number => CompareUtil.compareCodeUnits(a, b));
  eq('★码元序：1.jpg < 10.jpg < 2.jpg（字典序，不是自然数序）',
    names, ['1.jpg', '10.jpg', '2.jpg']);
  // 反证：自然数序会是 1,2,10 —— 上游不是这个行为
  ok('码元序结果 ≠ 自然数序（10 排在 2 前）',
    names.indexOf('10.jpg') < names.indexOf('2.jpg'));

  // ---------- ④ compareIgnoreCase ----------
  eq('大小写不同但折叠后相同 → 0', CompareUtil.compareIgnoreCase('abc', 'ABC'), 0);
  eq('大小写无关比较："AbC" vs "aBc" → 0', CompareUtil.compareIgnoreCase('AbC', 'aBc'), 0);
  ok('码元序但忽略大小写："ABC" < "abd"', CompareUtil.compareIgnoreCase('ABC', 'abd') < 0);
  ok('码元序但忽略大小写："abd" > "ABC"', CompareUtil.compareIgnoreCase('abd', 'ABC') > 0);
  eq('前缀 + 大小写差异 → 长度差', CompareUtil.compareIgnoreCase('AB', 'abc'), -1);
  // 与 Java 一致：先比原码元，不同才折叠 —— 结果是折叠后的差值
  ok('"a" vs "C"：折叠后 a(65) < C(67) → 负', CompareUtil.compareIgnoreCase('a', 'C') < 0);
  // 非 ASCII：'Ä'(196) vs 'ä'(228) 折叠后相等
  eq('非 ASCII 大小写折叠（Ä vs ä）→ 0', CompareUtil.compareIgnoreCase('Ä', 'ä'), 0);

  // ---------- ⑤ codeUnitComparator 与 compareCodeUnits 一致 ----------
  eq('比较器与直接调用的符号一致',
    sign(CompareUtil.codeUnitComparator('b', 'a')), sign(CompareUtil.compareCodeUnits('b', 'a')));
  const arr: string[] = ['c', 'a', 'b'];
  arr.sort(CompareUtil.codeUnitComparator);
  eq('作为 sort 比较器可用', arr, ['a', 'b', 'c']);

  // ---------- ⑥ 代理对（BMP 外）按码元比较，与 Java char 语义一致 ----------
  // U+1F600 是代理对 (0xD83D, 0xDE00)；Java 的 char 比较也按这两个码元
  const emoji: string = '\u{1F600}';
  const bmpHigh: string = '\uFFFD';
  ok('代理对首码元 0xD83D < 0xFFFD → emoji 排在 \uFFFD 前',
    CompareUtil.compareCodeUnits(emoji, bmpHigh) < 0);

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('compareutil test failed');
  }
  console.log(`✓ CompareUtil 批（码元序 vs localeCompare）: ${pass} 条断言全部通过`);
}

main();
