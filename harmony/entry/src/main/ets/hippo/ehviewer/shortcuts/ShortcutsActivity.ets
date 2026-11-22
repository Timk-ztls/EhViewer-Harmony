/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/shortcuts/ShortcutsActivity.java（38 行）。
 *
 * 上游：一个不显示界面的 Activity（launcher 长按快捷方式 / 桌面快捷方式的目标），
 * `onCreate` 里取 Intent action，只有 `ACTION_START_ALL` / `ACTION_STOP_ALL` 两个被识别，
 * 命中就 `startService(new Intent(this, DownloadService.class).setAction(action))`，随后 `finish()`。
 *
 * 平台差异（DEVIATIONS 未登记但属同一类「Activity 生命周期不可搬」问题，已在 MR 描述里写明）：
 *   ArkTS 没有"执行完就 finish 的 Activity"。鸿蒙侧的等价物是 **honor 一个 Want**：
 *   快捷方式的 want.action 由 `EntryAbility.onCreate` / `AbilityStage.onCreate` 收到，
 *   这里提供静态入口 `handleWant()` 判定并转发，返回 true 表示"已消费，不要加载页面"。
 *   调用方据此决定是否 `windowStage.loadContent(...)`，语义等价于上游 `finish()`。
 *
 * 行为等价说明：
 *   1. 只识别 `start_all` / `stop_all`（其余 action 忽略，然后同样返回"已处理完毕"）。
 *      **注意**：上游无论 action 是否被识别都会 `finish()`，即"这个 Activity 永远不显示界面"。
 *      因此 `handleWant()` 对任意 action 都返回 true（消费并退出），由 `isHandledAction()`
 *      单独回答"这个 action 是否被下载服务接走"。
 *   2. `intent != null → action != null` 的判空链保留（want 为空/action 为空都不崩）。
 *   3. 上游用 `startService` 的显式 Intent 定向到 DownloadService；鸿蒙侧没有 Service 组件，
 *      下载服务是长时任务 + DownloadManager 单例，因此改为静态方法
 *      `DownloadService.dispatchAction(action)`（同一个 action 常量表）。
 */

import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { DownloadService } from '../download/DownloadService';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'ShortcutsActivity';

export class ShortcutsActivity {
  static readonly KEY_SHORTCUT_ACTION: string = 'shortcut_action';

  /** 上游 `getIntent().getAction()` 的鸿蒙等价：`parameters.shortcut_action` 优先，其次 `Want.action`。 */
  public static getAction(want: Want | null): string | null {
    if (want === null || want === undefined) {
      return null;
    }
    const params: Record<string, Object> | undefined = want.parameters;
    if (params !== undefined && params !== null) {
      const paramAction: Object | undefined = params[ShortcutsActivity.KEY_SHORTCUT_ACTION];
      if (typeof paramAction === 'string' && (paramAction as string).length > 0) {
        return paramAction as string;
      }
    }
    const action: string | undefined = want.action;
    if (action === undefined || action === null || action.length === 0) {
      return null;
    }
    return action;
  }

  public static isShortcutWant(want: Want | null): boolean {
    return ShortcutsActivity.isHandledAction(ShortcutsActivity.getAction(want));
  }

  /** 该 action 是否会被下载服务接走（上游那两个 equals 判断）。 */
  public static isHandledAction(action: string | null): boolean {
    if (action === null) {
      return false;
    }
    return action === DownloadService.ACTION_START_ALL || action === DownloadService.ACTION_STOP_ALL;
  }

  /**
   * 对应上游 `onCreate(savedInstanceState)`。
   *
   * @returns 恒为 true —— 等价于上游 `finish()`：调用方不要为这个 Want 加载任何页面。
   */
  public static handleWant(want: Want | null): boolean {
    const action: string | null = ShortcutsActivity.getAction(want);
    if (ShortcutsActivity.isHandledAction(action)) {
      hilog.info(DOMAIN, TAG, 'dispatch download action: %{public}s', action as string);
      DownloadService.dispatchAction(action as string);
    } else {
      hilog.info(DOMAIN, TAG, 'unhandled shortcut action, nothing to do: %{public}s',
        action === null ? 'null' : action);
    }
    return true;
  }
}
