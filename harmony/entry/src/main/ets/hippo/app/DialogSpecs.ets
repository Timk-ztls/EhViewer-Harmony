/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0002 / S0003 / S0004（三个 DialogBuilder 合批）
 * 目标   : harmony/entry/src/main/ets/hippo/app/DialogSpecs.ets
 *
 * 【**声明式重写**：不弹窗、不持有 dialog 句柄，产出 Spec 描述对象】
 * 上游三个类都是 `AlertDialog.Builder` 的子类，构造即 inflate 布局、`create()` 才出 dialog、
 * 之后靠 `isChecked` / `text` 读用户输入。ArkUI 是声明式的：
 * `AlertDialog.show({...})` + `@State` 状态——
 * 因此本文件只保留**三条真正可移植的语义**：
 *
 *   1. **初始状态与默认值**（`checked` / `checked` 缺省、`List` 的 items 必须非空）
 *   2. **用户输入的读取契约**（`isChecked` / `text` → Spec 上的可变字段）
 *   3. **`EditText` 的 IME 行为**：`onEditorAction` 时**如果 event 非空且 dialog 已创建**，
 *      就**触发确定按钮**并返回 true；否则返回 false（交给框架默认处理）
 *      —— 这是"软键盘回车 = 点确定"的关键，也是上游唯一有分支的逻辑
 *
 * 不移植（Android UI，全归 ui-widget）：
 *   `AlertDialog.Builder` / `LayoutInflater` / `findViewById` / `CheckBox` / `ListView` /
 *   `ArrayAdapter` / `TextInputLayout` / `EditText.setSelection` / `dismiss()` / `getButton()`
 *
 * 平台差异：
 *  1. `AlertDialog.Builder` → `DialogSpec` 数据对象；调用方用 `AlertDialog.show({...})` 渲染。
 *  2. `EditText.setSelection(editText.text.length)` → **光标置尾**（`selectionEnd`），
 *     否则用户编辑"已有文本"时会在开头插入 —— 这是可感知的体验差异。
 *  3. `create()` 里记录 `mDialog` → `ready: boolean`（Spec 是否已挂到可见对话框）；
 *     `onEditorAction` 的 `event != null && mDialog != null` 两个前置条件**逐字保留**。
 *  4. `ListCheckBoxDialogBuilder.onItemClick` 里**先回调 listener 再 dismiss**（顺序照搬：
 *     listener 里若读 `isChecked`，读到的是**点击瞬间**的值，不是 dismiss 后的）。
 */

/** 三个 Builder 共用的对话框描述 */
export class DialogSpec {
  /** 标题（上游都由调用方在 builder 上 `setTitle`，这里统一承载） */
  title: string | null = null;
  /** 主消息（`CheckBoxDialogBuilder` 的 message） */
  message: string | null = null;
  /** 确认/取消按钮文案；null 表示用系统默认 */
  positiveText: string | null = null;
  negativeText: string | null = null;
}

/** S0002 `CheckBoxDialogBuilder`：消息 + 一个复选框 */
export class CheckBoxDialogSpec extends DialogSpec {
  /** 复选框文案 */
  checkText: string | null;
  /** 复选框当前状态（**可变**：对应上游 `mCheckBox.isChecked`） */
  checked: boolean;

  constructor(message: string | null, checkText: string | null, checked: boolean) {
    super();
    this.message = message;
    this.checkText = checkText;
    this.checked = checked;
  }

  /** 对应上游 `val isChecked: Boolean get() = mCheckBox.isChecked` */
  isChecked(): boolean {
    return this.checked;
  }
}

/** S0003 `EditTextDialogBuilder`：一个带 hint 的输入框 */
export class EditTextDialogSpec extends DialogSpec {
  /** 输入框当前文本（**可变**：对应上游 `editText.setText/text`） */
  text: string;
  /** `TextInputLayout.hint` */
  hint: string | null;
  /** `TextInputLayout.error`（`setError` 写入；null = 无错误） */
  error: string | null = null;
  /** 对应上游 `mDialog != null`（`create()` 之后为 true） */
  ready: boolean = false;

  constructor(text: string | null, hint: string | null) {
    super();
    this.text = (text === null) ? '' : text;
    this.hint = hint;
  }

  /** 对应上游 `val text: String get() = editText.text.toString()` */
  getText(): string {
    return this.text;
  }

  /** 对应上游 `setError(error: CharSequence?)` —— null 表示清除错误 */
  setError(error: string | null): void {
    this.error = error;
  }

  /** 对应上游 `create()`：记录 dialog 已存在 */
  markReady(): void {
    this.ready = true;
  }

  /**
   * 对应上游 `val selectionEnd`：**新文本的光标应在末尾**。
   * 上游 `editText.setSelection(editText.text.length)` 就是这个语义；
   * 不设置会让用户编辑已有文本时从**开头**插入（可感知的体验差异）。
   */
  getSelectionEnd(): number {
    return this.text.length;
  }

  /**
   * 对应上游 `onEditorAction(v, actionId, event)`：
   * ```
   * if (event != null && mDialog != null) { 点确定; return true } else return false
   * ```
   * @param hasEvent 对应 `event != null`（上游判的是"是否来自硬键盘/IME 的真实事件"）
   * @returns true = **已消费该事件**（调用方不要再用默认行为）
   */
  onEditorAction(hasEvent: boolean): boolean {
    if (hasEvent && this.ready) {
      return true; // 等价"performClick(BUTTON_POSITIVE)"——由调用方据返回值触发确认
    }
    return false;
  }
}

/** S0004 `ListCheckBoxDialogBuilder` 的列表项点击回调 */
export interface OnItemClickListener {
  onItemClick(position: number): void;
}

/** S0004 `ListCheckBoxDialogBuilder`：一个列表 + 一个复选框 */
export class ListCheckBoxDialogSpec extends DialogSpec {
  /** 列表项（上游 `Array<CharSequence>`；**必须非空**，上游写的是 `items!!`） */
  items: string[];
  /** 复选框文案 */
  checkText: string | null;
  /** 复选框当前状态（**可变**） */
  checked: boolean;
  /** 对应上游 `mDialog != null` */
  ready: boolean = false;

  constructor(items: string[] | null, checkText: string | null, checked: boolean) {
    super();
    // 上游 `items!!`（非空断言）→ 传 null 会 NPE；这里抛错，语义一致且更早暴露
    if (items === null) {
      throw new Error('items must not be null');
    }
    this.items = items;
    this.checkText = checkText;
    this.checked = checked;
  }

  /** 对应上游 `val isChecked: Boolean get() = mCheckBox.isChecked` */
  isChecked(): boolean {
    return this.checked;
  }

  /** 对应上游 `create()` */
  markReady(): void {
    this.ready = true;
  }

  /**
   * 对应上游 `onItemClickListener` 的回调体：
   * **先 `listener?.onItemClick(...)`（位置传入），再 `dismiss()`** —— 顺序照搬。
   * @returns 是否已消费（对应"点了某一项"这件事已发生）
   */
  onItemClick(position: number, listener: OnItemClickListener | null): boolean {
    if (position < 0 || position >= this.items.length) {
      return false; // 越界 = 没有点击语义（上游 ListView 不会给越界 position）
    }
    if (listener !== null) {
      listener.onItemClick(position);
    }
    // 上游此处 `mDialog!!.dismiss()` —— 未 ready 时上游会 NPE，这里**不抛**：
    // 用户输入不该因为"对话框还没挂上"而崩溃（B 类修复，已在文件头差异 4 说明顺序）
    this.ready = false;
    return true;
  }
}
