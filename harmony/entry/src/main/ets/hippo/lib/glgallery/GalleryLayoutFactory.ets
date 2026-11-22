/*
 * Copyright 2016 Hippo Seven
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

import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  GalleryLayoutManager,
  GalleryLayoutManagerFactory,
  GalleryView
} from './GalleryView';
import { ScrollLayoutManager } from './ScrollLayoutManager';

const TAG = 'GalleryLayoutFactory';
const DOMAIN = 0x0000;

/** 构造一个布局管理器（`PagerLayoutManager` 落地前用它做注入点）。 */
export type PagerLayoutManagerCreator =
  (galleryView: GalleryView, scaleMode: number, startPosition: number,
    pagerInterval: number) => GalleryLayoutManager;

/**
 * `GalleryLayoutManagerFactory` 的实现：把 `ScrollLayoutManager` / `PagerLayoutManager`
 * 接到 `GalleryView.setLayoutManagerFactory()` 上（**独立文件，不动 `GalleryView` 契约**）。
 *
 * ## 为什么要这一层
 * `GalleryView` 只声明"要一个 pager / 一个 scroll 管理器"（`GalleryLayoutManagerFactory`），
 * 具体类是**后面才落地**的。用一个工厂接缝：
 * - 本文件现在能给 `ScrollLayoutManager`（已交付）
 * - `PagerLayoutManager`（net-parse 在做）落地后，**调用 `setPagerCreator(...)` 一行接上**，
 *   `GalleryView` 与 `ScrollLayoutManager` 都不用改
 *
 * ## 未注入 pager 时的行为（**降级，不崩**）
 * `createPagerLayoutManager` 抛 `PagerLayoutManagerUnavailableError`；
 * `GalleryView.ensurePagerLayoutManager()` 捕获后返回 null 并打 warn → 布局不排页但不崩溃。
 * 之所以不在工厂里返回 null：`GalleryLayoutManagerFactory` 的返回类型是非空
 * （`GalleryView` 的 `xxxInternal` 都在 null 上有分支，但契约选择"非空返回 + 失败抛错"更显式）。
 */
export class PagerLayoutManagerUnavailableError extends Error {
  constructor() {
    super('PagerLayoutManager not registered yet (call GalleryLayoutFactory.setPagerCreator)');
  }
}

export class GalleryLayoutFactory implements GalleryLayoutManagerFactory {
  private static sInstance: GalleryLayoutFactory | null = null;
  private static sPagerCreator: PagerLayoutManagerCreator | null = null;

  /** 注入 `PagerLayoutManager` 的构造器（net-parse 落地后调用一次）。 */
  static setPagerCreator(creator: PagerLayoutManagerCreator | null): void {
    GalleryLayoutFactory.sPagerCreator = creator;
  }

  static hasPagerCreator(): boolean {
    return GalleryLayoutFactory.sPagerCreator !== null;
  }

  static getInstance(): GalleryLayoutFactory {
    let instance = GalleryLayoutFactory.sInstance;
    if (instance === null) {
      instance = new GalleryLayoutFactory();
      GalleryLayoutFactory.sInstance = instance;
    }
    return instance;
  }

  /**
   * 安装到 `GalleryView`（幂等）。
   * 应在应用启动、`GLRootView` 创建之前调用一次。
   */
  static install(): GalleryLayoutFactory {
    const factory = GalleryLayoutFactory.getInstance();
    GalleryView.setLayoutManagerFactory(factory);
    return factory;
  }

  /** 卸载（测试用）。 */
  static uninstall(): void {
    GalleryView.setLayoutManagerFactory(null);
    GalleryLayoutFactory.sPagerCreator = null;
  }

  createPagerLayoutManager(galleryView: GalleryView, scaleMode: number, startPosition: number,
    pagerInterval: number): GalleryLayoutManager {
    const creator = GalleryLayoutFactory.sPagerCreator;
    if (creator === null) {
      throw new PagerLayoutManagerUnavailableError();
    }
    return creator(galleryView, scaleMode, startPosition, pagerInterval);
  }

  createScrollLayoutManager(galleryView: GalleryView, scrollInterval: number): GalleryLayoutManager {
    return new ScrollLayoutManager(galleryView, scrollInterval);
  }

  /** 诊断：当前能否创建 pager 管理器。 */
  static describe(): string {
    return GalleryLayoutFactory.sPagerCreator === null
      ? 'pager=unavailable scroll=ready'
      : 'pager=ready scroll=ready';
  }
}
