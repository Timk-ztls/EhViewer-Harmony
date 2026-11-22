/**
 * 迁移自 app/src/main/java/com/hippo/widget/ContentLayout.java（inventory S0515，上游 929 行）
 *
 * ============================ 裁决落地（Lead 2026-10-24） ============================
 * 渲染层**放弃** FastScroller / EasyRecyclerView（外部库 com.hippo.easyrecyclerview，无 inventory 编号，
 * 移植它会突破"1:1 只覆盖 app 源码树"的边界），改用 ArkUI 原生 `Refresh` + `List`。
 * **状态机必须 1:1**：`ContentHelper` 的 7 态 + 4 个 GOTO_* + 3 个 REFRESH_TYPE_* 全量保留，
 * 因为它是"翻页/刷新/跳页"的唯一真相来源，换渲染层不改变语义。
 *
 * ============================ 未移植项（登记 D-022，由 Lead 落 DEVIATIONS） ============================
 * | 项 | 上游行为 | 影响 |
 * |---|---|---|
 * | `FastScroller` | 长列表右侧可拖拽的快速滚动条 + 索引气泡 | **未移植**。长列表（1000+ 项历史/收藏）只能靠 `List` 自带滚动条或搜索定位 |
 * | `EasyRecyclerView` | 外部库，承载 `setSelection`/`scrollToPositionWithOffset` 等 | **未移植**。用 `List` + `Scroller.scrollToIndex` 替代 |
 * 回退条件（Lead 已批）：P5 验收若判定长列表"没法用"，补一个最小 FastScroller（约 200 行，只做拖拽+气泡）。
 *
 * ============================ 上游 → ArkUI 对位 ============================
 * onGetPageData(taskId, pages, nextPage, data) 的 7 态分发 → 同序搬（本文件 ContentHelper.onGetPageData）
 * TYPE_NEXT_PAGE(_KEEP_POS) 追加、TYPE_PRE_PAGE(_KEEP_POS) 前插、TYPE_SOMEWHERE 整表替换、
 * TYPE_REFRESH_PAGE 只换当前页 → 同序搬
 * isDuplicate(E,E) 抽象 → 抽象方法保留（子类必须实现，语义不变）
 * onAddData/onRemoveData/onClearData 钩子 → 同序搬
 * showContent/showProgressBar()/showProgressBar(boolean)/showText/showEmptyString → 由 ViewTransition 承载
 *   （content / progress / text 三槽交叉淡入，正是上游 mTransition 的用法）
 * doGetData(type, page, refreshType) → 记录 mCurrentTaskType/Page/RefreshType 后调注入的 requestFn
 *   （上游在此发起 EhClient 请求；网络层归 net-parse，故注入）
 * setFitPaddingTop/Bottom、setRefreshLayoutEnable、setEnable → 组件 @Prop/enabled
 * showFastScroll/hideFastScroll → **空实现 + 注释**（FastScroller 未移植）
 *
 * 差异（已登记 MR）：
 *   1) 上游 `getRecyclerView()/getFastScroller()/getRefreshLayout()` 返回具体控件；鸿蒙侧只暴露
 *      `scroller`（ArkUI `Scroller`）供 `scrollToIndex` 使用，不暴露内部 List。
 *   2) `onGetPageData(GalleryListParser.Result, ...)` / `(FavoritesParser.Result, ...)` 两个重载
 *      是 net-parse 的数据模型；本文件只保留通用的 `(taskId, pages, nextPage, data)` 入口，
 *      另两个由调用方在拿到 Result 后转成通用入口（避免 ui-widget → net-parse 的 parser 依赖）。
 *   3) `onSaveInstanceState/onRestoreInstanceState` → saveState()/restoreState()（页面栈、任务类型、空串）。
 */
import { ViewTransition, ViewTransitionController, OnShowViewListenerImpl } from '../view/ViewTransition';

