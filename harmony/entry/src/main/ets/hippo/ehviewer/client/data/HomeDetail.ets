/*
 * Copyright 2016 Hippo Seven
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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/HomeDetail.java
 * （inventory S0053）
 *
 * 首页「H@H 配额 / GP 收益 / 管理权限」面板数据。
 *
 * 注意上游 getter 的两个细节（照搬）：
 *   - `getResetCost()/getFromXxx()` 返回带 `" Gp"` 后缀的字符串（`withGp(long)`）
 *   - `resetCost()` 才是原始 long；`getImageLimits()` 在 total==0 时返回一句提示文案
 *     （上游从 `R.string.ip_base_limits` 取，属 core-runtime 的 i18n → 用 HomeDetailConfig 注入）
 */
export class HomeDetail {
  private _used: number = 0;
  private _total: number = 0;
  private _resetCost: number = 0;
  private _fromGalleryVisits: number = 0;
  private _fromTorrentCompletions: number = 0;
  private _fromArchiveDownloads: number = 0;
  private _fromHentaiAtHome: number = 0;
  private _currentModerationPower: number = 0;

  getUsed(): number {
    return this._used;
  }

  setUsed(used: number): void {
    this._used = used;
  }

  getTotal(): number {
    return this._total;
  }

  setTotal(total: number): void {
    this._total = total;
  }

  /** 带 " Gp" 后缀（上游 getResetCost 的返回值）。 */
  getResetCost(): string {
    return HomeDetail.withGp(this._resetCost);
  }

  /** 原始数值（上游 resetCost()）。 */
  resetCost(): number {
    return this._resetCost;
  }

  setResetCost(resetCost: number): void {
    this._resetCost = resetCost;
  }

  getFromGalleryVisits(): string {
    return HomeDetail.withGp(this._fromGalleryVisits);
  }

  setFromGalleryVisits(v: number): void {
    this._fromGalleryVisits = v;
  }

  getFromTorrentCompletions(): string {
    return HomeDetail.withGp(this._fromTorrentCompletions);
  }

  setFromTorrentCompletions(v: number): void {
    this._fromTorrentCompletions = v;
  }

  getFromArchiveDownloads(): string {
    return HomeDetail.withGp(this._fromArchiveDownloads);
  }

  setFromArchiveDownloads(v: number): void {
    this._fromArchiveDownloads = v;
  }

  getFromHentaiAtHome(): string {
    return HomeDetail.withGp(this._fromHentaiAtHome);
  }

  setFromHentaiAtHome(v: number): void {
    this._fromHentaiAtHome = v;
  }

  getCurrentModerationPower(): string {
    return `${this._currentModerationPower}`;
  }

  setCurrentModerationPower(v: number): void {
    this._currentModerationPower = v;
  }

  /** total == 0 时返回提示文案，否则 "used/total"。 */
  getImageLimits(config: HomeDetailConfig): string {
    if (this._total === 0) {
      return config.getIpBaseLimits();
    }
    return this._used + '/' + this._total;
  }

  private static withGp(l: number): string {
    return l + ' Gp';
  }
}

/** core-runtime 的 i18n 注入点（`R.string.ip_base_limits`）。 */
export class HomeDetailConfig {
  getIpBaseLimits(): string {
    return 'IP-based limits';
  }
}
