/*
 * 上游：app/src/main/res/layout/activity_main.xml（105 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/activity_main.ets（inventory S0554）
 *
 * ============================================================================
 * 骨架缺口（auditor-ui 量化 28/105，`[SKELETON]`）
 * ============================================================================
 * 原骨架只剩一个 `SafeCoordinatorLayout` 的 `@BuilderParam` 槽位，其下**5 层子树全丢**。
 * 根因：生成器遇到第一个"未识别的自定义控件"就当叶子节点，不再往下走 ——
 * 于是 EhDrawerLayout / EhStageLayout / EhNavigationView / EhDrawerView 这**四个已交付**的
 * 组件一个都没接进来。本文件是**接线活**，不新实现任何容器。
 *
 * ============================================================================
 * 上游 6 层结构（缩进即嵌套）
 * ============================================================================
 *   SafeCoordinatorLayout                          ← L1 安全区协调容器
 *     EhDrawerLayout#draw_view  fitsSystemWindows   ← L2 抽屉容器
 *       EhStageLayout#fragment_container           ← L3 场景栈（内容区）
 *       EhNavigationView                           ← L4 左抽屉壳
 *         FrameLayout                              ← L5-a 导航主体
 *           FrameLayout
 *             NavigationView#nav_view              ← L6 材质导航列表
 *               headerLayout=@layout/nav_header_main / menu=@menu/nav_drawer_main
 *         FrameLayout layout_gravity=bottom|center ← L5-b 底部计数区
 *           LinearLayout(vertical)
 *             LimitsCountView#limits_count_view maxHeight=180dp
 *             TextView#change_theme
 *       EhDrawerView#right_drawer maxWidth=drawer_max_width ← L4' 右抽屉
 *
 * ============================================================================
 * 四处**接线陷阱**（组件已存在，槽位搞错就白接）
 * ============================================================================
 *   1. **EhDrawerLayout 的槽位是 `drawer` + `content` 两个 `@BuilderParam`**，不是"子节点顺序"。
 *      **右抽屉（EhDrawerView）要放进 `content`**，与 `EhStageLayout` 并列 ——
 *      上游 XML 里它俩确实是兄弟（同在 EhDrawerLayout 下）；
 *   2. **EhNavigationView 只有一个 `content` 槽位**，导航列表与底部计数区都塞进这一个 content；
 *   3. `nav_view` 的 `layout_weight=1` 与底部 `FrameLayout` 的 `layout_gravity=bottom|center`
 *      在小屏会**互相挤压**，所以 L5 必须是 `Stack` 而非 `Column` ——
 *      用 Column 会让底部区把导航列表顶走；
 *   4. `NavigationView`（Google 材质组件）**ArkUI 侧没有等价 struct** → 用 `List` + `ListItem`
 *      还原，菜单项由 `navMenu` 注入（上游 `@menu/nav_drawer_main`）。
 */

import { SafeCoordinatorLayout } from '../../widget/SafeCoordinatorLayout';
import { EhDrawerLayout } from '../../ehviewer/widget/EhDrawerLayout';
import { EhStageLayout } from '../../ehviewer/widget/EhStageLayout';
import { EhNavigationView } from '../../ehviewer/widget/EhNavigationView';
import { EhDrawerView } from '../../ehviewer/widget/EhDrawerView';
import { LimitsCountView } from '../../ehviewer/widget/LimitsCountView';
import { NavHeaderMainLayout } from './nav_header_main';

/** 抽屉菜单的一项（上游 `@menu/nav_drawer_main` 的投影）。 */
export class NavMenuItem {
  /** 上游 menu item id（与 `MainActivity.DRAWER_*` 常量对应） */
  id: number = 0;
  /** 显示文案（已本地化） */
  title: string = '';
  /** 图标资源名（可选） */
  iconRes: string = '';

  constructor(id: number, title: string, iconRes: string) {
    this.id = id;
    this.title = title;
    this.iconRes = iconRes;
  }
}

@Component
export struct ActivityMainLayout {
  /** 上游 `@id/nav_view` 的菜单项（`@menu/nav_drawer_main`，9 项） */
  @Prop navMenu: NavMenuItem[] = [];
  /** 左抽屉是否打开（上游 `EhDrawerLayout` 的滑动状态） */
  @Prop drawerOpen: boolean = false;
  /** 右抽屉是否打开（上游 `right_drawer`，D-023 作用域 reset 依赖它） */
  @Prop rightDrawerOpen: boolean = false;
  /** 上游 `@id/change_theme` 的文案 */
  @Prop changeThemeText: string = '';
  /**
   * 抽屉开合变化（手势拖动结束 / 点击遮罩）。
   *
   * **由宿主页（Index/GalleryListHostPage）接管**：上游 `MainActivity.onDrawerOpened/Closed`
   * 会向所有场景广播（D-023 的作用域 reset 依赖它）。组件层只上报，不做广播。
   */
  onDrawerToggle: (open: boolean) => void = (open: boolean): void => {};
  /** 左抽屉头部展示名（`nav_header_main`） */
  @Prop displayName: string = '';
  /** 左抽屉头部背景图 */
  @Prop headerBackgroundSrc: ResourceStr = '';

