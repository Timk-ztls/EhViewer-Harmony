/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/TagSelectorActivity.java（663 行）。
 *
 * ============================================================================
 * 一、上游是什么（标签选择页）
 * ============================================================================
 * 一个分组的标签网格（3 列）+ 底部"已选"面板：
 *
 *   ```java
 *   分组：Language（12 个语言**写死置顶**）+ Female/Male/Parody/Character/Group/Artist/Cosplayer/Location
 *   每组：先展示 initialCount(=12) 个，footer「▼ More」→ loadNextBatch（visibleCount += 12）
 *        loadNextBatch 的取数靠 **前缀分批**：LOAD_PREFIXES = ["", a..z, 0..9]
 *        每次查 `namespace + ":" + LOAD_PREFIXES[prefixIndex]`，不够 12 个就 prefixIndex++ 再查
 *   选中：selectedTags（LinkedHashMap）—— 点一次加入、再点移除；底部按 namespace 分组显示 chip（xx ×）
 *   确认：把所有 key 用空格拼成一个字符串回传（`selected_tags`）
 *   ```
 *
 * 逐行对照时最容易丢/写反的**七条**（本文件逐条保留并断言）：
 *   1. `LOAD_PREFIXES` 的第 0 项是**空串**（先查全组），然后是 a..z，最后 0..9 ——
 *      顺序与内容都是契约：改顺序会让"More"每次翻到不同批；
 *   2. `loadNextBatch` 的目标是 `visibleCount + 12`；**本地不够才查库**，
 *      且查库时 `visibleCount` 已经先被设成目标值（不是查到后再调）；
 *   3. `collapseGroup` 把 `visibleCount` 拉回 **initialCount**（Language 是 12，其余也是 12）；
 *   4. 前缀查库结果要**双向归一**：`suggest()` 返回的 pair 里哪一侧是 `namespace:tag` 不确定，
 *      两侧都试；都不带 namespace 的**整条丢弃**；
 *   5. 非中文系统**强制英文**（取 `:` 之后部分首字母大写），中文系统才用翻译；
 *      翻译缺失（空 或 与 key 相同）时同样回退英文；
 *   6. **纯 CJK 的 key 直接丢弃**（上游 `isChinese(searchKey)` → continue）——
 *      这是数据清洗，不是翻译；
 *   7. 回传是 `key` 用 **空格** 连接后 `trim()`（不是逗号、不是 URL 编码）。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * 上游 663 行里约 350 行是 Android 视图脚手架（RecyclerView/GridLayoutManager/
 * GradientDrawable/FlexboxLayout/动画）。移植时分三层：
 *
 *   - **状态机 + 判据**（本文件）：分组结构、分批加载计划、前缀推进、suggest 归一、
 *     选中集合、已选面板分组、footer 三态、确认串、3 列 span；
 *   - **标签来源** → 注入 `TagSuggester`（生产实现包 `EhTagDatabase.suggest`）；
 *   - **界面** → 返回 `TagRow`/`UiText` 等纯数据，由 ArkUI 页面渲染（`Grid` + 底部 `Flex`）。
 *
 * 标签翻译**可空**：`TagSuggester` 未注入时标签树照常工作（只有 key 的首字母大写形态），
 * 这对应 Lead 的要求"翻译走注入点，不硬等"。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'TagSelector';

/** 一行数据在列表里的种类（上游 `TYPE_HEADER / TYPE_ITEM / TYPE_FOOTER`）。 */
export enum TagRowKind {
  HEADER = 0,
  ITEM = 1,
  FOOTER = 2
}

/** `suggest()` 返回的一对（上游 `Pair<String, String>`；两侧都可能是 null）。 */
export class TagPair {
  first: string | null;
  second: string | null;

  constructor(first: string | null, second: string | null) {
    this.first = first;
    this.second = second;
  }
}

