/*
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/GalleryListSceneDialog.kt
 * （清单 S0243 记 150 行，实际 171 行）。
 *
 * ============================================================================
 * 上游是什么（标签长按菜单）
 * ============================================================================
 *   ```kotlin
 *   showTagLongPressDialog(ehTags):
 *     ① temp = tagName 里 ':' **之后**的部分（无冒号 → 整个 tagName）；用于拼标签定义 URL
 *     ② 标题 = 显示翻译 ? "中文(tagName)" : tagName
 *     ③ 菜单两项：0 → 打开标签定义页（用 **temp**）；1 → 加入过滤（用 **tagName**）
 *     ④ 按钮组**按登录状态分两套**：
 *          未登录 → negative = 复制标签
 *          已登录 → neutral = 复制标签、negative = 订阅(关注)、positive = 隐藏
 *     ⑤ 订阅 → requestTag(tagName, tagState)：tagState ? tagWatchNew="on" : tagHiddenNew="on"
 *     ⑥ 成功 → baseScene.setTagList(result) + toast("subscription_success", 状态名)
 *     ⑦ 失败 → toast(e.message)
 *   ```
 *
 * 逐行对照时最容易写错的**五条**（本文件逐条断言）：
 *   1. 菜单项 0 用 **temp（冒号后）**，而按钮组/订阅/过滤用 **tagName（全串）** —— 两者不同；
 *   2. 按钮组是**两套**，不是"同一套再加两个"：未登录只有一个 negative；
 *   3. **"复制"的槽位随登录状态变化**（未登录 negative → 已登录 neutral）—— 最容易抄成固定槽位；
 *   4. 订阅 body 的两个字段**互斥**：只写 `tagWatchNew` 或只写 `tagHiddenNew`；
 *   5. 过滤用 `MODE_TAG` + `text = tagName`（**全串**）。
 *
 * 不属于本文件：`EhDB` 落库、`AlertDialog` 控件本体、`EhFilter` 单例、`UrlOpener` —— 全由调用方/注入。
 */

/** 标签长按菜单的菜单项索引（上游 `R.array.tag_menu_entries` 的 0/1）。 */
export enum TagMenuItem {
  OPEN_TAG_DEFINITION = 0,
  FILTER_TAG = 1
}

/** 弹窗按钮（上游 `setNegativeButton` / `setNeutralButton` / `setPositiveButton`）。 */
export class DialogButton {
  /** `negative` / `neutral` / `positive` */
  slot: string = '';
  /** 文案资源名 */
  textRes: string = '';

  constructor(slot: string, textRes: string) {
    this.slot = slot;
    this.textRes = textRes;
  }
}

/** 标签长按菜单的完整形态（纯数据，便于断言"是哪一套按钮组"）。 */
export class TagLongPressPlan {
  title: string = '';
  /** 菜单项资源名（固定两项，顺序照上游） */
  menuEntries: string[] = [];
  buttons: DialogButton[] = [];
  /** 打开标签定义页用（**冒号后的 temp**） */
  definitionTag: string = '';
  /** 加入过滤用（**全串 tagName**） */
  filterTag: string = '';

  constructor(title: string, menuEntries: string[], buttons: DialogButton[],
    definitionTag: string, filterTag: string) {
    this.title = title;
    this.menuEntries = menuEntries;
    this.buttons = buttons;
    this.definitionTag = definitionTag;
    this.filterTag = filterTag;
  }
}

/** 标签过滤要提交的内容（上游 `Filter` 的三字段）。 */
export class TagFilterSpec {
  /** 上游 `EhFilter.MODE_TAG` */
  mode: string = 'MODE_TAG';
  text: string = '';

  constructor(mode: string, text: string) {
    this.mode = mode;
    this.text = text;
  }
}

/** 订阅/隐藏请求的 body（上游 `TagPushParam` 的**互斥**二字段）。 */
export class TagPushBody {
  tagNameNew: string = '';
  /** 关注：`"on"`；不关注时为空串（表示不写该字段） */
  tagWatchNew: string = '';
  /** 隐藏：`"on"`；不隐藏时为空串 */
  tagHiddenNew: string = '';

