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
 * 1:1 对位 upstream: .../client/data/Tag.java（inventory S0059，44 行）
 *
 * 中英对照标签（EhTagDatabase 的翻译表条目）。
 * 上游是 Parcelable 但 writeToParcel 什么都不写（空实现），故本层不需要任何序列化。
 */
export class Tag {
  public english: string;
  public chinese: string;

  /** 对齐 Tag(String content) —— 单参构造：english = content，chinese 留空。 */
  constructor(english: string, chinese: string = '') {
    this.english = english;
    this.chinese = chinese;
  }

  /** 对齐 Tag.setEnglish(String content)。 */
  setEnglish(content: string): void {
    this.english = content;
  }

  /** 对齐 Tag.involve(String chars)：英文或中文任一包含即命中。 */
  involve(chars: string): boolean {
    if (this.english.indexOf(chars) >= 0) {
      return true;
    }
    return this.chinese.indexOf(chars) >= 0;
  }
}
