/*
 * 接线层：把已完成的三块真正接起来（审计 B 的「140 个布局 struct 零调用方」）
 *   SceneGalleryListLayout（布局）+ GalleryListItemLayout（列表项）+ ArrayDataSource（数据）
 * 上游：scene_gallery_list.xml + item_gallery_list.xml + GalleryAdapter.onBindViewHolder 的组合
 *
 * 用途：作为 pages/Index.ets 的入口页（页面文件属 Lead 作用域，落地只需在 Index 里
 *       import 本组件并 `GalleryListHostPage({ items })`）。
 *
 * 两条已修的缺陷（都是"注释写了契约、代码没有"型）：
 *   ① 空态：`items=[]` 时旧实现只渲染 0 个 ListItem + 4 个空槽位 → 空容器不产生像素（黑屏）。
 *      现在组件**自己兜空态**（列表级职责），任何宿主都不必再记得写；
 *      与页面级空态（Index）并存不冲突。
 *   ② 数据源：旧实现在 build() 里 `new ArrayDataSource(...)` → 每次重建换实例，
 *      旧监听器不注销（泄漏）+ @Prop 深拷贝导致"新实例旧内容" → 列表假死（刷新后内容不变）。
 *      现在数据源是字段单例，数据变化走 onDataReloaded()。
 */
import { GalleryInfo } from '../ehviewer/client/data/GalleryInfo';
import { EhUtils } from '../ehviewer/client/EhUtils';
import { EhCacheKeyFactory } from '../ehviewer/client/EhCacheKeyFactory';
import { GalleryListClient } from './GalleryListClient';
import { GalleryListItemLayout } from './layout/item_gallery_list';
import { SceneGalleryListLayout } from './layout/scene_gallery_list';

@Component
export struct GalleryListHostPage {
  /** 数据（由 @Entry 页面或场景注入；空数组 = 空态） */
  @Prop @Watch('onDataChanged') items: GalleryInfo[] = [];
  /** 点击列表项：转场到详情（由宿主接 StageActivity.startScene） */
  onItemClick: (index: number) => void = (index: number): void => {};
  /** 滚动到底：加载下一页（接 GalleryListScene.onReachEnd） */
  onReachEnd: () => void = (): void => {};
  /** 空态文案（空串则用资源键 empty_result） */
  @Prop emptyText: string = '';

  /**
   * LazyForEach 的数据源必须长期存活：每次 build 都 new 会让框架拿到一批新对象，
   * 旧监听器挂在旧实例上 → 列表空白/不刷新。这里持有单例，数据变化走 onDataReloaded()。
   */
  private dataSource: GalleryArrayDataSource = new GalleryArrayDataSource([]);

  aboutToAppear(): void {
    // 首帧就要有数据（@Prop 的初值不会触发 @Watch）
    this.dataSource.setAll(this.items);
  }

  private onDataChanged(): void {
    this.dataSource.setAll(this.items);
  }

  @Builder
  listContent() {
    List({ space: 2 }) {
      LazyForEach(this.dataSource, (item: GalleryInfo, index: number) => {
        ListItem() {
          GalleryListItemLayout({
            title: EhUtils.getSuitableTitle(item) ?? item.title,
            uploader: item.uploader,
            category: GalleryListClient.formatCategoryLabel(item.category),
            categoryBgColor: GalleryListClient.formatCategoryColor(item.category),
            posted: item.posted,
            pages: item.pages > 0 ? (item.pages.toString() + 'P') : '',
            simpleLanguage: item.simpleLanguage ?? '',
            rating: item.rating,
            thumbUrl: item.thumb,
            thumbKey: EhCacheKeyFactory.getThumbKey(item.gid),
            downloaded: false,
            favourited: item.favoriteSlot >= -1 && item.favoriteSlot <= 10
          })
        }
        .onClick(() => { this.onItemClick(index); })
      }, (item: GalleryInfo) => String(item.gid))
    }
    .width('100%')
    .height('100%')
    .onReachEnd(() => { this.onReachEnd(); })
  }

