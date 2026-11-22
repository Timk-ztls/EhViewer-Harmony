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

/**
 * `com.hippo.lib.glview.annotation.RenderThread` 的 ArkTS 等价物。
 *
 * 上游是 `@Retention(SOURCE)` 的**纯标记注解**：编译期丢弃，零运行时行为。
 * ArkTS 不支持自定义注解（DEVIATIONS §5 第 2 条：无注解处理器），且 ArkTS 的
 * 装饰器只能用于 struct/class 的受支持集合，自定义标记装饰器会被编译器拒绝。
 *
 * 处理方式（保持可读性与可搜索性）：
 * 1. 保留本文件与同名导出的标记类，使 inventory 的 1:1 追溯关系成立；
 * 2. 上游被标注的方法/构造器，在 ArkTS 侧统一改用注释 `// @RenderThread`
 *    标记（`grep -rn "@RenderThread"` 仍能定位全部渲染线程约束点）；
 * 3. 运行期约束不靠注解，而靠 `GalleryUtils.assertInRenderThread()` 显式断言
 *    —— 上游本身也只有"注解 + 手工断言"两套，注解那套没有运行期效果。
 *
 * 因此这个类的唯一作用是**追溯锚点**，不要实例化它。
 */
export class RenderThread {
  private constructor() {
  }
}
