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
 * 1:1 对位 upstream: .../client/data/NewVersion.java（inventory S0056，32 行）
 *
 * 画廊详情页「新版本」列表项（同作品的其它语言/修正版）。
 * 上游字段 versionName/versionUrl 为 public String，无默认值（可能为 null），
 * 本层用空串初始值 + 注释：读方只做非空判断，语义等价。
 */
export class NewVersion {
  versionName: string = '';
  versionUrl: string = '';

  constructor(versionName: string = '', versionUrl: string = '') {
    this.versionName = versionName;
    this.versionUrl = versionUrl;
  }

  /** 深拷贝（上游走 Parcel）。字段都是基本类型，直接赋值即可。 */
  copy(): NewVersion {
    const n: NewVersion = new NewVersion();
    n.versionName = this.versionName;
    n.versionUrl = this.versionUrl;
    return n;
  }}