  /** 空态：组件自己兜（列表级职责），不依赖宿主记得写 */
  @Builder
  emptyContent() {
    Column({ space: 12 }) {
      Text(this.emptyText.length > 0 ? this.emptyText : $r('app.string.empty_result'))
        .fontSize(15)
        .fontColor($r('app.color.colorPrimaryDark'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    SceneGalleryListLayout({
      contentBuilder: () => {
        // 空态与列表二选一：空数组时若只给 List，容器高 0 → 黑屏
        if (this.items.length === 0) {
          this.emptyContent();
        } else {
          this.listContent();
        }
      }
    })
  }
}

/** LazyForEach 需要的轻量数据源（整段替换语义 + GID 去重） */
export class GalleryArrayDataSource implements IDataSource {
  private items: GalleryInfo[] = [];
  private listeners: DataChangeListener[] = [];
  private reloadVersion: number = 0;

  constructor(items: GalleryInfo[]) {
    this.items = GalleryArrayDataSource.dedupByGid(items);
  }

  private static dedupByGid(items: GalleryInfo[]): GalleryInfo[] {
    if (items.length <= 1) {
      return items;
    }
    const seen: Set<number> = new Set<number>();
    let hasDup: boolean = false;
    for (let i = 0; i < items.length; i++) {
      const gid: number = Number(items[i].gid);
      if (gid > 0) {
        if (seen.has(gid)) {
          hasDup = true;
          break;
        }
        seen.add(gid);
      }
    }
    if (!hasDup) {
      return items;
    }
    seen.clear();
    const out: GalleryInfo[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: GalleryInfo = items[i];
      const gid: number = Number(item.gid);
      if (gid > 0) {
        if (seen.has(gid)) {
          continue;
        }
        seen.add(gid);
      }
      out.push(item);
    }
    return out;
  }

  /** 整段替换 + 通知重载（LazyForEach 只认真实通知，改数组不会自动重绘） */
  setAll(items: GalleryInfo[]): void {
    this.items = GalleryArrayDataSource.dedupByGid(items);
    this.notifyDataReload();
  }

  /** 增量同步数据：仅在长度/GID 序列变化时发送增量或重载通知，避免无谓整表重绘卡顿 */
  syncItems(next: GalleryInfo[]): void {
    const deduped: GalleryInfo[] = GalleryArrayDataSource.dedupByGid(next);
    const oldLen: number = this.items.length;
    const nextLen: number = deduped.length;
    if (nextLen === oldLen) {
      let sameOrder: boolean = true;
      for (let i = 0; i < oldLen; i++) {
        if (Number(this.items[i].gid) !== Number(deduped[i].gid)) {
          sameOrder = false;
          break;
        }
      }
      if (sameOrder) {
        this.items = deduped;
        return;
      }
    }
    if (nextLen > oldLen && oldLen > 0) {
      let samePrefix: boolean = true;
      for (let i = 0; i < oldLen; i++) {
        if (Number(this.items[i].gid) !== Number(deduped[i].gid)) {
          samePrefix = false;
          break;
        }
      }
      if (samePrefix) {
        this.items = deduped;
        for (let i = oldLen; i < nextLen; i++) {
          for (let j = 0; j < this.listeners.length; j++) {
            this.listeners[j].onDataAdd(i);
          }
        }
        return;
      }
    }
    this.items = deduped;
    this.notifyDataReload();
  }

  /** 仅通知重载（用于主题切换等不改数组内容的重绘场景） */
  notifyDataReload(): void {
    this.reloadVersion = this.reloadVersion + 1;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  getItemKey(item: GalleryInfo, idx: number, themeId: number): string {
    const gid: number = Number(item.gid);
    return `${idx}_${Number.isFinite(gid) ? gid : 0}_${themeId}_${this.reloadVersion}`;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): GalleryInfo {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i: number = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }
}