/** 上游 TYPE_* */
export class ContentGetType {
  static readonly REFRESH: number = 0;
  static readonly PRE_PAGE: number = 1;
  static readonly PRE_PAGE_KEEP_POS: number = 2;
  static readonly NEXT_PAGE: number = 3;
  static readonly NEXT_PAGE_KEEP_POS: number = 4;
  static readonly SOMEWHERE: number = 5;
  static readonly REFRESH_PAGE: number = 6;
}

/** 上游 REFRESH_TYPE_* */
export class ContentRefreshType {
  static readonly HEADER: number = 0;
  static readonly FOOTER: number = 1;
  static readonly PROGRESS_VIEW: number = 2;
}

/** 上游 GOTO_* */
export class ContentGoto {
  static readonly FIRST_PAGE: number = 0;
  static readonly PREV_PAGE: number = 1;
  static readonly NEXT_PAGE: number = 2;
  static readonly LAST_PAGE: number = 3;
}

/** 三方槽位下标（对位上游 mTransition 的 content/progress/text 三视图） */
export class ContentSlot {
  static readonly CONTENT: number = 0;
  static readonly PROGRESS: number = 1;
  static readonly TEXT: number = 2;
}

/** 存档（对位上游 Parcelable） */
export class ContentHelperSavedState {
  pages: number = 0;
  page: number = 0;
  currentTaskPage: number = 0;
  currentTaskType: number = ContentGetType.REFRESH;
  emptyString: string = '';
}

/**
 * `ContentHelper`：数据 + 任务状态机（与渲染无关，可独立测试）。
 * 上游是 `abstract static class ContentHelper<E extends Parcelable> implements ViewTransition.OnShowViewListener`；
 * 鸿蒙侧同样继承 `OnShowViewListener` 语义（由 transition 回调驱动槽位切换）。
 */
export abstract class ContentHelper<E> {
  /** 对位上游 mContentLayout / mTransition：由 ContentLayout 组件注入 */
  /** 对位上游 mTransition（注意：不能叫 transition，与 CustomComponent 基类属性冲突） */
  vtController: ViewTransitionController | null = null;

  data: E[] = [];
  pages: number = 0;
  page: number = 0;
  currentTaskId: number = -1;
  /** 任务号发生器（对位上游 IntIdGenerator：单调递增、不复用；完成时 currentTaskId 置 -1 不影响它） */
  private taskSeq: number = 0;
  currentTaskPage: number = 0;
  currentTaskType: number = ContentGetType.REFRESH;
  currentRefreshType: number = ContentRefreshType.HEADER;
  emptyString: string = '';
  /** 最近一次 showText 的文案（对位上游 mText 视图内容） */
  lastText: string = '';
  enabled: boolean = true;

  /** 上游 protected abstract boolean isDuplicate(E d1, E d2) */
  protected abstract isDuplicate(d1: E, d2: E): boolean;

  // ---------- 数据访问 ----------
  getData(): E[] {
    return this.data;
  }

  getDataAt(location: number): E {
    return this.data[location];
  }

  /** 上游 getDataAtEx：越界返回 null（ArkTS 无可空泛型，用 undefined 表达） */
  getDataAtEx(location: number): E | undefined {
    if (location < 0 || location >= this.data.length) {
      return undefined;
    }
    return this.data[location];
  }

  size(): number {
    return this.data.length;
  }

  getPages(): number {
    return this.pages;
  }

  isCurrentTask(taskId: number): boolean {
    return this.currentTaskId === taskId;
  }

  addAt(index: number, value: E): void {
    this.data.splice(index, 0, value);
    this.onAddData(value);
  }

  removeAt(index: number): void {
    const removed: E = this.data[index];
    this.data.splice(index, 1);
    this.onRemoveData(removed);
  }

  // ---------- 钩子（子类按需覆盖）----------
  protected onAddData(value: E): void {
  }

  protected onAddDatas(values: E[]): void {
  }

  protected onRemoveData(value: E): void {
  }

  protected onRemoveDatas(values: E[]): void {
  }

  protected onClearData(): void {
  }

