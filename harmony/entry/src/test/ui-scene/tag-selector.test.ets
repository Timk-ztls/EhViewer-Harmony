/*
 * download-sync 接手批单测：TagSelectorActivity（S0272，663 行）的纯逻辑
 *
 * 钉住七条"写错也能编译、但用户可见"的语义：
 *   1. LOAD_PREFIXES 的顺序（空串最前 → a..z → 0..9，共 38 项）
 *   2. loadNextBatch 的目标 = visibleCount + 12，且**先设 visibleCount 再查库**
 *   3. collapse 回到 initialCount（不是 0、不是 12 写死）
 *   4. suggest 结果的双向归一：谁带 namespace 谁是 key；都不带 → 丢
 *   5. 非中文系统**强制英文**；中文系统才用翻译，翻译缺失回退英文
 *   6. 纯 CJK 的 key 必须丢弃（数据清洗，不是翻译）
 *   7. 回传串是 key 用**空格**连接并 trim
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  TagSelectorActivity, TagGroup, TagItem, TagPair, FooterItem, TagRowKind, FooterState,
  TagSelectorColors, SelectedTagGroup
} from '../../main/ets/hippo/ehviewer/ui/TagSelectorActivity';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
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
    fails.push(`${name}  (want true)`);
  }
}

// ---------------------------------------------------------------- 常量表

function testConstants(): void {
  const p: string[] = TagSelectorActivity.LOAD_PREFIXES;
  eq('前缀共 37 项（空串 + 26 字母 + 10 数字）', p.length, 37);
  eq('第 0 项是空串（先查全组）', p[0], '');
  eq('接着是 a', p[1], 'a');
  eq('字母段末尾是 z', p[26], 'z');
  eq('数字段从 0 开始', p[27], '0');
  eq('数字段末尾是 9', p[36], '9');
  eq('12 个置顶语言', TagSelectorActivity.TOP_LANGUAGES.length, 12);
  eq('第一个置顶语言是 chinese', TagSelectorActivity.TOP_LANGUAGES[0], 'chinese');
  eq('标准分组 8 个', TagSelectorActivity.STANDARD_GROUPS.length, 8);
  eq('网格 3 列', TagSelectorActivity.GRID_SPAN, 3);
  eq('每次「More」+12', TagSelectorActivity.PAGE_STEP, 12);
}

// ---------------------------------------------------------------- 环境判定

function testEnvironment(): void {
  // 上游是 contains("zh")，不是 startsWith
  eq('zh-CN 算中文', TagSelectorActivity.isChineseLanguage('zh-CN'), true);
  eq('zh_TW 算中文', TagSelectorActivity.isChineseLanguage('zh_TW'), true);
  eq('en-US 不算中文', TagSelectorActivity.isChineseLanguage('en-US'), false);
  eq('含 zh 的私有标签也算（上游 contains 语义）',
    TagSelectorActivity.isChineseLanguage('x-zh-x'), true);

  // 语言显示名：非中文一律首字母大写；中文查硬编码
  eq('非中文系统：chinese → Chinese',
    TagSelectorActivity.displayLanguageFor('chinese', false), 'Chinese');
  eq('中文系统：chinese → 中文',
    TagSelectorActivity.displayLanguageFor('chinese', true), '中文');
  eq('中文系统：japanese → 日语',
    TagSelectorActivity.displayLanguageFor('japanese', true), '日语');
  eq('中文系统：未知语言回退首字母大写',
    TagSelectorActivity.displayLanguageFor('klingon', true), 'Klingon');
}

// ---------------------------------------------------------------- 工具函数

function testUtils(): void {
  eq('namespace 取冒号前', TagSelectorActivity.extractNamespace('female:swimsuit'), 'female');
  eq('无冒号 → 空串', TagSelectorActivity.extractNamespace('swimsuit'), '');
  eq('冒号在第 0 位 → 空串', TagSelectorActivity.extractNamespace(':x'), '');
  eq('null → 空串', TagSelectorActivity.extractNamespace(null), '');

  eq('首字母大写', TagSelectorActivity.capitalize('female'), 'Female');
  eq('空串保持空', TagSelectorActivity.capitalize(''), '');
  eq('已是大写不变', TagSelectorActivity.capitalize('ABC'), 'ABC');

  // CJK 判定：只认 U+4E00–U+9FFF（扩展区不认，与上游 UnicodeBlock 一致）
  eq('汉字算 CJK', TagSelectorActivity.containsCjk('中文'), true);
  eq('英文不算', TagSelectorActivity.containsCjk('chinese'), false);
  eq('null 不算', TagSelectorActivity.containsCjk(null), false);
  eq('扩展 A 区（U+3400）不算（上游不认）',
    TagSelectorActivity.containsCjk('\u3400'), false);
}

// ---------------------------------------------------------------- 分组结构

function testGroups(): void {
  const act: TagSelectorActivity = new TagSelectorActivity();
  act.initGroups(true);

  eq('共 9 个分组（1 Language + 8 标准）', act.groups.length, 9);
  eq('第 0 个是 Language', act.groups[0].namespace, 'language');
  eq('Language 12 个置顶标签', act.groups[0].loadedTags.length, 12);
  eq('Language 初始可见 12', act.groups[0].visibleCount, 12);
  eq('Language 初始折叠数 12', act.groups[0].initialCount, 12);
  eq('第一个置顶项的 key 带 namespace', act.groups[0].loadedTags[0].key, 'language:chinese');
  eq('第一个置顶项是 pinned', act.groups[0].loadedTags[0].isPinned, true);
  eq('中文系统下第一个显示「中文」', act.groups[0].loadedTags[0].show, '中文');

  const en: TagSelectorActivity = new TagSelectorActivity();
  en.initGroups(false);
  eq('非中文系统下显示 English 形态', en.groups[0].loadedTags[0].show, 'Chinese');

  // 预加载只针对非 language 组
  const preload: TagGroup[] = act.groupsToPreload();
  eq('预加载 8 个（排除 Language）', preload.length, 8);
  ok('预加载里没有 language', preload.every((g: TagGroup): boolean => g.namespace !== 'language'));

  // 标准组：initialCount/visibleCount 都是 12，但 loadedTags 空
  eq('标准组初始可见 12', act.groups[1].visibleCount, 12);
  eq('标准组初始已加载 0', act.groups[1].loadedTags.length, 0);
}

function testAddPinnedDedup(): void {
  const g: TagGroup = new TagGroup('Test', 'test', 0);
  g.addPinned('a', 'A');
  g.addPinned('a', 'A2');
  eq('重复置顶 key 不重复加入', g.loadedTags.length, 1);
  eq('先到的显示名保留', g.loadedTags[0].show, 'A');
  eq('key 拼成 namespace:key', g.loadedTags[0].key, 'test:a');
}

// ---------------------------------------------------------------- 分批加载

function testBatches(): void {
  const g: TagGroup = new TagGroup('Female', 'female', 12);
  eq('初始前缀是 female:', TagSelectorActivity.prefixFor(g), 'female:');

  g.prefixIndex = 36;
  eq('最后一个前缀是 female:9', TagSelectorActivity.prefixFor(g), 'female:9');
  g.prefixIndex = 37;
  eq('前缀用尽 → null', TagSelectorActivity.prefixFor(g), null);

  // planNextBatch：本地够 → 不查库
  const cached: TagGroup = new TagGroup('X', 'x', 12);
  for (let i = 0; i < 30; i++) {
    cached.loadedTags.push(new TagItem(`x:t${i}`, `T${i}`, false));
  }
  const p1 = TagSelectorActivity.planNextBatch(cached);
  eq('本地够 → 目标 24', p1.targetCount, 24);
  eq('本地够 → 不查库', p1.needQuery, false);
  eq('本地够 → 刷新', p1.refresh, true);

  // 本地不够 → 查库
  const cold: TagGroup = new TagGroup('Y', 'y', 12);
  const p2 = TagSelectorActivity.planNextBatch(cold);
  eq('本地不够 → 目标 24', p2.targetCount, 24);
  eq('本地不够 → 要查库', p2.needQuery, true);
  eq('本地不够 → 查完再刷新', p2.refresh, false);

  // 前缀用尽 → 收敛到实际数量
  const exhausted: TagGroup = new TagGroup('Z', 'z', 12);
  exhausted.prefixIndex = 37;
  exhausted.loadedTags.push(new TagItem('z:a', 'A', false));
  const p3 = TagSelectorActivity.planNextBatch(exhausted);
  eq('前缀用尽 → 目标 = 已加载数', p3.targetCount, 1);
  eq('前缀用尽 → 不查库', p3.needQuery, false);
  eq('前缀用尽 → 刷新', p3.refresh, true);

  // collapse 回到 initialCount
  const c: TagGroup = new TagGroup('C', 'c', 12);
  c.visibleCount = 60;
  TagSelectorActivity.collapse(c);
  eq('收起 → 回到 12', c.visibleCount, 12);
}

// ---------------------------------------------------------------- suggest 归一

function testNormalize(): void {
  const g: TagGroup = new TagGroup('Female', 'female', 12);

  // ① key 在 first
  const r1: TagItem[] = TagSelectorActivity.normalizeSuggest(g,
    [new TagPair('female:swimsuit', '泳装')], true);
  eq('key 在 first：取 key', r1[0].key, 'female:swimsuit');
  eq('中文系统用翻译', r1[0].show, '泳装');

  // ② key 在 second（位置不固定）
  const r2: TagItem[] = TagSelectorActivity.normalizeSuggest(g,
    [new TagPair('泳装', 'female:swimsuit')], true);
  eq('key 在 second 也能识别', r2[0].key, 'female:swimsuit');
  eq('显示名随之调换', r2[0].show, '泳装');

  // ③ 两侧都不带 namespace → 丢弃
  eq('都不带 namespace → 丢',
    TagSelectorActivity.normalizeSuggest(g, [new TagPair('swimsuit', '泳装')], true).length, 0);

  // ④ 非中文系统强制英文（即使有翻译）
  const r4: TagItem[] = TagSelectorActivity.normalizeSuggest(g,
    [new TagPair('female:swimsuit', '泳装')], false);
  eq('非中文 → 强制英文首字母大写', r4[0].show, 'Swimsuit');

  // ⑤ 中文系统但翻译缺失 → 回退英文
  const r5: TagItem[] = TagSelectorActivity.normalizeSuggest(g,
    [new TagPair('female:swimsuit', '')], true);
  eq('翻译为空 → 回退英文', r5[0].show, 'Swimsuit');

  // ⑥ 翻译等于 key → 回退英文
  const r6: TagItem[] = TagSelectorActivity.normalizeSuggest(g,
    [new TagPair('female:swimsuit', 'female:swimsuit')], true);
  eq('翻译同 key → 回退英文', r6[0].show, 'Swimsuit');

  // ⑦ 翻译里还带 namespace → 取后半
  const r7: TagItem[] = TagSelectorActivity.normalizeSuggest(g,
    [new TagPair('female:swimsuit', 'other:泳装')], true);
  eq('翻译里带冒号 → 取后半', r7[0].show, '泳装');

  // ⑧ 纯 CJK 的 key 丢弃
  eq('CJK key → 丢',
    TagSelectorActivity.normalizeSuggest(g,
      [new TagPair('female:泳装', '泳装')], true).length, 0);

  // ⑨ null 入参不崩
  eq('null → 空数组', TagSelectorActivity.normalizeSuggest(g, null, true).length, 0);
}

function testApplyBatch(): void {
  const g: TagGroup = new TagGroup('Female', 'female', 12);
  const items: TagItem[] = [
    new TagItem('female:a', 'A', false),
    new TagItem('female:b', 'B', false)
  ];
  const more: boolean = TagSelectorActivity.applyBatch(g, items);
  eq('加入 2 个', g.loadedTags.length, 2);
  eq('前缀推进到 1', g.prefixIndex, 1);
  eq('不够 12 个 → 需要继续查', more, true);

  // 去重：同 key 再来一次不重复加入
  TagSelectorActivity.applyBatch(g, [new TagItem('female:a', 'A2', false)]);
  eq('重复 key 不重复加入', g.loadedTags.length, 2);
  eq('已加载 2 个但 visibleCount 仍是 12 → 继续查', g.prefixIndex, 2);

  // 前缀用尽时收敛 visibleCount
  g.prefixIndex = 36;
  g.visibleCount = 12;
  TagSelectorActivity.applyBatch(g, []);
  eq('前缀用尽 → visibleCount 收敛到已加载数', g.visibleCount, 2);

  // 已够数 → 不再继续
  const full: TagGroup = new TagGroup('F', 'f', 12);
  full.visibleCount = 1;
  const moreFull: boolean = TagSelectorActivity.applyBatch(full,
    [new TagItem('f:a', 'A', false), new TagItem('f:b', 'B', false)]);
  eq('已满足 visibleCount → 不继续', moreFull, false);
}

// ---------------------------------------------------------------- 展示

function testRows(): void {
  const act: TagSelectorActivity = new TagSelectorActivity();
  act.initGroups(true);
  // 让第一个标准组有 3 个标签，但 visibleCount=2 → 只展示 2 个
  const female: TagGroup = act.groups[1];
  female.loadedTags.push(new TagItem('female:a', 'A', false));
  female.loadedTags.push(new TagItem('female:b', 'B', false));
  female.loadedTags.push(new TagItem('female:c', 'C', false));
  female.visibleCount = 2;

  const rows = act.buildRows();
  // 9 组 × (header + footer) = 18；Language 12 个标签；Female 2 个（被 visibleCount 截断）；其余 0
  eq('行数 = 18 + 12 + 2', rows.length, 32);
  eq('第 0 行是 Language 的 header', rows[0].kind, TagRowKind.HEADER);
  eq('header 携带分组', rows[0].group === null ? null : rows[0].group.namespace, 'language');
  eq('第 1 行是第一个标签', rows[1].kind, TagRowKind.ITEM);
  eq('Language 后面是 footer（第 13 行）', rows[13].kind, TagRowKind.FOOTER);

  // 选中状态反映在行上
  act.toggle('female:a', 'A');
  const rows2 = act.buildRows();
  const itemRow = rows2.find((r): boolean =>
    r.kind === TagRowKind.ITEM && r.item !== null && r.item.key === 'female:a');
  eq('已选标签的行标 selected', itemRow === undefined ? null : itemRow.selected, true);

  // span：header/footer 3 格，item 1 格，越界 1
  eq('header 占 3 格', TagSelectorActivity.spanSizeOf(rows, 0), 3);
  eq('item 占 1 格', TagSelectorActivity.spanSizeOf(rows, 1), 1);
  eq('footer 占 3 格', TagSelectorActivity.spanSizeOf(rows, 13), 3);
  eq('越界 → 1（上游保留该分支）', TagSelectorActivity.spanSizeOf(rows, 9999), 1);
  eq('负下标 → 1', TagSelectorActivity.spanSizeOf(rows, -1), 1);

  // footer 三态
  const lang: TagGroup = act.groups[0];
  const fs1 = TagSelectorActivity.footerState(lang);
  eq('Language 还有前缀可查 → MORE', fs1.state, FooterState.MORE);
  eq('未展开 → 不显示收起', fs1.showCollapse, false);

  lang.visibleCount = 24;
  const fs2 = TagSelectorActivity.footerState(lang);
  eq('展开后 → 显示收起', fs2.showCollapse, true);

  // 前缀用尽 + 已加载不超过可见 → END
  const done: TagGroup = new TagGroup('D', 'd', 12);
  done.prefixIndex = 37;
  done.loadedTags.push(new TagItem('d:a', 'A', false));
  done.visibleCount = 12;
  eq('到底 → END', TagSelectorActivity.footerState(done).state, FooterState.END);
}

// ---------------------------------------------------------------- 选中与回传

function testSelection(): void {
  const act: TagSelectorActivity = new TagSelectorActivity();
  act.initGroups(true);

  eq('初始无选中', act.isEmptySelection(), true);
  eq('空选中 → 空回传串', act.selectedQueryText(), '');
  eq('空选中 → 已选面板无分组', act.rebuildSelectedGroups().length, 0);

  // 选中两个（顺序 = 插入顺序）
  const added1: boolean = act.toggle('female:swimsuit', '泳装');
  const added2: boolean = act.toggle('male:glasses', '眼镜');
  eq('首次点击是"加入"', added1, true);
  eq('第二个也是加入', added2, true);
  eq('回传串用空格连接', act.selectedQueryText(), 'female:swimsuit male:glasses');

  // 再点同一个 → 移除
  const removed: boolean = act.toggle('female:swimsuit', '泳装');
  eq('再点 → 移除', removed, false);
  eq('移除后只剩一个', act.selectedQueryText(), 'male:glasses');

  // 已选面板按分组归类
  act.toggle('female:swimsuit', '泳装');
  const groups: SelectedTagGroup[] = act.rebuildSelectedGroups();
  eq('已选面板分成 2 组（female 在前，因为 groups 顺序）', groups.length, 2);
  eq('第一组标题取自分组表', groups[0].title, 'Female');
  eq('第一组里有 swimsuit', groups[0].entries.length, 1);
  eq('第一组 key 完整', groups[0].entries[0].first, 'female:swimsuit');
  eq('第一组显示名', groups[0].entries[0].second, '泳装');

  // 未知 namespace → 追加在后 + 首字母大写标题
  act.toggle('weird:thing', 'Thing');
  const groups2: SelectedTagGroup[] = act.rebuildSelectedGroups();
  eq('未知分组追加在后', groups2[groups2.length - 1].title, 'Weird');

  // 无 namespace 的 key → "其他" 资源名
  act.toggle('nocolon', 'X');
  const groups3: SelectedTagGroup[] = act.rebuildSelectedGroups();
  eq('无 namespace → other group 资源名',
    groups3[groups3.length - 1].title, 'tag_selector_other_group');

  // 面板文案
  eq('分区标题资源名', TagSelectorActivity.sectionTitleText().resKey,
    'tag_selector_selected_section_title');
  eq('空提示资源名', TagSelectorActivity.emptySelectionText().resKey,
    'tag_selector_empty_selected');
}

// ---------------------------------------------------------------- 主题色

function testColors(): void {
  const dark: TagSelectorColors = TagSelectorColors.of(true);
  eq('深色 chip 背景', dark.selectedChipBg, '#AD1457');
  eq('深色网格背景', dark.gridBackground, '#121212');
  const light: TagSelectorColors = TagSelectorColors.of(false);
  eq('浅色 chip 背景', light.selectedChipBg, '#F48FB1');
  eq('浅色不设网格背景（空串）', light.gridBackground, '');
  eq('浅色选中文字为白', light.selectedChipText, '#FFFFFF');
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testConstants();
  testEnvironment();
  testUtils();
  testGroups();
  testAddPinnedDedup();
  testBatches();
  testNormalize();
  testApplyBatch();
  testRows();
  testSelection();
  testColors();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync tag selector test failed');
  }
  console.log(`✓ download-sync 标签选择页批: ${pass} 条断言全部通过`);
}

main();