  /** 场景内容槽位（由 MainActivity 注入） */
  @BuilderParam stageContent: () => void = this.emptySlot;
  /** 右抽屉内容槽位（上游是空 FrameLayout，留给后续接线） */
  @BuilderParam rightDrawerContent: () => void = this.emptySlot;

  /** onOpenChange 的内部转发（ArkTS 不允许直接在参数位写 this.xxx 的多行闭包时再引用 this） */
  onDrawerOpenChange(open: boolean): void {
    this.onDrawerToggle(open);
  }

  @Builder
  emptySlot() {
    Column().width(0).height(0)
  }

  /** L6：NavigationView（材质组件）→ List + ListItem */
  @Builder
  navList() {
    List() {
      ListItem() {
        NavHeaderMainLayout({
          displayName: this.displayName,
          headerBackgroundSrc: this.headerBackgroundSrc
        })
      }
      ForEach(this.navMenu, (item: NavMenuItem) => {
        ListItem() {
          Row() {
            Text(item.title).layoutWeight(1).maxLines(1)
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
        }
        .id(`nav_item_${item.id}`)
      }, (item: NavMenuItem) => `${item.id}`)
    }
    .id('nav_view')
    // 上游 paddingBottom=48dip：给底部手势条留白
    .padding({ bottom: 48 })
    .scrollBar(BarState.Auto)
    .layoutWeight(1)
  }

  /** 左抽屉内容（EhDrawerLayout 的 `drawer` 槽位） */
  @Builder
  leftDrawer() {
    // L4 EhNavigationView（单个 @BuilderParam → 可用尾随闭包）
    EhNavigationView() {
      // L5：Stack（导航列表 + 底部计数区叠放，不用 Column —— 否则底部区把列表顶走）
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          this.navList()
        }
        .width('100%')
        .height('100%')

        // L5-b 底部计数区（layout_gravity=bottom|center）
        Column() {
          LimitsCountView()
            .id('limits_count_view')
            .constraintSize({ maxHeight: 180 })
          Text(this.changeThemeText)
            .id('change_theme')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 内容区（EhDrawerLayout 的 `content` 槽位：EhStageLayout 与右抽屉**并列**） */
  @Builder
  contentArea() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // L3 EhStageLayout（单个 @BuilderParam → 尾随闭包）
      Column() {
        EhStageLayout() {
          this.stageContent()
        }
      }
      .id('fragment_container')
      .width('100%')
      .height('100%')

      // L4' EhDrawerView：右抽屉（单个 @BuilderParam → 尾随闭包）
      Column() {
        EhDrawerView({ maxWidth: 280 }) {
          this.rightDrawerContent()
        }
      }
      .id('right_drawer')
      .visibility(this.rightDrawerOpen ? Visibility.Visible : Visibility.None)
    }
    .id('draw_view')
    .width('100%')
    .height('100%')
  }

  build() {
    // L1 SafeCoordinatorLayout（单个 @BuilderParam → 尾随闭包）
    Column() {
      SafeCoordinatorLayout() {
        // L2 EhDrawerLayout：**两个 @BuilderParam（drawer + content）**
        // ⚠️ ArkTS 规定：带**不止一个** @BuilderParam 的组件**不能**用尾随闭包语法
        //    （报 "must have one and only one property decorated with '@BuilderParam'"），
        //    必须两个都写成**具名参数**。
        EhDrawerLayout({
          open: this.drawerOpen,
          drawer: (): void => { this.leftDrawer(); },
          content: (): void => { this.contentArea(); },
          // ② 手势层回写：EhDrawerLayout 的 @Watch 只在**外部**改 open 时触发；
          // 用户拖拽结束后必须通过 onOpenChange 通知宿主，否则 this.drawerOpen 与真实状态脱节，
          // 下一次受控更新会把抽屉"弹回"到旧状态（22 断言的手势层正是在这里与页面同步）。
          onOpenChange: (open: boolean): void => { this.onDrawerOpenChange(open); }
        })
      }
    }
    .id('safe_coordinator')
    .width('100%')
    .height('100%')
  }
}