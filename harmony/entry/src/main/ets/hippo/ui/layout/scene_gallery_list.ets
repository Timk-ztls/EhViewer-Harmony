/*
 * 上游：app/src/main/res/layout/scene_gallery_list.xml（inventory S0654）
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * FrameLayout#main_layout (match/match) → Stack(TopCenter) + windowBackground
 * 1) ContentLayout#content_layout       → @BuilderParam contentBuilder
 * 2) SearchLayout#search_layout         → @BuilderParam searchLayoutBuilder
 * 3) SearchBar#search_bar               → @BuilderParam searchBarBuilder（margin 6/8vp，支持 translationY）
 * 4) FabLayout#fab_layout               → @BuilderParam fabBuilder（padding right/bottom 16vp，透明穿透）
 * 5) FabLayout#search_fab               → @BuilderParam searchFabBuilder（padding right/bottom 16vp，透明穿透）
 */

import { ThemeTokens } from '../../../common/theme/ThemeTokens';

export class SearchBarOffsetHolder {
  private _translationY: number = 0;
  private listener: ((y: number) => void) | null = null;

  get translationY(): number {
    return this._translationY;
  }

  set translationY(value: number) {
    if (this._translationY === value) {
      return;
    }
    this._translationY = value;
    if (this.listener !== null) {
      this.listener(value);
    }
  }

  subscribe(listener: ((y: number) => void) | null): void {
    this.listener = listener;
    if (listener !== null) {
      listener(this._translationY);
    }
  }
}

@Component
struct FloatingSearchBarWrapper {
  offsetHolder: SearchBarOffsetHolder = new SearchBarOffsetHolder();
  @Prop forceZero: boolean = false;
  @Prop visible: boolean = true;
  @BuilderParam content: () => void = this.emptyContent;
  @State private translationY: number = 0;

  @Builder
  emptyContent() {
    Column().width(0).height(0)
  }

  aboutToAppear(): void {
    this.translationY = this.offsetHolder.translationY;
    this.offsetHolder.subscribe((y: number): void => {
      this.translationY = y;
    });
  }

  aboutToDisappear(): void {
    this.offsetHolder.subscribe(null);
  }

  build() {
    Row() {
      this.content();
    }
    .width('100%')
    .padding({
      left: $r('app.float.gallery_search_bar_margin_h'),
      right: $r('app.float.gallery_search_bar_margin_h'),
      top: $r('app.float.gallery_search_bar_margin_v')
    })
    .translate({ y: this.forceZero ? 0 : this.translationY })
    .visibility(this.visible ? Visibility.Visible : Visibility.None)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@Component
export struct SceneGalleryListLayout {
  @Prop contentVisible: boolean = true;
  @Prop searchLayoutVisible: boolean = false;
  @Prop searchBarVisible: boolean = true;
  @Prop searchBarTranslationY: number = 0;
  @Prop forceSearchBarZero: boolean = false;
  searchBarOffset: SearchBarOffsetHolder | null = null;
  @Prop windowBackground: ResourceColor = ThemeTokens.current().windowBackground;

  @BuilderParam contentBuilder: () => void = this.emptySlot;
  @BuilderParam searchLayoutBuilder: () => void = this.emptySlot;
  @BuilderParam searchBarBuilder: () => void = this.emptySlot;
  @BuilderParam fabBuilder: () => void = this.emptySlot;
  @BuilderParam searchFabBuilder: () => void = this.emptySlot;

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 1) 内容层（ContentLayout，铺满）
      Column() {
        this.contentBuilder();
      }
      .width('100%')
      .height('100%')
      .visibility(this.contentVisible ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(this.contentVisible ? HitTestMode.Default : HitTestMode.None)

      // 2) 搜索浮层（SearchLayout，铺满，展开时显示）
      Column() {
        this.searchLayoutBuilder();
      }
      .width('100%')
      .height('100%')
      .visibility(this.searchLayoutVisible ? Visibility.Visible : Visibility.None)

      // 3) 顶部悬浮搜索栏（margin 6/8vp / tablet 76/8vp，随列表滚动平移；优先走独立 OffsetHolder 避免整页重绘）
      if (this.searchBarOffset !== null) {
        FloatingSearchBarWrapper({
          offsetHolder: this.searchBarOffset,
          forceZero: this.forceSearchBarZero,
          visible: this.searchBarVisible,
          content: (): void => {
            this.searchBarBuilder();
          }
        })
      } else {
        Row() {
          this.searchBarBuilder();
        }
        .width('100%')
        .padding({
          left: $r('app.float.gallery_search_bar_margin_h'),
          right: $r('app.float.gallery_search_bar_margin_h'),
          top: $r('app.float.gallery_search_bar_margin_v')
        })
        .translate({ y: this.searchBarTranslationY })
        .visibility(this.searchBarVisible ? Visibility.Visible : Visibility.None)
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 4) 主 FAB 组（右下角 padding 16vp，未展开区域不阻挡列表手势）
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.fabBuilder();
      }
      .width('100%')
      .height('100%')
      .padding({
        right: $r('app.float.corner_fab_margin'),
        bottom: $r('app.float.corner_fab_margin')
      })
      .hitTestBehavior(HitTestMode.Transparent)

      // 5) 搜索态 FAB（右下角 padding 16vp，透明穿透）
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.searchFabBuilder();
      }
      .width('100%')
      .height('100%')
      .padding({
        right: $r('app.float.corner_fab_margin'),
        bottom: $r('app.float.corner_fab_margin')
      })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.windowBackground)
  }
}