/** 标签项（上游 `static class TagItem`）。 */
export class TagItem {
  /** 完整 key（`namespace:tag`）。 */
  key: string;
  /** 显示文案（翻译或英文回退）。 */
  show: string;
  /** 是否"置顶写死"（Language 组那 12 个）。 */
  isPinned: boolean;

  constructor(key: string, show: string, isPinned: boolean) {
    this.key = key;
    this.show = show;
    this.isPinned = isPinned;
  }
}

/** 分组（上游 `static class TagGroup`）。 */
export class TagGroup {
  title: string;
  namespace: string;
  /** 折叠后的最少展示数（上游 `initialCount`）。 */
  initialCount: number;
  /** 当前要展示多少个（上游 `visibleCount`）。 */
  visibleCount: number;
  /** `LOAD_PREFIXES` 的推进下标（上游 `prefixIndex`）。 */
  prefixIndex: number;
  loadedTags: TagItem[];
  /** 已加入的 key（去重用；上游 `HashSet<String> addedKeys`）。 */
  addedKeys: Set<string>;

  constructor(title: string, namespace: string, count: number) {
    this.title = title;
    this.namespace = namespace;
    this.initialCount = count;
    this.visibleCount = count;
    this.prefixIndex = 0;
    this.loadedTags = [];
    this.addedKeys = new Set<string>();
  }

  /** 写死一个置顶项（上游 `addPinned`）：key = `namespace:key`，重复则忽略。 */
  addPinned(key: string, display: string): void {
    const full: string = `${this.namespace}:${key}`;
    if (!this.addedKeys.has(full)) {
      this.loadedTags.push(new TagItem(full, display, true));
      this.addedKeys.add(full);
    }
  }
}

/** footer 行携带的分组引用（上游 `FooterItem`）。 */
export class FooterItem {
  group: TagGroup;

  constructor(group: TagGroup) {
    this.group = group;
  }
}

/** footer 的三种状态（上游 `onBindViewHolder` 里那段 if）。 */
export enum FooterState {
  /** 还有更多可加载：显示「▼ More」 */
  MORE = 0,
  /** 已经到底：显示「--- End ---」且禁用 */
  END = 1
}

/** 已选面板的一个分组（上游 `SelectedTagGroup`：标题 + 若干 (key, show)）。 */
export class SelectedTagGroup {
  title: string;
  entries: TagPair[];

  constructor(title: string, entries: TagPair[]) {
    this.title = title;
    this.entries = entries;
  }
}

/** 一条渲染行（页面按 kind 决定画 header / tag / footer）。 */
export class TagRow {
  kind: TagRowKind;
  /** HEADER/FOOTER 用 */
  group: TagGroup | null;
  /** ITEM 用 */
  item: TagItem | null;
  /** ITEM 是否已选中（上游 `selectedTags.containsKey`） */
  selected: boolean;

  constructor(kind: TagRowKind, group: TagGroup | null, item: TagItem | null, selected: boolean) {
    this.kind = kind;
    this.group = group;
    this.item = item;
    this.selected = selected;
  }
}

/** 文案（资源名 + 参数），由页面按当前语言取字符串。 */
export class UiText {
  resKey: string;
  args: (string | number)[];

  constructor(resKey: string, args: (string | number)[]) {
    this.resKey = resKey;
    this.args = args;
  }

  static of(resKey: string, ...args: (string | number)[]): UiText {
    return new UiText(resKey, args);
  }
}

/** 主题色（上游 `initView` / `initColors` 的两套常量）。 */
export class TagSelectorColors {
  selectedChipBg: string = '';
  selectedChipText: string = '';
  selectedGroupHeader: string = '';
  selectedSectionTitle: string = '';
  selectedEmptyText: string = '';
  /** 深色模式下网格背景（浅色模式为空串 = 不设） */
  gridBackground: string = '';
  /** 深色模式下已选卡片背景（浅色模式为空串） */
  cardBackground: string = '';
  selectedBg: string = '';
  unselectedBg: string = '';
  unselectedText: string = '';
  unselectedBorder: string = '';
  headerColor: string = '';
  footerColor: string = '';

