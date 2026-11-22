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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/scene/ProgressScene.java（221 行）。
 *
 * ============================================================================
 * 一、上游是什么（"后台任务进度页"）
 * ============================================================================
 * 这个页面**只有一个任务**：拿 `gallery_token`。
 *
 *   ```java
 *   onCreate: savedInstanceState == null ? onInit() : onRestore(...)
 *   onInit:   mValid = handleArgs(getArguments());
 *             if (mValid) mValid = doJobs();
 *             if (!mValid) mError = getString(R.string.error_something_wrong_happened);
 *   doJobs:   ACTION_GALLERY_TOKEN → 参数不全（gid==-1 / pToken==null / page==-1）→ false
 *             否则发 METHOD_GET_GALLERY_TOKEN 请求 → true
 *   视图：    valid → 显示进度圈；!valid → 显示"难过安卓"图 + 错误文案（**可点击重试**）
 *   点击 tip：doJobs() 成功 → mValid = true + 切进度圈
 *   成功回调：跳 GalleryDetailScene，参数 (KEY_ACTION=ACTION_GID_TOKEN, gid, token, page) + finish
 *   失败回调：mValid = false；有 context/transition/tip 时 → 显示可读错误串（getReadableString）
 *   ```
 *
 * 逐行对照时最容易丢的**六条**（本文件逐条保留并断言）：
 *   1. **参数三缺一就无效**：`gid == -1` / `pToken == null` / `page == -1`，任一命中即 false；
 *      （注意 `page` 的 sentinel 是 **-1**，不是 0 —— 第 0 页是合法值）
 *   2. `onInit` 是**两段式**：先 `handleArgs` 再 `doJobs`，`handleArgs` 为假时**根本不发请求**；
 *   3. 无效时错误文案是**固定资源串**（`error_something_wrong_happened`），不是请求错误；
 *   4. 失败回调会**再判一次三个空值**（context / transition / tip）—— 视图已销毁时只改状态不改 UI；
 *   5. 点 tip 重试成功才切进度圈；`doJobs()` 返回 false（还是参数不全）**什么都不做**；
 *   6. 恢复时全部字段从 bundle 读，`mValid` 为真则直接显示进度圈（不发请求）。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * 上游 221 行里约 80 行是 Android 视图/事务胶水。移植分三层：
 *   - **状态机/判据**（本文件）：参数校验、初始化两段式、视图选择、成功/失败后的字段变换；
 *   - **发请求** → 注入 `GalleryTokenRequester`（生产实现包 EhEngine 的 `METHOD_GET_GALLERY_TOKEN`）；
 *   - **界面** → `showImage`/`tipText` 之类纯数据（进度圈 vs 错误提示）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'ProgressScene';

/** bundle 键（上游常量，逐字对齐）。 */
export const KEY_ACTION: string = 'action';
export const ACTION_GALLERY_TOKEN: string = 'gallery_token';
export const KEY_VALID: string = 'valid';
export const KEY_ERROR: string = 'error';
export const KEY_GID: string = 'gid';
export const KEY_PTOKEN: string = 'ptoken';
export const KEY_PAGE: string = 'page';

/** 跳转 `GalleryDetailScene` 时用的键（上游 `GalleryDetailScene.KEY_*`）。 */
export const DETAIL_KEY_ACTION: string = 'action';
export const DETAIL_ACTION_GID_TOKEN: string = 'gid_token';
export const DETAIL_KEY_GID: string = 'gid';
export const DETAIL_KEY_TOKEN: string = 'token';
export const DETAIL_KEY_PAGE: string = 'page';

/** 参数缺省哨兵（上游 `getLong(KEY_GID, -1)` / `getInt(KEY_PAGE, -1)`）。 */
export const DEFAULT_GID: number = -1;
export const DEFAULT_PAGE: number = -1;

/** 页面要显示哪个视图（上游 `ViewTransition.showView(0/1)`）。 */
export enum ProgressView {
  /** 进度圈（0） */
  PROGRESS = 0,
  /** 错误提示（1，"难过安卓"图 + 文案，可点击重试） */
  TIP = 1
}

/** 页面参数（上游 `mAction/mGid/mPToken/mPage` 四件套）。 */
export class ProgressArgs {
  action: string | null = null;
  gid: number = DEFAULT_GID;
  pToken: string | null = null;
  page: number = DEFAULT_PAGE;

  constructor(action: string | null, gid: number, pToken: string | null, page: number) {
    this.action = action;
    this.gid = gid;
    this.pToken = pToken;
    this.page = page;
  }
}

/** 页面状态（可序列化；对应上游 `onSaveInstanceState` 写的那几项）。 */
export class ProgressState {
  valid: boolean = false;
  error: string | null = null;
  args: ProgressArgs = new ProgressArgs(null, DEFAULT_GID, null, DEFAULT_PAGE);

  constructor(valid: boolean, error: string | null, args: ProgressArgs) {
    this.valid = valid;
    this.error = error;
    this.args = args;
  }
}

/** 发请求的能力（生产实现包 EhEngine）。 */
export interface GalleryTokenRequester {
  /** 发起 `METHOD_GET_GALLERY_TOKEN(gid, pToken, page)`；成功返回 true（上游 `doJobs` 的返回值）。 */
  requestGalleryToken(gid: number, pToken: string, page: number): boolean;
}

/**
 * 进度页（对位上游 `ProgressScene`）。
 */
