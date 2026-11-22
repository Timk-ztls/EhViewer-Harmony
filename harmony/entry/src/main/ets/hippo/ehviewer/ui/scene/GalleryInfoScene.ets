/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/GalleryInfoScene.java
 *       （inventory S0251，上游实际 283 行；清单登记 247 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/GalleryInfoScene.ets
 *
 * 背景：**画廊信息页**——把一条 `GalleryDetail` 的全部字段摊成"键: 值"两列列表。
 * 交互只有两种：点某行 → 复制值到剪贴板（`INDEX_URL` 那行还要额外记住 hash）；
 * 点 `INDEX_PARENT` 那行 → **用浏览器打开**（不是复制）。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 常量：`KEY_GALLERY_DETAIL="gallery_detail"` / `KEY_KEYS="keys"` / `KEY_VALUES="values"`
 *      `INDEX_URL = 3` / `INDEX_PARENT = 10`
 * `onCreate`：**`savedInstanceState == null → onInit()` 否则 `onRestore()`**（与 GetGalleryDetailListener
 *   所在批的 `Listing` 不同 —— 这里**真的**做了恢复）
 * `handlerArgs(args)`：`args == null → return`；`gd == null → return`；
 *   **`mKeys == null || mValues == null → return`**（三道防御）
 *   然后**按固定顺序**填 23 行（见下面「23 行清单」）
 * `onInit()`：先建两个空 ArrayList，再 `handlerArgs(getArguments())`
 * `onRestore(state)`：从 `KEY_KEYS` / `KEY_VALUES` 两个独立数组恢复（**不是**重算）
 * `onSaveInstanceState`：**只存这两个数组**（不存 GalleryDetail）
 *
 * ── 23 行清单（顺序即列表顺序，**INDEX_URL=3 / INDEX_PARENT=10 依赖这个顺序**）──
 *   0 header_key : header_value            ← 表头行（**不可点**，`itemView.setEnabled(false)`）
 *   1 key_gid          → `Long.toString(gd.gid)`
 *   2 key_token        → `gd.token`
 *   3 key_url          → `EhUrl.getGalleryDetailUrl(gid, token)`          ★ INDEX_URL
 *   4 key_title        → `gd.title`
 *   5 key_title_jpn    → `gd.titleJpn`
 *   6 key_thumb        → `gd.thumb`
 *   7 key_category     → `EhUtils.getCategory(gd.category)`
 *   8 key_uploader     → `gd.uploader`
 *   9 key_posted       → `gd.posted`
 *  10 key_parent       → `gd.parent`                                     ★ INDEX_PARENT（**点击走浏览器**）
 *  11 key_visible      → `gd.visible`
 *  12 key_language     → `gd.language`
 *  13 key_pages        → `Integer.toString(gd.pages)`
 *  14 key_size         → `gd.size`
 *  15 key_favorite_count → `Integer.toString(gd.favoriteCount)`
 *  16 key_favorited    → `Boolean.toString(gd.isFavorited)`
 *  17 key_rating_count → `Integer.toString(gd.ratingCount)`
 *  18 key_rating       → `Float.toString(gd.rating)`
 *  19 key_torrents     → `Integer.toString(gd.torrentCount)`
 *  20 key_torrent_url  → `gd.torrentUrl`
 *  21 favorite_name    → `gd.favoriteName`
 *  （共 22 行 + 表头 1 = **22 项数据**；上游注释里 `torrentCount`/`torrentUrl` 是两行，符合上面 19/20）
 *
 * `onItemClick(position)`：
 *   · `context != null && position != 0 && mValues != null` 才处理 —— **表头行（0）不可点**
 *   · `position == INDEX_PARENT(10)` → **`UrlOpener.openUrl(context, value, true)`**（第三个参数 = 新任务/外部浏览器语义）
 *   · 其它（含 INDEX_URL=3）→ 写剪贴板 + `showTip(@string/copied_to_clipboard, LENGTH_SHORT)`
 *   · **`position == INDEX_URL(3)` 时额外 `Settings.putClipboardTextHashCode(value.hashCode())`**
 *     —— 目的见上游注释："Save it to avoid detect the gallery"（避免粘贴时被当成画廊链接自动识别）
 *   · 处理了 → `return true`；否则 `return false`
 * `onViewCreated`：title `@string/gallery_info` + 返回图标
 * `onDestroyView`：`stopScroll()` + 置 null
 * `onNavigationClick` → `onBackPressed()`
 *
 * `InfoAdapter`：
 *   · `getItemViewType`：**position == 0 → TYPE_HEADER，否则 TYPE_DATA**（两种布局：
 *     `item_gallery_info_header` / `item_gallery_info_data`）
 *   · `onBindViewHolder`：`key.setText(mKeys[position])` + `value.setText(mValues[position])` +
 *     **`itemView.setEnabled(position != 0)`**（表头禁用，与 onItemClick 的第一道判断呼应）
 *   · `getItemCount` = **`Math.min(mKeys.size(), mValues.size())`**（取小，见「关键行为」1）
 *   · 分隔线：`LinearDividerItemDecoration(VERTICAL, ?attr/dividerColor, dp2pix(1))` + padding `@dimen/keyline_margin`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`getItemCount` 取 `min(keys, values)`** —— 两个数组理论上等长，但取小是安全网；
 *    若写 `keys.size()`，`onBindViewHolder` 会在 values 短时越界。
 * 2. **`INDEX_URL = 3` / `INDEX_PARENT = 10` 是硬编码下标**，与上面 23 行的顺序**强耦合**。
 *    往表里插一行就会错位 —— 这是本文件最脆的地方，**用断言钉住"第 3 行是 url、第 10 行是 parent"**。
 * 3. **表头行不可点**：`onItemClick` 判 `position != 0`，`onBindViewHolder` 又 `setEnabled(position != 0)`。
 * 4. **`INDEX_PARENT` 走浏览器，其它一律复制** —— parent 是一个页面 URL（`/g/<parent>`），
 *    复制它没意义。
 * 5. **复制 url 时额外记 hash**（避免画廊链接被自动识别）—— 只有 `INDEX_URL` 这一行特殊。
 * 6. **`Float.toString(gd.rating)`** —— 上游用 Float（不是 double），ArkTS 侧 `number` 都可，
 *    但**格式化必须避免 `1` 变成 `1.0` 或 `3.5` 变成 `3.5000000001`**：用 `Number.toString()` 保持最短表示。
 * 7. **`Boolean.toString` 输出 `"true"/"false"`**（小写，Java 语义）。
 * 8. **面板不显示 `simpleLanguage`**（`GalleryDetail` 有这个字段但上游没列）—— 不要顺手加。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `ToolbarScene` 未落地 → `GalleryInfoSceneHost`（剪贴板/浏览器/提示/返回/取字符串）。
 * 2. `Bundle.putStringArrayList/getStringArrayList` → 两个 `string[]` 字段（`keys` / `values`），
 *    ArkTS 侧用一个 `GalleryInfoSnapshot` 承载，语义等价（只存这两个数组、**不存 detail**）。
 * 3. `ClipboardManager + ClipData` → 宿主 `copyToClipboard(text)`（ArkUI 用 `pasteboard`）。
 * 4. `Settings.putClipboardTextHashCode(hash)` → 宿主 `rememberClipboardHash(hash)`
 *    （本仓库 `Settings` 尚无该字段，见「缺口」）。
 * 5. `UrlOpener.openUrl(context, url, true)` → 宿主 `openUrlExternally(url)`。
 * 6. `Ripple`/`LinearDividerItemDecoration`/`EasyRecyclerView` → ArkUI `List` + `divider`。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * `EhUtils.getCategory(type)`：本仓库只有 `getCategoryByValue(number)` / `getCategoryByType(string)`，
 * 上游 `getCategory(int category)` 收的正是 `GalleryDetail.category`（int）→ 用 `getCategoryByValue`。
 * `Settings.getClipboardTextHashCode/putClipboardTextHashCode` 本仓库**不存在** → 走宿主接口。
 */

