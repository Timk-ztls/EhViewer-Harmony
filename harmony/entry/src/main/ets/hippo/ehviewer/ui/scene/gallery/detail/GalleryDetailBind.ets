/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/detail/GalleryDetailScene.java（2287 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/detail/GalleryDetailScene.ets
 * 清单：S0232。**Part 2（本批）= 头部的 key-value 展示 + 标签组渲染判据 + 评论/预览的"更多"文案判据**
 *
 * ============================================================================
 * Part 2 的上游依据（逐行核过 1000-1220 区间）
 * ============================================================================
 *   ① `bindGalleryDetail`（1022-1044）：title/uploader/category/pages/size/posted/
 *      ratingText/favoredTimes/torrentCount 的**取值与可见性**
 *   ② `bindTags`（1090-1149）：标签组的**前缀映射** + 翻译回落 + 空的可见性
 *   ③ `bindComments`（1151-1184）：**最多 2 条** + 三态文案
 *   ④ 预览集（1210-1215）：同构三态
 *
 * 逐行对照时最容易丢/写反的**六条**（本文件逐条断言）：
 *   1. `pages` 文案是 **`startPage + "/" + pages + "P"`**（`startPage` 从 0 起），
 *      而 `startPage == -1`（未读）时是 **`"0/" + pages + "P"`** —— 两个分支都得出 `0/…`
 *      但**来源不同**（一个是 `-1+1`，一个是字面 0）；移植时合并成一个分支会在"已读但 currentIndex=0"时错；
 *   2. `favoredTimes` / `torrent` 用**复数资源**（`favored_times` / `torrent_count` 带 `%d`）；
 *      且 `favoriteCount`/`torrentCount` 为 0 时**整行隐藏**（上游用 `VISIBLE/GONE`）；
 *   3. 标签组名的翻译键是 **`"n:" + groupName`**（带 `n:` 前缀），而**标签**的翻译键是
 *      **`namespaceToPrefix(groupName) + tagStr`**（前缀映射，不是 `n:`）—— 两套键不同；
 *   4. `namespaceToPrefix` 返回 `null` 时回落 **空串**（不是 `n:`、不是 groupName）；
 *   5. 标签点击用的 `tag` 是 **`groupName + ":" + tagStr`**（全串），而显示用**翻译后的串** ——
 *      点给后端的是全串；
 *   6. 评论"最多 2 条"是 `Math.min(2, comments.length)`，且三态文案是
 *      **空 → no_comments / ≤2 → no_more_comments / >2 → more_comment**（注意 `<=` 而不是 `<`）。
 */

import { GalleryTagGroup } from '../../../../client/data/GalleryTagGroup';
import { GalleryComment } from '../../../../client/data/GalleryComment';
import { EhTagDatabase } from '../../../../client/EhTagDatabase';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'GalleryDetailScene';

/** 评论最多展示条数（上游 `maxShowCount = 2`）。 */
export const MAX_SHOW_COMMENTS: number = 2;
/** 预览最多展示条数（上游同类常量）。 */
export const MAX_SHOW_PREVIEWS: number = 4;

/** 一格 key-value（上游 `mLanguage/mPages/mSize/mPosted/mFavoredTimes/mTorrent` 的投影）。 */
export class KeyValueField {
  /** 上游控件名（`language` / `pages` / `size` / `posted` / `favoredTimes` / `torrent`） */
  id: string = '';
  /** 已经是最终文案（含复数展开） */
  text: string = '';
  /** 上游 `View.VISIBLE/GONE` */
  visible: boolean = true;

  constructor(id: string, text: string, visible: boolean) {
    this.id = id;
    this.text = text;
    this.visible = visible;
  }
}

/** 标签组渲染模型（上游 `gallery_tag_group` 一层 + 内部若干 tag 项）。 */
export class TagGroupView {
  /** 上游 `tg.groupName`（**原名**，点击/翻译都用它做前缀来源） */
  groupName: string = '';
  /** 组名显示串（有翻译用翻译，否则原名） */
  displayName: string = '';
  /** 组内标签 */
  tags: TagChip[] = [];

  constructor(groupName: string, displayName: string, tags: TagChip[]) {
    this.groupName = groupName;
    this.displayName = displayName;
    this.tags = tags;
  }
}

/** 一个标签（显示串 vs 点击串**不同**）。 */
export class TagChip {
  /** 显示串（有翻译用翻译，否则原名） */
  display: string = '';
  /** 点击/长按时给后端与对话框的**全串**：`groupName + ":" + tagStr` */
  fullTag: string = '';

  constructor(display: string, fullTag: string) {
    this.display = display;
    this.fullTag = fullTag;
  }
}

/** 评论/预览区的"更多"状态（上游三态文案）。 */
export enum MoreState {
  /** 空 → no_comments / no_previews */
  NONE = 0,
  /** 全部已展示（≤max）→ no_more_comments / no_more_previews */
  ALL_SHOWN = 1,
  /** 还有更多 → more_comment / more_previews */
  MORE_AVAILABLE = 2
}

/**
 * 详情页头部与区块的判据层（Part 2）。
 *
 * 只做**纯函数**：上游这些都写在 `bind*` 里直接操作 View，这里抽成数据，
 * 由 ArkUI 的 build() 消费（`@Prop` 列表）。这样这一层可以单测。
 */
export class GalleryDetailBind {