export class ProgressScene {
  /** 不显示左侧抽屉（上游 `needShowLeftDrawer() = false`）。 */
  static readonly NEED_SHOW_LEFT_DRAWER: boolean = false;
  /** 无效时的固定错误文案资源名（上游 `R.string.error_something_wrong_happened`）。 */
  static readonly ERROR_SOMETHING_WRONG: string = 'error_something_wrong_happened';

  /**
   * 解析页面参数并校验（上游 `handleArgs`）。
   *
   * 只有 `ACTION_GALLERY_TOKEN` 一种动作；三缺一（gid==-1 / pToken==null / page==-1）→ false。
   *
   * @returns 合法时返回参数对象；否则 null
   */
  static handleArgs(args: ProgressArgs | null): ProgressArgs | null {
    if (args === null) {
      return null;
    }
    if (args.action !== ACTION_GALLERY_TOKEN) {
      return null;
    }
    if (args.gid === DEFAULT_GID || args.pToken === null || args.page === DEFAULT_PAGE) {
      return null;
    }
    return args;
  }

  /**
   * 是否应该发请求（上游 `doJobs` 的前半段）—— context/activity 为空时返回 false。
   *
   * 参数校验**再做一遍**（上游 `doJobs` 里确实重复校验了 mGid/mPToken/mPage）。
   */
  static canRunJobs(contextAlive: boolean, args: ProgressArgs | null): boolean {
    if (!contextAlive || args === null) {
      return false;
    }
    if (args.action !== ACTION_GALLERY_TOKEN) {
      return false;
    }
    return !(args.gid === DEFAULT_GID || args.pToken === null || args.page === DEFAULT_PAGE);
  }

  /**
   * 初始化（上游 `onInit`）：两段式 —— 先校验参数，合法才发请求。
   *
   * @returns 页面状态；`valid=false` 时 `error` 是固定文案
   */
  static init(args: ProgressArgs | null, contextAlive: boolean,
    requester: GalleryTokenRequester): ProgressState {
    const handled: ProgressArgs | null = ProgressScene.handleArgs(args);
    if (handled === null) {
      return new ProgressState(false, ProgressScene.ERROR_SOMETHING_WRONG, ProgressArgsFrom(args));
    }
    const launched: boolean = ProgressScene.canRunJobs(contextAlive, handled)
      ? requester.requestGalleryToken(handled.gid, handled.pToken as string, handled.page)
      : false;
    if (!launched) {
      return new ProgressState(false, ProgressScene.ERROR_SOMETHING_WRONG, handled);
    }
    return new ProgressState(true, null, handled);
  }

  /** 恢复（上游 `onRestore`）：全部字段来自 bundle，**不发请求**。 */
  static restore(valid: boolean, error: string | null, args: ProgressArgs): ProgressState {
    return new ProgressState(valid, error, args);
  }

  /** 该显示哪个视图（上游 `onCreateView2` 末尾的 `showView(0/1)`）。 */
  static viewFor(state: ProgressState): ProgressView {
    return state.valid ? ProgressView.PROGRESS : ProgressView.TIP;
  }

  /**
   * 点击错误提示重试（上游 `onClick`）。
   *
   * @returns 重试是否成功；成功时 `valid` 置真、切进度圈
   */
  static retry(state: ProgressState, contextAlive: boolean,
    requester: GalleryTokenRequester): boolean {
    if (!ProgressScene.canRunJobs(contextAlive, state.args)) {
      return false;
    }
    const launched: boolean = requester.requestGalleryToken(state.args.gid,
      state.args.pToken as string, state.args.page);
    if (!launched) {
      return false;
    }
    state.valid = true;
    return true;
  }

  /**
   * 请求成功（上游 `onGetGalleryTokenSuccess`）：要跳到详情页的参数。
   *
   * 注意 `KEY_ACTION` 在详情页侧的取值是 **`gid_token`**（与本页的 `gallery_token` 不同）。
   */
  static detailArgsOnSuccess(state: ProgressState, token: string): Map<string, Object> {
    const out: Map<string, Object> = new Map<string, Object>();
    out.set(DETAIL_KEY_ACTION, DETAIL_ACTION_GID_TOKEN);
    out.set(DETAIL_KEY_GID, state.args.gid);
    out.set(DETAIL_KEY_TOKEN, token);
    out.set(DETAIL_KEY_PAGE, state.args.page);
    return out;
  }

  /**
   * 请求失败（上游 `onGetGalleryTokenFailure`）。
   *
   * 状态一定变（valid=false），但**只有 context/transition/tip 都在**时才更新 UI 文案。
   *
   * @param readable 上游 `ExceptionUtils.getReadableString(e)` 的结果
   * @returns 是否应该刷新 UI 文案
   */
  static applyFailure(state: ProgressState, contextAlive: boolean, viewAlive: boolean,
    readable: string): boolean {
    state.valid = false;
    state.error = readable;
    if (!contextAlive || !viewAlive) {
      hilog.info(DOMAIN, TAG, 'failure while view gone, state updated only');
      return false;
    }
    return true;
  }

  /** 保存实例状态（上游 `onSaveInstanceState` 的字段集）。 */
  static toSaved(state: ProgressState): ProgressState {
    return new ProgressState(state.valid, state.error, state.args);
  }
}

/** 把可空参数转成非空参数（失败时也要保留原始值做诊断）。 */
function ProgressArgsFrom(args: ProgressArgs | null): ProgressArgs {
  if (args === null) {
    return new ProgressArgs(null, DEFAULT_GID, null, DEFAULT_PAGE);
  }
  return args;
}