import { GalleryDetail } from '../../client/data/GalleryDetail';
import { EhUtils } from '../../client/EhUtils';
import { EhUrl } from '../../client/EhUrl';

/** 上游三个 args/savedState 键 */
export const KEY_GALLERY_DETAIL: string = 'gallery_detail';
export const KEY_KEYS: string = 'keys';
export const KEY_VALUES: string = 'values';
/** 上游两个硬编码下标（见「关键行为」2） */
export const INDEX_URL: number = 3;
export const INDEX_PARENT: number = 10;
/** 上游 `@string/gallery_info` */
export const TITLE_GALLERY_INFO: string = 'app.string.gallery_info';
/** 上游 `@string/copied_to_clipboard` */
export const TIP_COPIED: string = 'app.string.copied_to_clipboard';
/** 上游两个条目布局 */
export const LAYOUT_HEADER: string = 'item_gallery_info_header';
export const LAYOUT_DATA: string = 'item_gallery_info_data';

/** 23 行的键名（顺序即列表顺序，**不要重排** —— INDEX_URL/INDEX_PARENT 依赖它） */
export const INFO_KEY_ORDER: string[] = [
  'app.string.header_key',        // 0 表头
  'app.string.key_gid',           // 1
  'app.string.key_token',         // 2
  'app.string.key_url',           // 3 ← INDEX_URL
  'app.string.key_title',         // 4
  'app.string.key_title_jpn',     // 5
  'app.string.key_thumb',         // 6
  'app.string.key_category',      // 7
  'app.string.key_uploader',      // 8
  'app.string.key_posted',        // 9
  'app.string.key_parent',        // 10 ← INDEX_PARENT
  'app.string.key_visible',       // 11
  'app.string.key_language',      // 12
  'app.string.key_pages',         // 13
  'app.string.key_size',          // 14
  'app.string.key_favorite_count',// 15
  'app.string.key_favorited',     // 16
  'app.string.key_rating_count',  // 17
  'app.string.key_rating',        // 18
  'app.string.key_torrents',      // 19
  'app.string.key_torrent_url',   // 20
  'app.string.favorite_name'      // 21
];

