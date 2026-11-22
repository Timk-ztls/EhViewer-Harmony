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
 * 用户自定义标签，两个文件对位上游：
 *   userTag/UserTag.java      (S0066) —— 单条（id/名称/关注/隐藏/颜色/权重）
 *   userTag/UserTagList.java  (S0067) —— 容器
 *
 * UserTag 的三个方法逐条照搬：
 *   - `getName(EhTagDatabase)`：`Settings.getShowTagTranslations()` 为真、且名称含一个 ':' 时，
 *     走 TagTranslationUtil 翻译（core-runtime 的 i18n 能力 → 用 UserTagConfig 注入，默认不翻译）
 *   - `getId()`：`Long.parseLong(userTagId.substring(8))`（id 形如 `usertag_12345`，取掉 8 位前缀）
 *   - `deleteParam()`：拼表单串，`modify_usertags%5B%5D` 里的 `%5B%5D` 就是 `[]`
 */
export class UserTag {
  userTagId: string = '';
  tagName: string = '';
  watched: boolean = false;
  hidden: boolean = false;
  color: string = '';
  tagWeight: number = 0;

  /** 对齐 `getName(EhTagDatabase ehTags)`。 */
  getName(config: UserTagConfig, ehTags: Object | null): string {
    if (config.getShowTagTranslations()) {
      const name: string = this.tagName;
      if (name !== null && name.split(':').length === 2) {
        return config.getTagTranslation(name.split(':'), ehTags);
      }
    }
    return this.tagName;
  }

  /** 对齐 `getId()`：userTagId 的前 8 个字符是 `usertag_` 前缀。 */
  getId(): number {
    return Number.parseInt(this.userTagId.substring(8), 10);
  }

  /** 对齐 `deleteParam()`：删除该用户标签的表单参数串。 */
  deleteParam(): string {
    return 'usertag_action=mass' +
      '&tagname_new=' +
      '&tagcolor_new=' +
      '&tagweight_new=' + this.tagWeight +
      '&modify_usertags%5B%5D=' + this.getId() +
      '&usertag_target=0';
  }
}

/** 1:1 对位 `userTag/UserTagList.java`。 */
export class UserTagList {
  userTags: UserTag[] = [];

  get(index: number): UserTag {
    return this.userTags[index];
  }

  size(): number {
    return this.userTags.length;
  }
}

/**
 * 1:1 对位 `userTag/TagPushParam.java`（inventory S0065）。
 *
 * 注意上游 `getEncodeTagName()` / `getEncodeColorName()` 里的 `replace(...)` **结果被丢弃**
 * （Java 的 String 不可变，`tagName.replace(":", "%3A");` 不改变 tagName）：
 * 所以实际发出去的是**未编码**的标签名与颜色（`:`、空格、`#` 都不转义）。
 * 这是上游既成行为，照搬；修它会改变请求体字节。
 */
export class TagPushParam {
  userTagAction: string = '';
  tagNameNew: string = '';
  // 这三个字段上游**真的会传 null**（C-7 审计 ②a：addTagParam / getEncodeColorName 里有 null 判定），
  // 所以按 C-7 规则① 声明成 `string | null`，默认 null —— 与上游语义一致。
  // 若这里给 ''，上游的 `if (tagHiddenNew != null && ...)` 就会变成死代码。
  tagWatchNew: string | null = null;
  tagHiddenNew: string | null = null;
  tagColorNew: string | null = null;
  tagWeightNew: number = 0;
  userTagTarget: number = 0;

  /** 对齐 `addTagParam()`：hidden 先判、watch 后判 → **两者都开时 watch 生效**。 */
  addTagParam(): string {
    let state: string = '';
    if (this.tagHiddenNew !== null && this.tagHiddenNew === 'on') {
      state = '&taghide_new=on';
    }
    if (this.tagWatchNew !== null && this.tagWatchNew === 'on') {
      state = '&tagwatch_new=on';
    }
    return 'usertag_action=add&tagname_new=' + this.getEncodeTagName() +
      state + '&tagcolor_new=' + this.getEncodeColorName() +
      '&tagweight_new=10&usertag_target=0';
  }

  /** 对齐 `getEncodeTagName()`：上游并未真正编码（见类注释）。 */
  private getEncodeTagName(): string {
    return this.tagNameNew;
  }

  /** 对齐 `getEncodeColorName()`：颜色为空时返回空串；同样未真正编码。 */
  private getEncodeColorName(): string {
    if (this.tagColorNew === null) {
      return '';
    }
    return this.tagColorNew;
  }
}

/**
 * core-runtime 的 i18n/设置注入点：
 *   Settings.getShowTagTranslations()（默认 false，与上游默认一致）
 *   TagTranslationUtil.getTagCN(namespace, ehTags)
 */
export class UserTagConfig {
  getShowTagTranslations(): boolean {
    return false;
  }

  getTagTranslation(names: string[], ehTags: Object | null): string {
    return names.join(':');
  }
}