  // ---------- 任务 ----------
  /**
   * 上游 doGetData(type, page, refreshType)：记录任务态后发起请求。
   * @param requestFn 注入的请求发起函数（上游直接调 EhClient；网络层归 net-parse）
   */
  doGetData(type: number, page: number, refreshType: number,
            requestFn: (taskId: number, page: number, type: number) => void): void {
    this.currentTaskType = type;
    this.currentTaskPage = page;
    this.currentRefreshType = refreshType;
    this.taskSeq = this.taskSeq + 1;
    this.currentTaskId = this.taskSeq;
    requestFn(this.currentTaskId, page, type);
  }

  /**
   * 上游 `ContentLayout.java:914 refreshSort(String sort)`：
   * ```
   * showProgressBar();
   * mCurrentTaskId = mIdGenerator.nextId();
   * mCurrentTaskType = TYPE_REFRESH;
   * mCurrentTaskPage = 0;                       // ← 排序变更必须回到第 0 页
   * getPageData(mCurrentTaskId, mCurrentTaskType, mCurrentTaskPage, sort);
   * ```
   * ⇒ **排序是"带 sort 重新请求第 0 页"，不是本地重排**（`favOrder` 由服务端决定）。
   * `sort` 只在本次请求里传递，不写进 ContentHelper 状态（上游也是作为参数透传）。
   */
  refreshSort(sort: string,
              requestFn: (taskId: number, page: number, type: number, sort: string) => void): void {
    this.showProgressBar();
    this.doGetData(ContentGetType.REFRESH, 0, ContentRefreshType.PROGRESS_VIEW,
      (taskId: number, page: number, type: number) => {
        requestFn(taskId, page, type, sort);
      });
  }

  /** 上游 onGetPageData(taskId, pages, nextPage, data)：7 态分发的核心 */
  onGetPageData(taskId: number, pages: number, nextPage: number, newData: E[]): void {
    if (!this.isCurrentTask(taskId)) {
      return;
    }
    this.currentTaskId = -1;
    this.pages = pages;
    this.page = nextPage;

    if (this.currentTaskType !== ContentGetType.NEXT_PAGE_KEEP_POS
      && this.currentTaskType !== ContentGetType.NEXT_PAGE) {
      // 非"下一页"类任务：清空后重建
      if (this.currentTaskType !== ContentGetType.PRE_PAGE_KEEP_POS
        && this.currentTaskType !== ContentGetType.PRE_PAGE) {
        // TYPE_REFRESH / TYPE_SOMEWHERE / TYPE_REFRESH_PAGE：整表替换
        this.data = [];
        this.onClearData();
        this.data = newData.slice();
        this.onAddDatas(newData);
      } else {
        // TYPE_PRE_PAGE(_KEEP_POS)：前插
        const merged: E[] = newData.slice().concat(this.data);
        const added: E[] = newData.slice();
        this.data = merged;
        this.onAddDatas(added);
      }
    } else {
      // TYPE_NEXT_PAGE(_KEEP_POS)：追加（去重靠 isDuplicate）
      const appended: E[] = [];
      for (let i = 0; i < newData.length; i++) {
        const candidate: E = newData[i];
        let dup: boolean = false;
        for (let j = 0; j < this.data.length; j++) {
          if (this.isDuplicate(this.data[j], candidate)) {
            dup = true;
            break;
          }
        }
        if (!dup) {
          appended.push(candidate);
        }
      }
      this.data = this.data.concat(appended);
      this.onAddDatas(appended);
    }
    this.showContent();
  }

  /** 上游 onGetException(taskId, e)：只处理当前任务 */
  onGetException(taskId: number, message: string): void {
    if (!this.isCurrentTask(taskId)) {
      return;
    }
    this.currentTaskId = -1;
    this.showText(message);
  }

  // ---------- 三槽切换（对位上游 ViewTransition）----------
  showContent(): void {
    const vt: ViewTransitionController | null = this.vtController;
    if (vt !== null) {
      vt.showView(ContentSlot.CONTENT);
    }
  }