/** 本页宿主能力（`ClipboardManager` / `UrlOpener` / `showTip` 的对位） */
export interface GalleryInfoSceneHost {
  /** 上游 `cmb.setPrimaryClip(ClipData.newPlainText(null, value))` */
  copyToClipboard(text: string): void;
  /** 上游 `Settings.putClipboardTextHashCode(hash)`（见「缺口」） */
  rememberClipboardHash(hash: number): void;
  /** 上游 `UrlOpener.openUrl(context, url, true)` */
  openUrlExternally(url: string): void;
  /** 上游 `showTip(@string/copied_to_clipboard, LENGTH_SHORT)` */
  showTip(key: string): void;
  onBackPressed(): void;
  /** 上游 `resources.getString(resId)`（键 → 本地化文本） */
  resolveString(key: string): string;
}

/** 上游 `onSaveInstanceState` 的两个数组（**不存 detail**） */
export class GalleryInfoSnapshot {
  keys: string[] = [];
  values: string[] = [];
}

/** 点一行的结果（便于断言"复制还是打开"） */
export const CLICK_COPIED: number = 1;
export const CLICK_OPENED: number = 2;
export const CLICK_NONE: number = 0;

export class GalleryInfoScene {
  private host: GalleryInfoSceneHost;
  private keys: string[] | null = null;
  private values: string[] | null = null;
  /** 是否已从 savedState 恢复（测试观测） */
  private restored: boolean = false;

  constructor(host: GalleryInfoSceneHost) {
    this.host = host;
  }