  /**
   * `pages` 文案（上游 1073-1084）。
   *
   * **两个分支不能合并**（见头注第 1 条）。
   */
  static pagesText(startPage: number, pages: number): string {
    if (startPage >= 0) {
      return `${startPage + 1}/${pages}P`;
    }
    return `0/${pages}P`;
  }

  /**
   * `favoredTimes`（上游 1043）：`favoriteCount == 0` → 整行隐藏。
   *
   * 上游用 `resources.getString(R.string.favored_times, count)`（复数资源，含 `%d`）。
   */
  static favoredTimesField(favoriteCount: number, formatted: string): KeyValueField {
    if (favoriteCount === 0) {
      return new KeyValueField('favoredTimes', '', false);
    }
    return new KeyValueField('favoredTimes', formatted, true);
  }

  /** `torrent`（上游 1044）：同 `favoredTimes`，0 → 隐藏。 */
  static torrentField(torrentCount: number, formatted: string): KeyValueField {
    if (torrentCount === 0) {
      return new KeyValueField('torrent', '', false);
    }
    return new KeyValueField('torrent', formatted, true);
  }

  /** `language` / `size` / `posted` 三格（上游 1028/1036/1037：直接 setText，总是可见）。 */
  static plainFields(language: string, size: string, posted: string): KeyValueField[] {
    return [
      new KeyValueField('language', language, true),
      new KeyValueField('pages', '', true),      // pages 由 pagesText 单独算
      new KeyValueField('size', size, true),
      new KeyValueField('posted', posted, true)
    ];
  }

  /**
   * 评论文案（上游 1160-1184）。
   *
   * 三态判据：**空 → NONE；`length <= max` → ALL_SHOWN；否则 MORE_AVAILABLE**。
   * 注意是 `<=`（等于 max 时也是"没有更多"）。
   */
  static moreStateOf(count: number, max: number): MoreState {
    if (count <= 0) {
      return MoreState.NONE;
    }
    return count <= max ? MoreState.ALL_SHOWN : MoreState.MORE_AVAILABLE;
  }

  /** 该状态的文案资源名（评论区）。 */
  static commentStateRes(state: MoreState): string {
    switch (state) {
      case MoreState.NONE:
        return 'no_comments';
      case MoreState.ALL_SHOWN:
        return 'no_more_comments';
      default:
        return 'more_comment';
    }
  }

  /** 该状态的文案资源名（预览区，与评论**同构但键不同**）。 */
  static previewStateRes(state: MoreState): string {
    switch (state) {
      case MoreState.NONE:
        return 'no_previews';
      case MoreState.ALL_SHOWN:
        return 'no_more_previews';
      default:
        return 'more_previews';
    }
  }

  /** 实际要渲染的评论条数（上游 `Math.min(maxShowCount, comments.length)`）。 */
  static shownCount(count: number, max: number): number {
    return count < max ? count : max;
  }

  /**
   * 标签组渲染模型（上游 `bindTags` 1090-1149）。
   *
   * **两套翻译键**（头注第 3 条）：
   *   组名 → `"n:" + groupName`
   *   标签 → `namespaceToPrefix(groupName) + tagStr`（前缀映射，`null` 回落空串）
   *
   * @param translate 注入的翻译查询（`EhTagDatabase.getTranslation(key)`，未启用翻译时传 null）
   * @param prefixOf  注入的 `EhTagDatabase.namespaceToPrefix(groupName)`
   */
  static buildTagGroups(tagGroups: GalleryTagGroup[] | null,
    translate: ((key: string) => string | null) | null,
    prefixOf: (groupName: string) => string | null): TagGroupView[] {
    if (tagGroups === null || tagGroups.length === 0) {
      return [];
    }
    const out: TagGroupView[] = [];
    for (let i = 0; i < tagGroups.length; i++) {
      const tg: GalleryTagGroup = tagGroups[i];
      let readableName: string | null = null;
      if (translate !== null) {
        readableName = translate(`n:${tg.groupName}`);
      }
      const displayName: string = readableName !== null ? readableName : tg.groupName;

      let prefix: string | null = prefixOf(tg.groupName);
      if (prefix === null) {
        prefix = '';
      }

      const chips: TagChip[] = [];
      // 上游 `for (int j = 0, z = tg.size(); j < z; j++)` —— 用 size()/getTagAt()，不是公开数组
      for (let j = 0; j < tg.size(); j++) {
        const tagStr: string = tg.getTagAt(j);
        let readable: string | null = null;
        if (translate !== null) {
          readable = translate(`${prefix}${tagStr}`);
        }
        chips.push(new TagChip(readable !== null ? readable : tagStr, `${tg.groupName}:${tagStr}`));
      }
      out.push(new TagGroupView(tg.groupName, displayName, chips));
    }
    return out;
  }

  /** 标签组区的可见性（上游 1099-1104：空 → 显示 noTags，隐藏 mTags）。 */
  static tagsVisible(tagGroups: GalleryTagGroup[] | null): boolean {
    return tagGroups !== null && tagGroups.length > 0;
  }

  /** 无标签提示的可见性（与 `tagsVisible` **互斥**）。 */
  static noTagsVisible(tagGroups: GalleryTagGroup[] | null): boolean {
    return !GalleryDetailBind.tagsVisible(tagGroups);
  }
}

/** 剥离 `namespace:tag` 中的前缀，仅保留纯标签名供 EHWiki 查询。 */
export function stripTagNamespace(rawTag: string): string {
  const colonIdx: number = rawTag.indexOf(':');
  return colonIdx >= 0 ? rawTag.substring(colonIdx + 1) : rawTag;
}