  showProgressBar(animation: boolean = true): void {
    const vt: ViewTransitionController | null = this.vtController;
    if (vt !== null) {
      vt.showView(ContentSlot.PROGRESS, animation);
    }
  }

  showText(text: string): void {
    this.lastText = text;
    const vt: ViewTransitionController | null = this.vtController;
    if (vt !== null) {
      vt.showView(ContentSlot.TEXT);
    }
  }

  showEmptyString(): void {
    this.showText(this.emptyString);
  }

  // ---------- 存档 ----------
  saveState(): ContentHelperSavedState {
    const s: ContentHelperSavedState = new ContentHelperSavedState();
    s.pages = this.pages;
    s.page = this.page;
    s.currentTaskPage = this.currentTaskPage;
    s.currentTaskType = this.currentTaskType;
    s.emptyString = this.emptyString;
    return s;
  }

  restoreState(s: ContentHelperSavedState): void {
    this.pages = s.pages;
    this.page = s.page;
    this.currentTaskPage = s.currentTaskPage;
    this.currentTaskType = s.currentTaskType;
    this.emptyString = s.emptyString;
  }
}

/**
 * 渲染层：`Refresh`（顶部下拉=HEADER）+ `List`（触底=NEXT_PAGE）+ `ViewTransition`（三槽交叉淡入）。
 * 上游的 `FastScroller` / `EasyRecyclerView` **未移植**（见文件头 D-022）。
 */
@Component
export struct ContentLayout {
  helper: ContentHelper<Object> | null = null;
  vtController: ViewTransitionController = new ViewTransitionController(3);
  scroller: Scroller = new Scroller();
  /** 对位上游 setFitPaddingTop/Bottom（内容不被系统栏遮挡） */
  @Prop fitPaddingTop: number = 0;
  @Prop fitPaddingBottom: number = 0;
  /** 对位 setRefreshLayoutEnable */
  @Prop refreshEnabled: boolean = true;
  @State refreshing: boolean = false;
  /** 槽位内容：CONTENT/PROGRESS/TEXT */
  /** 注意：不能叫 content，与组件基类/属性解析冲突 */
  @BuilderParam slotContent: (slot: number) => void = this.emptySlot;
  /** 下拉刷新回调（对位 TYPE_REFRESH + REFRESH_TYPE_HEADER） */
  onRefresh: () => void = () => {
  };
  /** 触底加载回调（对位 TYPE_NEXT_PAGE + REFRESH_TYPE_FOOTER） */
  onLoadMore: () => void = () => {
  };

  @Builder
  emptySlot(slot: number): void {
  }

  aboutToAppear(): void {
    if (this.helper !== null) {
      this.helper.vtController = this.vtController;
    }
  }

  /** 上游 showFastScroll()：FastScroller 未移植，保留空实现（D-022） */
  showFastScroll(): void {
  }

  /** 上游 hideFastScroll()：同上 */
  hideFastScroll(): void {
  }

  build() {
    ViewTransition({ controller: this.vtController, slot: this.slotBuilder })
      .width('100%')
      .height('100%')
  }

  /** 槽位下标：0=content 1=progress 2=text（与 ContentSlot 常量一致；builder 内用字面量，避免 ets 解析器误判 X.Y 为属性链） */
  @Builder
  slotBuilder(i: number): void {
    Stack() {
      if (i === 0) {
      Refresh({ refreshing: this.refreshing }) {
        List({ scroller: this.scroller }) {
            this.slotContent(0)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          // 触底 = 上游 REFRESH_TYPE_FOOTER
          this.onLoadMore();
        })
      }
      .enabled(this.refreshEnabled)
      .onRefreshing(() => {
        this.refreshing = true;
        this.onRefresh();
      })
      .padding({ top: this.fitPaddingTop, bottom: this.fitPaddingBottom })
      .width('100%')
      .height('100%')
    } else if (i === 1) {
      Column() {
        LoadingProgress()
          .width(48)
          .height(48)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        this.slotContent(2)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
  }
}
