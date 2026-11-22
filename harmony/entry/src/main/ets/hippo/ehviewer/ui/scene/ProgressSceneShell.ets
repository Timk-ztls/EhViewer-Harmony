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

/*
 * Phase B Track P1: ProgressScene BaseScene/SceneFragment shell.
 *
 * Bridges the pure-logic `ProgressScene` state machine with `BaseScene` lifecycle,
 * `GalleryTokenRequester` injection, retry handling, and navigation to
 * `GalleryDetailScene` on success.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { Announcer } from '../../../scene/Announcer';
import { SceneArgs } from '../../../scene/SceneTypes';
import { BaseScene } from './BaseScene';
import {
  DEFAULT_GID,
  DEFAULT_PAGE,
  GalleryTokenRequester,
  KEY_ACTION,
  KEY_GID,
  KEY_PAGE,
  KEY_PTOKEN,
  ProgressArgs,
  ProgressScene,
  ProgressState,
  ProgressView
} from './ProgressScene';

const DOMAIN: number = 0x0000;
const TAG: string = 'ProgressSceneShell';

export class UnavailableGalleryTokenRequester implements GalleryTokenRequester {
  private warned: boolean = false;

  requestGalleryToken(gid: number, pToken: string, page: number): boolean {
    if (!this.warned) {
      this.warned = true;
      hilog.warn(DOMAIN, TAG,
        'GalleryTokenRequester 未接线: gid=%{public}d page=%{public}d；后果：进入错误提示态，可点击重试',
        gid, page);
    }
    return false;
  }
}

/**
 * `ProgressScene` 的 `BaseScene` 外壳。
 */
export class ProgressSceneShell extends BaseScene {
  static readonly DETAIL_SCENE_NAME: string = 'GalleryDetailScene';

  private requester: GalleryTokenRequester | null;
  private fallbackRequester: UnavailableGalleryTokenRequester = new UnavailableGalleryTokenRequester();
  private state: ProgressState = new ProgressState(
    false,
    ProgressScene.ERROR_SOMETHING_WRONG,
    new ProgressArgs(null, DEFAULT_GID, null, DEFAULT_PAGE)
  );
  private initialized: boolean = false;
  private stateChangeListener: ((state: ProgressState) => void) | null = null;

  constructor(requester: GalleryTokenRequester | null = null) {
    super();
    this.requester = requester;
  }

  getSceneName(): string {
    return 'ProgressScene';
  }

  needShowLeftDrawer(): boolean {
    return ProgressScene.NEED_SHOW_LEFT_DRAWER;
  }

  setRequester(requester: GalleryTokenRequester | null): void {
    this.requester = requester;
  }

  getRequester(): GalleryTokenRequester {
    if (this.requester !== null) {
      return this.requester;
    }
    return this.fallbackRequester;
  }

  setStateChangeListener(listener: ((state: ProgressState) => void) | null): void {
    this.stateChangeListener = listener;
  }

  getState(): ProgressState {
    return this.state;
  }

  getCurrentView(): ProgressView {
    return ProgressScene.viewFor(this.state);
  }

  getErrorText(): string | null {
    return this.state.error;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  /** 将 `SceneArgs`（Bundle 等价物）提取为强类型 `ProgressArgs`。 */
  static extractProgressArgs(args: SceneArgs | null): ProgressArgs | null {
    if (args === null) {
      return null;
    }
    const rawAction: Object | undefined = args.get(KEY_ACTION);
    const rawGid: Object | undefined = args.get(KEY_GID);
    const rawPToken: Object | undefined = args.get(KEY_PTOKEN);
    const rawPage: Object | undefined = args.get(KEY_PAGE);

    const action: string | null = typeof rawAction === 'string' ? rawAction : null;
    const gid: number = typeof rawGid === 'number' ? rawGid : DEFAULT_GID;
    const pToken: string | null = typeof rawPToken === 'string' ? rawPToken : null;
    const page: number = typeof rawPage === 'number' ? rawPage : DEFAULT_PAGE;

    return new ProgressArgs(action, gid, pToken, page);
  }

  /** 首次进入时执行两段式初始化（`handleArgs` → `doJobs`）；若已初始化则直接返回当前态。 */
  ensureInitialized(contextAlive: boolean = true): ProgressState {
    if (!this.initialized) {
      return this.initFromArguments(contextAlive);
    }
    return this.state;
  }

  /** 按当前 `getArguments()` 执行初始化（上游 `onInit`）。 */
  initFromArguments(contextAlive: boolean = true): ProgressState {
    const parsedArgs: ProgressArgs | null = ProgressSceneShell.extractProgressArgs(this.getArguments());
    this.state = ProgressScene.init(parsedArgs, contextAlive, this.getRequester());
    this.initialized = true;
    this.notifyStateChanged();
    return this.state;
  }

  /** 从已保存状态恢复（上游 `onRestore`：不重发请求）。 */
  restoreFromSaved(valid: boolean, error: string | null, args: ProgressArgs): ProgressState {
    this.state = ProgressScene.restore(valid, error, args);
    this.initialized = true;
    this.notifyStateChanged();
    return this.state;
  }

  /** 导出可保存状态（上游 `onSaveInstanceState`）。 */
  saveState(): ProgressState {
    return ProgressScene.toSaved(this.state);
  }

  /** 点击错误提示重试（上游 `onClick(mTip)`）。 */
  retry(contextAlive: boolean = true): boolean {
    const ok: boolean = ProgressScene.retry(this.state, contextAlive, this.getRequester());
    if (ok) {
      this.notifyStateChanged();
    }
    return ok;
  }

  /**
   * 获取 `gallery_token` 成功回调（上游 `onGetGalleryTokenSuccess`）：
   * 构造 `GalleryDetailScene` 参数（`action=gid_token`）→ `startScene` → `finish()`。
   */
  onGetGalleryTokenSuccess(token: string): Map<string, Object> {
    const detailArgs: Map<string, Object> = ProgressScene.detailArgsOnSuccess(this.state, token);
    this.startScene(new Announcer(ProgressSceneShell.DETAIL_SCENE_NAME).setArgs(detailArgs));
    this.finish();
    return detailArgs;
  }

  /**
   * 获取 `gallery_token` 失败回调（上游 `onGetGalleryTokenFailure`）：
   * 总是更新状态，仅在 context 与视图存活时通知 UI 刷新。
   */
  onGetGalleryTokenFailure(readableError: string, contextAlive: boolean = true): boolean {
    const shouldRefreshUi: boolean = ProgressScene.applyFailure(
      this.state,
      contextAlive,
      !this.viewDestroyed,
      readableError
    );
    if (shouldRefreshUi) {
      this.notifyStateChanged();
    }
    return shouldRefreshUi;
  }

  private notifyStateChanged(): void {
    if (this.stateChangeListener !== null) {
      try {
        this.stateChangeListener(this.state);
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'stateChangeListener threw: %{public}s', msg);
      }
    }
  }
}