  /** 按深色/浅色生成两套色（逐字对齐上游 `Color.parseColor` 的取值）。 */
  static of(isDarkMode: boolean): TagSelectorColors {
    const c: TagSelectorColors = new TagSelectorColors();
    if (isDarkMode) {
      c.selectedChipBg = '#AD1457';
      c.selectedChipText = '#FFFFFF';
      c.selectedGroupHeader = '#F48FB1';
      c.selectedSectionTitle = '#E0E0E0';
      c.selectedEmptyText = '#808080';       // Color.GRAY
      c.gridBackground = '#121212';
      c.cardBackground = '#1E1E1E';
      c.selectedBg = '#AD1457';
      c.unselectedBg = '#424242';
      c.unselectedText = '#E0E0E0';
      c.unselectedBorder = '#616161';
      c.headerColor = '#F48FB1';
      c.footerColor = '#808080';
    } else {
      c.selectedChipBg = '#F48FB1';
      c.selectedChipText = '#FFFFFF';
      c.selectedGroupHeader = '#424242';
      c.selectedSectionTitle = '#212121';
      c.selectedEmptyText = '#757575';
      c.gridBackground = '';
      c.cardBackground = '';
      c.selectedBg = '#F48FB1';
      c.unselectedBg = '#FFFFFF';
      c.unselectedText = '#212121';
      c.unselectedBorder = '#BDBDBD';
      c.headerColor = '#424242';
      c.footerColor = '#808080';
    }
    return c;
  }
}

/**
 * 标签来源（生产实现包 `EhTagDatabase.suggest`）。
 *
 * **可空**：不注入时标签树照常可用（只有 key 首字母大写形态），只是没有翻译。
 */
export interface TagSuggester {
  suggest(prefix: string): TagPair[] | null;
}

/**
 * 标签选择页的状态机（对位上游 `TagSelectorActivity`）。
 */
export class TagSelectorActivity {
  /** 分批加载的前缀序列（上游 `LOAD_PREFIXES`）：**空串在最前**，然后 a..z，再 0..9。 */
  public static readonly LOAD_PREFIXES: string[] = [
    '', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
  ];

  /** Language 组写死置顶的 12 个语言（顺序即展示顺序）。 */
  public static readonly TOP_LANGUAGES: string[] = [
    'chinese', 'japanese', 'korean', 'english', 'russian', 'spanish',
    'portuguese', 'french', 'german', 'polish', 'thai', 'vietnamese'
  ];

  /** 中文系统下这 12 个语言的显示名（上游 `getDisplayLanguage` 的 switch）。 */
  private static readonly LANGUAGE_ZH: Map<string, string> = new Map<string, string>([
    ['chinese', '中文'], ['japanese', '日语'], ['korean', '韩语'], ['english', '英语'],
    ['russian', '俄语'], ['spanish', '西班牙语'], ['portuguese', '葡萄牙语'],
    ['french', '法语'], ['german', '德语'], ['polish', '波兰语'],
    ['thai', '泰语'], ['vietnamese', '越南语']
  ]);

  /** 标准分组（namespace + 标题 + 初始展示数 12）。 */
  public static readonly STANDARD_GROUPS: string[][] = [
    ['Female', 'female'], ['Male', 'male'], ['Parody', 'parody'],
    ['Character', 'character'], ['Group', 'group'], ['Artist', 'artist'],
    ['Cosplayer', 'cosplayer'], ['Location', 'location']
  ];

  /** 每次「More」增加的数量（上游 `visibleCount + 12`）。 */
  public static readonly PAGE_STEP: number = 12;
  /** 网格列数（上游 `GridLayoutManager(this, 3)`）。 */
  public static readonly GRID_SPAN: number = 3;

  /** 分组列表（上游 `allGroups`）。 */
  groups: TagGroup[] = [];
  /** 已选：key → 显示名（上游 `LinkedHashMap selectedTags`，**保持插入顺序**）。 */
  selectedTags: Map<string, string> = new Map<string, string>();
  /** 是否中文系统（决定显示翻译还是英文）。 */
  isChineseSystem: boolean = true;

