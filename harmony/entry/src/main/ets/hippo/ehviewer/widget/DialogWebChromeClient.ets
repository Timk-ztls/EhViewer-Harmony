/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/DialogWebChromeClient.java（S0287，上游 67 行）
 *
 * 判据：**行为类，不是 UI 组件**（`extends WebChromeClient`）。它把 JS 的三个原生对话框
 * 映射成 App 的 AlertDialog，并**把结果回填给 JsResult**：
 *   onJsAlert  ：只显示消息 + 确定 → `result.confirm()`；**取消（点外部/返回）→ `result.cancel()`**
 *   onJsConfirm：确定 → confirm()；取消按钮/取消 → cancel()
 *   onJsPrompt ：显示 message + 预填 defaultValue 的输入框；确定 → `result.confirm(valueView.getText())`
 *  三者都 `return true`（表示"由我处理，WebView 不要再弹默认框"）
 *
 * ArkUI 对位：`Web` 组件提供 `onAlert` / `onConfirm` 回调（返回 boolean + 由调用方 setResult），
 *   所以本类做成**纯逻辑描述器**：把 (kind, message, defaultValue) 变成"对话框请求"，
 *   并把用户动作翻译成 `confirm/cancel` 的结论 —— 可单测，UI 由调用方渲染。
 *
 * 关键语义（断言锁死）：
 *   ① 三个 handler 都返回 true（否则 WebView 会弹自己的默认框，出现双框）
 *   ② **取消路径必须 cancel()**，不能什么都不做（否则 JS 的 `await prompt()` 永远挂起）
 *   ③ prompt 的 confirm 必须带输入值（可为空串，但**不能是 null**）
 */
export class JsDialogKind {
  static readonly ALERT: number = 0;
  static readonly CONFIRM: number = 1;
  static readonly PROMPT: number = 2;
}

/** 对位 JsResult / JsPromptResult 的结论 */
export class JsDialogOutcome {
  /** 是否已处理（对位 handler 的 `return true`） */
  handled: boolean = false;
  /** 用户是否确认 */
  confirmed: boolean = false;
  /** prompt 的输入值（仅 PROMPT 有意义；cancel 时为 null） */
  value: string | null = null;
}

export class DialogWebChromeClient {
  /**
   * 对位 onJsAlert：只有确定按钮；**取消（点外部/返回）→ cancel**。
   * 返回 handled=true（对位 `return true`）。
   */
  static onJsAlert(): JsDialogOutcome {
    const o: JsDialogOutcome = new JsDialogOutcome();
    o.handled = true;
    o.confirmed = false;
    return o;
  }

  /** 对位 onJsConfirm */
  static onJsConfirm(): JsDialogOutcome {
    const o: JsDialogOutcome = new JsDialogOutcome();
    o.handled = true;
    o.confirmed = false;
    return o;
  }

  /** 对位 onJsPrompt */
  static onJsPrompt(defaultValue: string): JsDialogOutcome {
    const o: JsDialogOutcome = new JsDialogOutcome();
    o.handled = true;
    o.confirmed = false;
    o.value = defaultValue;
    return o;
  }

  /** 用户点了确定：ALERT/CONFIRM 无值，PROMPT 带输入值（允许空串，不允许 null） */
  static onConfirmClicked(kind: number, inputValue: string): JsDialogOutcome {
    const o: JsDialogOutcome = new JsDialogOutcome();
    o.handled = true;
    o.confirmed = true;
    o.value = kind === JsDialogKind.PROMPT ? inputValue : null;
    return o;
  }

  /** 用户取消 / 点外部 / 返回键：**必须 cancel（confirmed=false）**，否则 JS 永远挂起 */
  static onCancelClicked(kind: number): JsDialogOutcome {
    const o: JsDialogOutcome = new JsDialogOutcome();
    o.handled = true;
    o.confirmed = false;
    o.value = null;
    return o;
  }
}