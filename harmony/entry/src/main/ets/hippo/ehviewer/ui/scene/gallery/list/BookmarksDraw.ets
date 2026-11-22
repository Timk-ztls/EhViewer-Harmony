/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/BookmarksDraw.java（146 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/BookmarksDraw.ets（S0236）
 *
 * 上游事实：class BookmarksDraw(Context, LayoutInflater, EhTagDatabase)
 *   静态：QUICK_SEARCH_DRAW_SCROLL_Y = "QuickSearchDrawScrollY"
 *         QUICK_SEARCH_DRAW_SCROLL_POS = "QuickSearchDrawScrollPos"
 *   字段：ehApplication / listView / ehTags(EhTagDatabase)
 * = 抽屉里的"快速搜索"面板：按 EhTagDatabase 的命名空间分组渲染标签列表，
 *   并把滚动位置持久化（下两项静态 key）。
 *
 * Part 1（本批）：分组数据构建、滚动位置读写、点击回传。
 * Part 2 待补：ListView → List/LazyForEach 的渲染层（需 @Component，属 scene 体系的接线活）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 上游 EhTagDatabase 的所需子集（net-parse 交付，此处只声明本类用到的） */
export interface TagDatabaseLike {
  /** 所有命名空间（上游 getTagNamespaceArray / 分组头） */
  getNamespaces(): string[];
  /** 某命名空间下的标签（上游 getTags(namespace)） */
  getTags(namespace: string): string[];
}

/** 滚动位置持久化（上游两个静态 key 属于共享偏好，注入以避开 pending 的 Settings） */
export interface DrawScrollStoreLike {
  getInt(key: string): number;
  putInt(key: string, value: number): void;
}

export class InMemoryDrawScrollStore implements DrawScrollStoreLike {
  private map: Map<string, number> = new Map<string, number>();
  getInt(key: string): number {
    const v: number | undefined = this.map.get(key);
    return v === undefined ? 0 : v;
  }
  putInt(key: string, value: number): void {
    this.map.set(key, value);
  }
}

/** 一个命名空间分组（上游 ListView 的分组项） */
export class TagNamespaceGroup {
  readonly namespace: string;
  readonly tags: string[];
  constructor(namespace: string, tags: string[]) {
    this.namespace = namespace;
    this.tags = tags;
  }
}

export class BookmarksDraw {
  static readonly QUICK_SEARCH_DRAW_SCROLL_Y: string = 'QuickSearchDrawScrollY';
  static readonly QUICK_SEARCH_DRAW_SCROLL_POS: string = 'QuickSearchDrawScrollPos';

  private readonly tags: TagDatabaseLike;
  private readonly scrollStore: DrawScrollStoreLike;
  private groups: TagNamespaceGroup[] = [];

  constructor(tags: TagDatabaseLike, scrollStore: DrawScrollStoreLike = new InMemoryDrawScrollStore()) {
    this.tags = tags;
    this.scrollStore = scrollStore;
  }

  /** 上游构建分组：命名空间 → 标签列表；空命名空间跳过（否则会出一个空分组头） */
  buildGroups(): TagNamespaceGroup[] {
    const namespaces: string[] = this.tags.getNamespaces();
    const out: TagNamespaceGroup[] = [];
    for (let i = 0; i < namespaces.length; i++) {
      const ns: string = namespaces[i];
      const list: string[] = this.tags.getTags(ns);
      if (list.length === 0) {
        continue;
      }
      out.push(new TagNamespaceGroup(ns, list));
    }
    this.groups = out;
    return out;
  }

  getGroups(): TagNamespaceGroup[] {
    return this.groups;
  }

  /** 上游保存滚动位置（两个 key 分别存像素偏移与列表位置，不能只存一个） */
  saveScroll(position: number, offsetY: number): void {
    this.scrollStore.putInt(BookmarksDraw.QUICK_SEARCH_DRAW_SCROLL_POS, position);
    this.scrollStore.putInt(BookmarksDraw.QUICK_SEARCH_DRAW_SCROLL_Y, offsetY);
  }

  /** 上游恢复滚动：返回 [position, offsetY]；两者都缺省为 0 */
  restoreScroll(): number[] {
    const pos: number = this.scrollStore.getInt(BookmarksDraw.QUICK_SEARCH_DRAW_SCROLL_POS);
    const y: number = this.scrollStore.getInt(BookmarksDraw.QUICK_SEARCH_DRAW_SCROLL_Y);
    if (pos < 0 || y < 0) {
      hilog.warn(0x0000, 'BookmarksDraw', '恢复的滚动位置异常: pos=%{public}d y=%{public}d；后果：回到顶部',
        pos, y);
      return [0, 0];
    }
    return [pos, y];
  }

  /** 上游点击标签：把该标签交给宿主（快速搜索面板不自己发请求） */
  onTagClicked(tag: string, onApply: (tag: string) => void): void {
    if (tag.length === 0) {
      hilog.info(0x0000, 'BookmarksDraw', '点击空标签；后果：无动作');
      return;
    }
    onApply(tag);
  }
}