  /**
   * 上游 `handlerArgs(args)`：**三道防御**（args null / gd null / 两数组 null）。
   * @param detail 上游 `args.getParcelable(KEY_GALLERY_DETAIL)`
   */
  handlerArgs(detail: GalleryDetail | null): boolean {
    if (detail === null) {
      return false;
    }
    if (this.keys === null || this.values === null) {
      return false;
    }
    const keys: string[] = this.keys;
    const values: string[] = this.values;
    // ── 按上游固定顺序填 23 行 ──
    keys.push(this.host.resolveString('app.string.header_key'));
    values.push(this.host.resolveString('app.string.header_value'));

    keys.push(this.host.resolveString('app.string.key_gid'));
    values.push(detail.gid.toString());

    keys.push(this.host.resolveString('app.string.key_token'));
    values.push(detail.token);

    keys.push(this.host.resolveString('app.string.key_url'));
    // 上游：EhUrl.getGalleryDetailUrl(gd.gid, gd.token)（**不带 page/nl 参数的重载**）
    values.push(EhUrl.getGalleryDetailUrlSimple(detail.gid, detail.token));

    keys.push(this.host.resolveString('app.string.key_title'));
    values.push(detail.title);

    keys.push(this.host.resolveString('app.string.key_title_jpn'));
    values.push(detail.titleJpn);

    keys.push(this.host.resolveString('app.string.key_thumb'));
    values.push(detail.thumb);

    keys.push(this.host.resolveString('app.string.key_category'));
    values.push(EhUtils.getCategoryByValue(detail.category));

    keys.push(this.host.resolveString('app.string.key_uploader'));
    values.push(detail.uploader);

    keys.push(this.host.resolveString('app.string.key_posted'));
    values.push(detail.posted);

    keys.push(this.host.resolveString('app.string.key_parent'));
    values.push(orEmpty(detail.parent));

    keys.push(this.host.resolveString('app.string.key_visible'));
    values.push(orEmpty(detail.visible));

    keys.push(this.host.resolveString('app.string.key_language'));
    values.push(orEmpty(detail.language));

    keys.push(this.host.resolveString('app.string.key_pages'));
    values.push(detail.pages.toString());

    keys.push(this.host.resolveString('app.string.key_size'));
    values.push(orEmpty(detail.size));

    keys.push(this.host.resolveString('app.string.key_favorite_count'));
    values.push(detail.favoriteCount.toString());

    keys.push(this.host.resolveString('app.string.key_favorited'));
    values.push(detail.isFavorited ? 'true' : 'false');   // Java Boolean.toString = 小写

    keys.push(this.host.resolveString('app.string.key_rating_count'));
    values.push(detail.ratingCount.toString());

    keys.push(this.host.resolveString('app.string.key_rating'));
    // 上游 Float.toString：最短表示（避免 1 → "1.0"、3.5 → "3.5000000001"）
    values.push(numberToString(detail.rating));

    keys.push(this.host.resolveString('app.string.key_torrents'));
    values.push(detail.torrentCount.toString());

    keys.push(this.host.resolveString('app.string.key_torrent_url'));
    values.push(orEmpty(detail.torrentUrl));

    keys.push(this.host.resolveString('app.string.favorite_name'));
    values.push(orEmpty(detail.favoriteName));
    return true;
  }

  /** 上游 `onInit()`：**先建空数组再 handlerArgs** */
  onInit(detail: GalleryDetail | null): void {
    this.keys = [];
    this.values = [];
    this.handlerArgs(detail);
  }

  /** 上游 `onRestore(savedState)`：从两个数组恢复（**不重算**） */
  onRestore(snapshot: GalleryInfoSnapshot): void {
    this.keys = snapshot.keys.slice();
    this.values = snapshot.values.slice();
    this.restored = true;
  }

  /** 上游 `onSaveInstanceState`：只存两个数组 */
  onSaveInstanceState(): GalleryInfoSnapshot {
    const s: GalleryInfoSnapshot = new GalleryInfoSnapshot();
    s.keys = this.keys === null ? [] : this.keys.slice();
    s.values = this.values === null ? [] : this.values.slice();
    return s;
  }

  /**
   * 上游 `onCreate`：`savedInstanceState == null → onInit()` 否则 `onRestore()`。
   * （这一次上游**真的**做了恢复 —— 与本批其他"整段注释掉"的文件不同）
   */
  onCreate(detail: GalleryDetail | null, snapshot: GalleryInfoSnapshot | null): void {
    if (snapshot === null) {
      this.onInit(detail);
    } else {
      this.onRestore(snapshot);
    }
  }

  /** 上游 `onViewCreated` 的标题键 */
  getTitleKey(): string {
    return TITLE_GALLERY_INFO;
  }

