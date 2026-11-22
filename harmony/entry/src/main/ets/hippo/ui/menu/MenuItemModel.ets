/*
 * 菜单定义模型（ui-scene 菜单移植的共用类型）
 *
 * 背景：Android 的 `/res/menu/*.xml` 是**菜单定义**（不是布局）：每个 `<item>` 声明
 * id / 图标 / 标题 / 显示位置，由 `onCreateOptionsMenu` inflate 成原生菜单。
 * ArkUI 没有资源级菜单 inflate，菜单通常由**数据驱动**（`Menu`/`bindMenu`/自定义 popup），
 * 因此这里把每个 menu XML 落成一个「菜单项定义数组」。
 *
 * 字段与上游 XML 属性的对应（**只映射上游实际用到的属性**，逐个统计过）：
 *   android:id                       → id（把 `@+id/action_add` 归一成 `'action_add'`，见 1）
 *   android:title="@string/x"        → title（`$r('app.string.x')`）
 *   android:icon="@drawable/x"       → iconName（**不**生成 `$r('app.media.x')`，见 2）
 *   app:showAsAction                 → showAsAction（always / ifRoom / never，见 3）
 *   android:visible                  → visible
 *   group 的 android:checkableBehavior → checkableBehavior（single / all / none，见 4）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `id` 用**字符串**而不是资源 id：ArkUI 没有 `R.id` 体系，业务侧按名字分发
 *    （对应上游 `menu.findItem(R.id.action_add)` → 这里 `items.find(i => i.id === 'action_add')`）。
 * 2. `icon` **不落 `$r('app.media.x')`**：本仓库把 drawable 迁成了 ArkUI 组件
 *    （`hippo/ui/drawable/x.ets`，如 `VPlusDarkX24`），`app.media.*` 多数不存在。
 *    所以这里存**资源名**（`'v_plus_dark_x24'`），由渲染方查组件表；名字保持与上游一致，
 *    便于 1:1 追溯。
 * 3. `showAsAction`：Android 的 `always`（常显）/ `ifRoom`（有空间才显示）/ `never`（进 overflow）。
 *    ArkUI 的菜单渲染由使用方决定，这里只保留语义标记，不强制渲染策略。
 * 4. `checkableBehavior`（`<group>` 级）：`single` = 单选组（radio）/ `all` = 多选（checkbox）/
 *    `none` = 不可选。成员下每个 item 带 `checkable` 标记。
 * 5. `android:orderInCategory` / `android:menuCategory` / `android:alphabeticShortcut` 等
 *    上游**没有用到**（已对 13 个文件逐个属性统计），故不建模 —— 不预留空字段。
 */

/** `app:showAsAction` 的三种取值（上游实际只用到 always） */
export enum ShowAsAction {
  /** 总是显示在 action bar 上 */
  ALWAYS = 'always',
  /** 有空间才显示，否则进 overflow */
  IF_ROOM = 'ifRoom',
  /** 从不显示在 action bar（只进 overflow） */
  NEVER = 'never'
}

/** `<group android:checkableBehavior>` 的三种取值 */
export enum CheckableBehavior {
  /** 不可选 */
  NONE = 'none',
  /** 单选（radio） */
  SINGLE = 'single',
  /** 多选（checkbox） */
  ALL = 'all'
}

/**
 * 一个菜单项。构造用 `menuItem()` 工厂（ArkTS 不允许对象字面量做结构化赋值到 interface ——
 * `arkts-no-structural-typing`，所以这里显式用 class + 默认值，避免每个菜单文件都写全字段）。
 */
export class MenuItemDef {
  /** 上游 `@+id/xxx` 的名字部分（如 `'action_add'`） */
  id: string;
  /** 上游 `android:title`（`$r('app.string.x')`；上游未设 title 时为空串） */
  title: ResourceStr;
  /** 上游 `android:icon="@drawable/x"` 的**资源名**（不是 Resource，见文件头 2）；无图标为 null */
  iconName: string | null;
  /** 上游 `app:showAsAction`；未设时按 Android 默认 `never` */
  showAsAction: ShowAsAction;
  /** 上游 `android:visible`（默认 true） */
  visible: boolean;
  /** 所属 group 的 `android:checkableBehavior`（无 group 时 `none`） */
  checkableBehavior: CheckableBehavior;
  /** 是否可勾选（由 group 的 checkableBehavior 推出：single/all → true） */
  checkable: boolean;

  constructor(id: string, title: ResourceStr, iconName: string | null,
              showAsAction: ShowAsAction, visible: boolean,
              checkableBehavior: CheckableBehavior) {
    this.id = id;
    this.title = title;
    this.iconName = iconName;
    this.showAsAction = showAsAction;
    this.visible = visible;
    this.checkableBehavior = checkableBehavior;
    this.checkable = checkableBehavior !== CheckableBehavior.NONE;
  }
}