  // ------------------------------------------------------------------ 判据

  /**
   * 系统语言是否算"中文"（上游 `Settings.getAppLanguage().contains("zh")`）。
   * 注意是 `contains("zh")` 而不是 `startsWith` —— `zh-TW`、`zh_CN` 都命中。
   */
  static isChineseLanguage(appLanguage: string): boolean {
    return appLanguage.includes('zh');
  }

  /** 取 namespace（上游 `extractNamespace`）：`:` 之前；无冒号或冒号在第 0 位 → 空串。 */
  static extractNamespace(key: string | null): string {
    if (key === null) {
      return '';
    }
    const idx: number = key.indexOf(':');
    return idx > 0 ? key.substring(0, idx) : '';
  }

  /** 首字母大写（上游 `key.substring(0,1).toUpperCase() + key.substring(1)`）。 */
  static capitalize(s: string): string {
    if (s.length === 0) {
      return s;
    }
    return s.substring(0, 1).toUpperCase() + s.substring(1);
  }

  /**
   * 是否含 CJK 统一表意文字（上游 `isChinese(String)`：逐字符比 `UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS`）。
   *
   * 该 block 的区间是 **U+4E00–U+9FFF**；扩展区（U+3400、U+20000+）上游**不认**，这里也不认。
   */
  static containsCjk(s: string | null): boolean {
    if (s === null) {
      return false;
    }
    for (let i = 0; i < s.length; i++) {
      const code: number = s.charCodeAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) {
        return true;
      }
    }
    return false;
  }

  /**
   * Language 组里某个语言的显示名（上游 `getDisplayLanguage`）。
   *
   * 非中文系统 → 一律首字母大写（**不走翻译表**）；中文系统 → 查 12 条硬编码，缺省首字母大写。
   */
  static displayLanguageFor(key: string, isChineseSystem: boolean): string {
    if (!isChineseSystem) {
      return TagSelectorActivity.capitalize(key);
    }
    const zh: string | undefined = TagSelectorActivity.LANGUAGE_ZH.get(key);
    return zh === undefined ? TagSelectorActivity.capitalize(key) : zh;
  }

  // ------------------------------------------------------------------ 分组结构

  /**
   * 建立分组结构（上游 `initGroupsStructure`）。
   *
   * Language 组：12 个写死语言，`initialCount = visibleCount = 12`；
   * 其余 8 组：`initialCount = visibleCount = 12`。
   * 上游建完后**只预加载非 Language 组**（Language 组要用户点 More 才查库）。
   */
  initGroups(isChineseSystem: boolean): void {
    this.isChineseSystem = isChineseSystem;
    this.groups = [];
    const lang: TagGroup = new TagGroup('Language', 'language', 12);
    for (let i = 0; i < TagSelectorActivity.TOP_LANGUAGES.length; i++) {
      const key: string = TagSelectorActivity.TOP_LANGUAGES[i];
      lang.addPinned(key, TagSelectorActivity.displayLanguageFor(key, isChineseSystem));
    }
    lang.initialCount = 12;
    lang.visibleCount = 12;
    this.groups.push(lang);
    for (let i = 0; i < TagSelectorActivity.STANDARD_GROUPS.length; i++) {
      const pair: string[] = TagSelectorActivity.STANDARD_GROUPS[i];
      this.groups.push(new TagGroup(pair[0], pair[1], 12));
    }
  }

  /** 需要预加载的分组（上游：建完结构后对所有非 language 组 `loadNextBatch`）。 */
  groupsToPreload(): TagGroup[] {
    const out: TagGroup[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].namespace !== 'language') {
        out.push(this.groups[i]);
      }
    }
    return out;
  }

  /** 当前批次要查的前缀（`namespace + ":" + LOAD_PREFIXES[prefixIndex]`）；越界 → null。 */
  static prefixFor(group: TagGroup): string | null {
    if (group.prefixIndex >= TagSelectorActivity.LOAD_PREFIXES.length) {
      return null;
    }
    return `${group.namespace}:${TagSelectorActivity.LOAD_PREFIXES[group.prefixIndex]}`;
  }

  /** `loadNextBatch` 的计划（上游那两分支）。 */
  static planNextBatch(group: TagGroup): BatchPlan {
    const targetCount: number = group.visibleCount + TagSelectorActivity.PAGE_STEP;
    if (group.loadedTags.length >= targetCount) {
      // 本地缓存够 → 只改 visibleCount 并刷新
      return new BatchPlan(targetCount, false, true);
    }
    // 本地不够 → 先设 targetCount，再决定查不查库
    if (group.prefixIndex < TagSelectorActivity.LOAD_PREFIXES.length) {
      return new BatchPlan(targetCount, true, false);
    }
    // 前缀用尽了：visibleCount 收敛到实际数量
    return new BatchPlan(group.loadedTags.length, false, true);
  }

  /** `collapseGroup`：visibleCount 回到 initialCount。 */
  static collapse(group: TagGroup): void {
    group.visibleCount = group.initialCount;
  }

  // ------------------------------------------------------------------ 查库结果归一

  /**
   * 把 `suggest()` 的结果归一成 `TagItem[]`（上游 `LoadTagsTask.doInBackground`）。
   *
   * 归一规则（顺序不能变）：
   *   ① 谁带 `namespace:` 谁是 key；都不带 → **整条丢弃**；
   *   ② `shortName` = `:` 之后的部分；
   *   ③ 非中文系统 → 强制英文（`shortName` 首字母大写）；
   *      中文系统 → 有翻译用翻译（若翻译里还带 `:` 则取后半），没翻译回退英文；
   *   ④ **纯 CJK 的 key 丢弃**（数据清洗）。
   */
  static normalizeSuggest(group: TagGroup, pairs: TagPair[] | null, isChineseSystem: boolean): TagItem[] {
    const out: TagItem[] = [];
    if (pairs === null) {
      return out;
    }
    const nsPrefix: string = `${group.namespace}:`;
    for (let i = 0; i < pairs.length; i++) {
      const pair: TagPair = pairs[i];
      const val1: string | null = pair.first;
      const val2: string | null = pair.second;
      let searchKey: string | null;
      let displayName: string | null;
      if (val1 !== null && val1.startsWith(nsPrefix)) {
        searchKey = val1;
        displayName = val2;
      } else if (val2 !== null && val2.startsWith(nsPrefix)) {
        searchKey = val2;
        displayName = val1;
      } else {
        searchKey = val1;
        displayName = val2;
      }
      if (searchKey === null || !searchKey.startsWith(nsPrefix)) {
        continue;
      }
      const colon: number = searchKey.indexOf(':');
      const shortName: string = colon >= 0 ? searchKey.substring(colon + 1) : searchKey;
      let show: string;
      if (!isChineseSystem) {
        show = TagSelectorActivity.capitalize(shortName);
      } else if (displayName === null || displayName.length === 0 || displayName === searchKey) {
        show = TagSelectorActivity.capitalize(shortName);
      } else if (displayName.includes(':')) {
        show = displayName.substring(displayName.indexOf(':') + 1);
      } else {
        show = displayName;
      }
      if (TagSelectorActivity.containsCjk(searchKey)) {
        continue;
      }
      out.push(new TagItem(searchKey, show, false));
    }
    return out;
  }

  /**
   * 收下查库结果（上游 `onPostExecute`）：去重加入 → `prefixIndex++` →
   * 若仍不够 `visibleCount` 且前缀未用尽 → 需要继续查；否则收敛 `visibleCount` 并刷新。
   *
   * @returns 是否需要继续查下一批
   */
  static applyBatch(group: TagGroup, items: TagItem[]): boolean {
    for (let i = 0; i < items.length; i++) {
      const item: TagItem = items[i];
      if (!group.addedKeys.has(item.key)) {
        group.loadedTags.push(item);
        group.addedKeys.add(item.key);
      }
    }
    group.prefixIndex++;
    if (group.loadedTags.length < group.visibleCount &&
      group.prefixIndex < TagSelectorActivity.LOAD_PREFIXES.length) {
      return true;
    }
    if (group.visibleCount > group.loadedTags.length) {
      group.visibleCount = group.loadedTags.length;
    }
    return false;
  }

  // ------------------------------------------------------------------ 展示

  /**
   * 构建展示列表（上游 `buildDisplayList`）：每组 = [分组头, 至多 visibleCount 个标签, footer]。
   *
   * `limit = min(visibleCount, loadedTags.length)` —— 两者都可能成为上限
   * （visibleCount 来自「More」的次数，loadedTags 来自实际查到多少）。
   */
  buildRows(): TagRow[] {
    const rows: TagRow[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      const group: TagGroup = this.groups[i];
      rows.push(new TagRow(TagRowKind.HEADER, group, null, false));
      const limit: number = Math.min(group.visibleCount, group.loadedTags.length);
      for (let j = 0; j < limit; j++) {
        const item: TagItem = group.loadedTags[j];
        rows.push(new TagRow(TagRowKind.ITEM, null, item, this.selectedTags.has(item.key)));
      }
      rows.push(new TagRow(TagRowKind.FOOTER, group, null, false));
    }
    return rows;
  }

  /**
   * 3 列网格的 span（上游 `getSpanSize`）：header/footer 占满 3 格，标签占 1 格；
   * **越界返回 1**（上游 `if (position >= displayList.size()) return 1;` —— 保留）。
   */
  static spanSizeOf(rows: TagRow[], position: number): number {
    if (position < 0 || position >= rows.length) {
      return 1;
    }
    const kind: TagRowKind = rows[position].kind;
    return (kind === TagRowKind.HEADER || kind === TagRowKind.FOOTER)
      ? TagSelectorActivity.GRID_SPAN
      : 1;
  }

  /**
   * footer 的状态（上游：`hasMore = prefixIndex < LOAD_PREFIXES.length`；
   * `isExpanded = visibleCount > initialCount`）。
   *
   * 「到底」的判据是 **两个条件的合取**：没有前缀了 **且** 已加载数不超过可见数。
   */
  static footerState(group: TagGroup): FooterUI {
    const hasMore: boolean = group.prefixIndex < TagSelectorActivity.LOAD_PREFIXES.length;
    const isExpanded: boolean = group.visibleCount > group.initialCount;
    if (!hasMore && group.visibleCount >= group.loadedTags.length) {
      return new FooterUI(FooterState.END, isExpanded);
    }
    return new FooterUI(FooterState.MORE, isExpanded);
  }

  // ------------------------------------------------------------------ 选中

  /** 点一个标签（上游 `onBindViewHolder` 的点击）：已选 → 移除并返回 false；否则加入并返回 true。 */
  toggle(key: string, show: string): boolean {
    if (this.selectedTags.has(key)) {
      this.selectedTags.delete(key);
      return false;
    }
    this.selectedTags.set(key, show);
    return true;
  }

  /** 从已选面板移除（上游 chip 的点击）。 */
  removeSelected(key: string): void {
    this.selectedTags.delete(key);
  }

  /**
   * 确认回传串（上游 `btn_confirm_search`）：所有 key 用**空格**连接后 `trim()`。
   *
   * 顺序 = `selectedTags` 的插入顺序（LinkedHashMap 语义；JS `Map` 同样保序）。
   */
  selectedQueryText(): string {
    const parts: string[] = [];
    this.selectedTags.forEach((_show: string, key: string): void => {
      parts.push(key);
    });
    return parts.join(' ').trim();
  }

  /**
   * 已选面板按 namespace 分组（上游 `rebuildSelectedGroups`）。
   *
   * 排序规则：先按 `allGroups` 的顺序，未在 groups 里的 namespace 追加在后（保持插入序）。
   */
  rebuildSelectedGroups(): SelectedTagGroup[] {
    const out: SelectedTagGroup[] = [];
    if (this.selectedTags.size === 0) {
      return out;
    }
    const byNs: Map<string, TagPair[]> = new Map<string, TagPair[]>();
    this.selectedTags.forEach((show: string, key: string): void => {
      const ns: string = TagSelectorActivity.extractNamespace(key);
      let list: TagPair[] | undefined = byNs.get(ns);
      if (list === undefined) {
        list = [];
        byNs.set(ns, list);
      }
      list.push(new TagPair(key, show));
    });
    const ordered: string[] = [];
    for (let i = 0; i < this.groups.length; i++) {
      const ns: string = this.groups[i].namespace;
      if (byNs.has(ns)) {
        ordered.push(ns);
      }
    }
    byNs.forEach((_list: TagPair[], ns: string): void => {
      if (!ordered.includes(ns)) {
        ordered.push(ns);
      }
    });
    for (let i = 0; i < ordered.length; i++) {
      const ns: string = ordered[i];
      out.push(new SelectedTagGroup(TagSelectorActivity.namespaceTitle(ns, this.groups),
        byNs.get(ns) as TagPair[]));
    }
    return out;
  }

  /**
   * namespace 的标题（上游 `resolveNamespaceTitle`）：
   * 空 → `tag_selector_other_group`；命中分组 → 组标题；否则首字母大写。
   */
  static namespaceTitle(namespace: string, groups: TagGroup[]): string {
    if (namespace.length === 0) {
      return 'tag_selector_other_group';
    }
    for (let i = 0; i < groups.length; i++) {
      if (groups[i].namespace === namespace) {
        return groups[i].title;
      }
    }
    return TagSelectorActivity.capitalize(namespace);
  }

  /** 已选面板是否显示"空"提示、是否显示已选列表（上游 `refreshSelectedPanel`）。 */
  isEmptySelection(): boolean {
    return this.selectedTags.size === 0;
  }

  /** 页面级文案（上游 `initView` 里两处 setText）。 */
  static sectionTitleText(): UiText {
    return UiText.of('tag_selector_selected_section_title');
  }

  static emptySelectionText(): UiText {
    return UiText.of('tag_selector_empty_selected');
  }

  /** 环境判定（上游 `checkSystemEnvironment`）：中文系统标记。 */
  static resolveChineseSystem(appLanguage: string): boolean {
    // 上游 `Settings.getAppLanguage()` 尚未在 Settings 导出 → 语言值由调用方传入
    // （与"依赖未落地时先问能不能变成参数"一致：这样本规则现在就能用、也能断言）。
    const chinese: boolean = TagSelectorActivity.isChineseLanguage(appLanguage);
    hilog.info(DOMAIN, TAG, 'appLanguage=%{public}s → chinese tags: %{public}s',
      appLanguage, `${chinese}`);
    return chinese;
  }
}

/** `planNextBatch` 的结果。 */
export class BatchPlan {
  /** 本次之后 `visibleCount` 应该变成多少。 */
  targetCount: number;
  /** 是否需要去查库。 */
  needQuery: boolean;
  /** 是否需要刷新列表。 */
  refresh: boolean;

  constructor(targetCount: number, needQuery: boolean, refresh: boolean) {
    this.targetCount = targetCount;
    this.needQuery = needQuery;
    this.refresh = refresh;
  }
}

/** footer 的渲染信息。 */
export class FooterUI {
  state: FooterState;
  /** 「收起」按钮是否可见（上游 `tvCollapse.setVisibility(isExpanded ? VISIBLE : GONE)`）。 */
  showCollapse: boolean;

  constructor(state: FooterState, showCollapse: boolean) {
    this.state = state;
    this.showCollapse = showCollapse;
  }
}
