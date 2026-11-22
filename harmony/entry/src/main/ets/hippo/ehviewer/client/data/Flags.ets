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
 * 位标志常量（net-parse 内部使用）。
 *
 * 权威定义分工（Lead 2026-10-24 裁决）：
 *   - 分类位（MISC..ALL_CATEGORY）与 namespace 位的**权威定义在本模块的 `client/EhConfig.ets`（S0071）**。
 *     本文件的 `CategoryFlags` 是 `EhConfig` 落地前的临时载体，现在改为**从 EhConfig 取值**，
 *     不再自己写数值 —— 否则 download-sync 的 `filterDownloadKind` 会面临「两个来源选哪个」的问题
 *     （这正是 Lead 指出的掉单形态）。
 *   - `AdvanceSearchFlags` 的权威定义在 ui-widget 的 `AdvanceSearchTable`（尚未落地）。
 *     本文件先承载数值，两边按 `check-flags.ps1` 的期望表校验一致。
 *
 * 变更历史：
 *   2026-10-24 初版把分类位写在本文件并注释「属 core-runtime 的 EhConfig」——该注释是错的
 *   （`client` 包 13/13 全在 net-parse 分片），已按 Lead 要求改为引用 EhConfig。
 */
import { EhConfig } from '../EhConfig';

/**
 * 分类位：数值全部来自 `EhConfig`（单一来源）。
 * 保留 `CategoryFlags` 这个名字，因为 `ListUrlBuilder` 等已按它引用；语义上它就是 `EhConfig.MISC` 等常量。
 */
export class CategoryFlags {
  /** EhUtils.NONE（首页用）：不是分类位，是「未选择」哨兵。 */
  static readonly NONE: number = -1;
  static readonly UNKNOWN: number = 0x400;
  static readonly MISC: number = EhConfig.MISC;
  static readonly DOUJINSHI: number = EhConfig.DOUJINSHI;
  static readonly MANGA: number = EhConfig.MANGA;
  static readonly ARTIST_CG: number = EhConfig.ARTIST_CG;
  static readonly GAME_CG: number = EhConfig.GAME_CG;
  static readonly IMAGE_SET: number = EhConfig.IMAGE_SET;
  static readonly COSPLAY: number = EhConfig.COSPLAY;
  static readonly ASIAN_PORN: number = EhConfig.ASIAN_PORN;
  static readonly NON_H: number = EhConfig.NON_H;
  static readonly WESTERN: number = EhConfig.WESTERN;
  static readonly ALL_CATEGORY: number = EhConfig.ALL_CATEGORY;
}

/**
 * 高级搜索位：权威定义在 ui-widget 的 `AdvanceSearchTable`。
 * 数值来自 `origin/upstream:app/src/main/java/com/hippo/ehviewer/widget/AdvanceSearchTable.java`。
 */
export class AdvanceSearchFlags {
  static readonly SNAME: number = 0x1;
  static readonly STAGS: number = 0x2;
  static readonly SDESC: number = 0x4;
  static readonly STORR: number = 0x8;
  static readonly STO: number = 0x10;
  static readonly SDT1: number = 0x20;
  static readonly SDT2: number = 0x40;
  static readonly SH: number = 0x80;
  static readonly SFL: number = 0x100;
  static readonly SFU: number = 0x200;
  static readonly SFT: number = 0x400;

  /** 上游 `ListUrlBuilder.DEFAULT_ADVANCE = SNAME | STAGS`。 */
  static readonly DEFAULT_ADVANCE: number = AdvanceSearchFlags.SNAME | AdvanceSearchFlags.STAGS;

  /** 上游 `ListUrlBuilder.DEFAULT_MIN_RATING = 2`。 */
  static readonly DEFAULT_MIN_RATING: number = 2;
}
