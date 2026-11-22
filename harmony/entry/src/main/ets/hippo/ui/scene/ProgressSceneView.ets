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
 * Phase B Track P1: ProgressSceneView (@Component V1).
 *
 * Binds `ProgressSceneShell` / `ProgressScene`:
 * - `ProgressView.PROGRESS` displays `LoadingProgress`
 * - `ProgressView.TIP` displays `BigSadPandroid` + error text and taps to retry
 *   calling `ProgressSceneShell.retry()` → `ProgressScene.retry(...)`.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ProgressScene,
  ProgressState,
  ProgressView
} from '../../ehviewer/ui/scene/ProgressScene';
import { ProgressSceneShell } from '../../ehviewer/ui/scene/ProgressSceneShell';
import { BigSadPandroid } from '../drawable/big_sad_pandroid';

const DOMAIN: number = 0x0000;
const TAG: string = 'ProgressSceneView';
const TEXT_PRIMARY: string = '#DE000000';

@Component
export struct ProgressSceneView {
  shell: ProgressSceneShell | null = null;

  @State currentView: ProgressView = ProgressView.PROGRESS;
  @State errorText: string = '';
  @State useDefaultErrorRes: boolean = false;

  aboutToAppear(): void {
    this.bindShell();
  }

  aboutToDisappear(): void {
    if (this.shell !== null) {
      this.shell.setStateChangeListener(null);
    }
  }

  private bindShell(): void {
    const currentShell: ProgressSceneShell | null = this.shell;
    if (currentShell === null) {
      this.currentView = ProgressView.TIP;
      this.errorText = '';
      this.useDefaultErrorRes = true;
      hilog.warn(DOMAIN, TAG, 'ProgressSceneView mounted with null shell');
      return;
    }

    currentShell.setStateChangeListener((state: ProgressState): void => {
      this.applyState(state);
    });
    const state: ProgressState = currentShell.ensureInitialized(true);
    this.applyState(state);
  }

  private applyState(state: ProgressState): void {
    this.currentView = ProgressScene.viewFor(state);
    const err: string | null = state.error;
    if (err === null || err.length === 0 || err === ProgressScene.ERROR_SOMETHING_WRONG) {
      this.errorText = '';
      this.useDefaultErrorRes = true;
    } else {
      this.errorText = err;
      this.useDefaultErrorRes = false;
    }
  }

  private onRetryTap(): void {
    const currentShell: ProgressSceneShell | null = this.shell;
    if (currentShell === null) {
      return;
    }
    const relaunched: boolean = currentShell.retry(true);
    if (relaunched) {
      this.applyState(currentShell.getState());
    } else {
      hilog.warn(DOMAIN, TAG, 'ProgressScene retry did not relaunch (args invalid or requester unavailable)');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.currentView === ProgressView.PROGRESS) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.colorPrimary'))

          Text($r('app.string.loading'))
            .fontSize(14)
            .fontColor('#FF616161')
        }
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 10 }) {
          BigSadPandroid({ iconSize: 120 })

          Text(this.useDefaultErrorRes ? $r('app.string.error_something_wrong_happened') : this.errorText)
            .width(228)
            .fontSize(16)
            .fontColor(TEXT_PRIMARY)
            .textAlign(TextAlign.Center)

          Text($r('app.string.retry'))
            .fontSize(13)
            .fontColor($r('app.color.colorAccent'))
            .textAlign(TextAlign.Center)
        }
        .padding(24)
        .alignItems(HorizontalAlign.Center)
        .onClick((): void => {
          this.onRetryTap();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background_light'))
  }
}