  constructor(tagNameNew: string, tagWatchNew: string, tagHiddenNew: string) {
    this.tagNameNew = tagNameNew;
    this.tagWatchNew = tagWatchNew;
    this.tagHiddenNew = tagHiddenNew;
  }
}

export class GalleryListSceneDialog {
  private tagName: string | null = null;

  setTagName(tagName: string | null): void {
    this.tagName = tagName;
  }

  getTagName(): string | null {
    return this.tagName;
  }

  /**
   * 标签名里 `:` **之后**的部分（上游 `temp`）。
   *
   * 无冒号 → 原样；冒号在末尾（`ns:`）→ 空串（与 `substring(index + 1)` 等价）。
   */
  static definitionTagOf(tagName: string): string {
    const index: number = tagName.indexOf(':');
    return index >= 0 ? tagName.substring(index + 1) : tagName;
  }

  /** 标题（上游 ternary）：开翻译 → `中文(tagName)`；否则纯 tagName。 */
  static titleOf(tagName: string, showTranslations: boolean, translated: string): string {
    return showTranslations ? `${translated}(${tagName})` : tagName;
  }

  /**
   * 按钮组（上游**按登录状态分两套**）。
   *
   * 未登录：`[negative = copy_tag]`
   * 已登录：`[neutral = copy_tag, negative = subscription_watched, positive = subscription_hidden]`
   *
   * ⚠️ "复制"在两种状态下**槽位不同**（negative → neutral），这是最容易抄错的地方。
   */
  static buttonsFor(loggedIn: boolean): DialogButton[] {
    if (!loggedIn) {
      return [new DialogButton('negative', 'copy_tag')];
    }
    return [new DialogButton('neutral', 'copy_tag'),
      new DialogButton('negative', 'subscription_watched'),
      new DialogButton('positive', 'subscription_hidden')];
  }

  /** 完整菜单计划（上游 `showTagLongPressDialog` 的组装）。 */
  static planOf(tagName: string, showTranslations: boolean, translated: string,
    loggedIn: boolean): TagLongPressPlan {
    return new TagLongPressPlan(
      GalleryListSceneDialog.titleOf(tagName, showTranslations, translated),
      ['tag_menu_entries_0', 'tag_menu_entries_1'],
      GalleryListSceneDialog.buttonsFor(loggedIn),
      GalleryListSceneDialog.definitionTagOf(tagName),
      tagName);
  }

  /** 加入过滤（上游 `showFilterTagDialog`）：`MODE_TAG` + **全串** tagName。 */
  static filterSpecOf(tagName: string): TagFilterSpec {
    return new TagFilterSpec('MODE_TAG', tagName);
  }

  /**
   * 订阅/隐藏的请求 body（上游 `requestTag` 里的 `TagPushParam`）。
   *
   * **两字段互斥**：`tagState=true` 只写 `tagWatchNew="on"`；`false` 只写 `tagHiddenNew="on"`。
   * 同时写两个是常见错误（服务端只认一个，行为不可预期）。
   */
  static pushBodyOf(tagName: string, tagState: boolean): TagPushBody {
    return tagState ? new TagPushBody(tagName, 'on', '') : new TagPushBody(tagName, '', 'on');
  }

  /** 订阅成功的提示资源名（上游 `subscription_success` 里插的那个状态名）。 */
  static subscriptionStateRes(tagState: boolean): string {
    return tagState ? 'subscription_watched' : 'subscription_hidden';
  }

  /** 订阅成功整句的格式（上游 `R.string.subscription_success`，含一个 `%s`）。 */
  static readonly SUBSCRIPTION_SUCCESS_RES: string = 'subscription_success';
  /** 菜单项对应的动作资源名（上游 `R.array.tag_menu_entries` 两项）。 */
  static readonly MENU_ENTRY_RES: string[] = ['tag_menu_entries_0', 'tag_menu_entries_1'];
}