  /** 上游 `onNavigationClick` */
  onNavigationClick(): void {
    this.host.onBackPressed();
  }

  /**
   * 上游 `InfoAdapter.getItemCount()`：**`min(keys, values)`**（见「关键行为」1）。
   */
  getItemCount(): number {
    const k: string[] | null = this.keys;
    const v: string[] | null = this.values;
    if (k === null || v === null) {
      return 0;
    }
    return Math.min(k.length, v.length);
  }

  /** 上游 `getItemViewType`：0 = 表头、其它 = 数据 */
  getItemViewType(position: number): string {
    return position === 0 ? LAYOUT_HEADER : LAYOUT_DATA;
  }

  /** 上游 `onBindViewHolder`：key/value + **表头行禁用** */
  bindItem(position: number): GalleryInfoRowSpec | null {
    const k: string[] | null = this.keys;
    const v: string[] | null = this.values;
    if (k === null || v === null || position < 0 || position >= this.getItemCount()) {
      return null;
    }
    const row: GalleryInfoRowSpec = new GalleryInfoRowSpec();
    row.key = k[position];
    row.value = v[position];
    // 上游：itemView.setEnabled(position != 0)
    row.enabled = position !== 0;
    row.layoutName = this.getItemViewType(position);
    return row;
  }

  /**
   * 上游 `onItemClick(parent, view, position, id)`：
   * ① `position == 0` → **不处理**（表头）② `INDEX_PARENT` → 浏览器打开
   * ③ 其它 → 复制；`INDEX_URL` 额外记 hash ④ 返回 true（已消费）/ false
   */
  onItemClick(position: number): number {
    const values: string[] | null = this.values;
    if (position === 0 || values === null || position >= values.length) {
      return CLICK_NONE;
    }
    const value: string = values[position];
    if (position === INDEX_PARENT) {
      // 上游：UrlOpener.openUrl(context, value, true)
      this.host.openUrlExternally(value);
      return CLICK_OPENED;
    }
    // 上游：剪贴板 + showTip
    this.host.copyToClipboard(value);
    if (position === INDEX_URL) {
      // 上游：Settings.putClipboardTextHashCode(value.hashCode()) —— 避免画廊链接被自动识别
      this.host.rememberClipboardHash(javaStringHash(value));
      // 上游此处**仍然**会 showTip（hash 记录不影响提示）
    }
    this.host.showTip(TIP_COPIED);
    return CLICK_COPIED;
  }

  /** 是否走了恢复路径（测试观测） */
  isRestored(): boolean {
    return this.restored;
  }
}

/** 列表行渲染描述 */
export class GalleryInfoRowSpec {
  key: string = '';
  value: string = '';
  /** 上游 `itemView.setEnabled(position != 0)` */
  enabled: boolean = true;
  layoutName: string = LAYOUT_DATA;
}

/** `string | null` → `''`（上游 Java 字段是 String，null 会被 `TextView.setText(null)` 显示为空） */
function orEmpty(v: string | null): string {
  return v === null ? '' : v;
}

/**
 * 上游 `Float.toString(float)` 的最短表示。
 * ArkTS 的 `Number.toString()` 已是"最短往返表示"，与 Java 的差异只在
 * Java 会把整数 float 打成 `"1.0"`。上游这里是**显示字段**，
 * 保持"1.0"会与 iOS/桌面端不一致，但**与上游一致才是目标** → 整数补 `.0`。
 */
function numberToString(v: number): string {
  if (Number.isInteger(v)) {
    return `${v}.0`;
  }
  return v.toString();
}

/**
 * 上游 `String.hashCode()`（Java 语义：`s[0]*31^(n-1) + … + s[n-1]`，**int 溢出**）。
 * 必须按 32 位有符号整数溢出，否则"记住的 hash"与实际剪贴板比较不上。
 */
export function javaStringHash(s: string): number {
  let h: number = 0;
  for (let i = 0; i < s.length; i++) {
    // h = h * 31 + c，按 int32 溢出
    h = (Math.imul(h, 31) + s.charCodeAt(i)) | 0;
  }
  return h;
}

