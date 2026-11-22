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

import { EhException } from './EhException';

/**
 * ehviewer 的 9 个异常类中的 6 个「无额外字段」异常，逐个对位上游：
 *   OffensiveException        —— `super("OFFENSIVE")`（g.e-hentai.org 的警告页）
 *   PiningException           —— `super("pining for the fjords")`（画廊已删除）
 *   GalleryUnavailableException —— 空实现（画廊不可用）
 *   EmptyGalleryException     —— 空实现
 *   NoHAtHClientException     —— 空实现（无 H@H 客户端）
 *   Image509Exception         —— 空实现（图床 509 限流）
 *   CancelledException        —— 空实现（请求被取消）
 *
 * 为什么合并到一个文件：它们都是「只有类名语义、没有字段」的标记异常，
 * ArkTS 的一个文件可导出多个类；分开 7 个 20 行文件只会制造噪声。
 * `EhException`/`ParseException` 有字段，仍单独成文件。
 *
 * 关键：`instanceof` 分派必须成立（EhEngine / ui-scene 按具体类型 catch），
 * 所以每个都显式 extends EhException，不是类型别名。
 */

export class OffensiveException extends EhException {
  constructor() {
    super('OFFENSIVE');
    this.name = 'OffensiveException';
  }
}

export class PiningException extends EhException {
  constructor() {
    super('pining for the fjords');
    this.name = 'PiningException';
  }
}

export class GalleryUnavailableException extends EhException {
  constructor() {
    super('This gallery is unavailable');
    this.name = 'GalleryUnavailableException';
  }
}

export class EmptyGalleryException extends EhException {
  constructor() {
    super('Empty gallery');
    this.name = 'EmptyGalleryException';
  }
}

export class NoHAtHClientException extends EhException {
  constructor() {
    super('No H@H client');
    this.name = 'NoHAtHClientException';
  }
}

export class Image509Exception extends EhException {
  constructor() {
    super('509');
    this.name = 'Image509Exception';
  }
}

export class CancelledException extends EhException {
  constructor() {
    super('Cancelled');
    this.name = 'CancelledException';
  }
}
