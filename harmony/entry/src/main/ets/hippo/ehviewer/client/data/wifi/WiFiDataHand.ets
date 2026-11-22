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

import { JsonObject } from '../../parser/Json';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/wifi/WiFiDataHand.java
 * （inventory S0068）
 *
 * 局域网传输的「消息信封」：
 *   messageType ∈ {ERROR=0, RECEIVED=1, SEND=2}
 *   dataType    —— 业务类型（1001 快速搜索 / 1002 下载信息 / 1003 标签 / 1004 收藏 / 1005-1007 迁移）
 *   data        —— 任意 JSON 对象
 *   pageSize/pageIndex —— 分页（字段名在 JSON 里是 **totalSize / part**，注意不是同名）
 *
 * 解析失败（上游 catch Throwable）：messageType 置 ERROR，errorMessage 记消息，data 置空对象。
 */
export class WiFiDataHand {
  static readonly ERROR: number = 0;
  static readonly RECEIVED: number = 1;
  static readonly SEND: number = 2;

  messageType: number = 0;
  dataType: number = 0;
  pageSize: number = 1;
  pageIndex: number = 1;
  errorMessage: string | null = null;
  private _data: string = '{}';

  constructor(messageType: number, data?: string) {
    this.messageType = messageType;
    if (data !== undefined && data !== null) {
      this._data = data;
    }
  }

  /** 对齐 `WiFiDataHand(String msg)`：从 JSON 文本构造，失败则 ERROR。 */
  static fromJson(msg: string): WiFiDataHand {
    try {
      const object: JsonObject = JsonObject.parse(msg);
      const hand: WiFiDataHand = new WiFiDataHand(object.getInt('messageType'));
      hand.dataType = object.getInt('dataType');
      hand._data = WiFidDataHandData.jsontOf(object);
      hand.pageSize = object.getLong('totalSize');
      hand.pageIndex = object.getLong('part');
      return hand;
    } catch (e) {
      const hand: WiFiDataHand = new WiFiDataHand(WiFiDataHand.ERROR);
      hand.errorMessage = (e as Error).message;
      hand._data = '{}';
      return hand;
    }
  }

  getData(): string {
    return this._data;
  }

  addData(key: string, value: string): void {
    this._data = WiFidDataHandData.put(this._data, key, value);
  }

  setData(data: string): void {
    this._data = data;
  }

  /** 对齐 `toJsonObject()`：键顺序 messageType / dataType / data / totalSize / part。 */
  toJsonObject(): string {
    // data 以原始 JSON 片段嵌入（不二次转义），与上游 JSONObject.put(key, JSONObject) 一致
    return '{"messageType":' + this.messageType +
      ',"dataType":' + this.dataType +
      // _data 是非空 string（默认 '{}'），只需判空串；原来的 `=== null` 是死代码（C-7 规则②）
      ',"data":' + (this._data.length === 0 ? '{}' : this._data) +
      ',"totalSize":' + this.pageSize +
      ',"part":' + this.pageIndex + '}';
  }

  toString(): string {
    return this.toJsonObject();
  }
}

/** 内部 JSON 片段操作（避免把整个对象反复解析/序列化）。 */
class WiFidDataHandData {
  static jsontOf(object: JsonObject): string {
    if (!object.has('data') || object.isNull('data')) {
      return '{}';
    }
    // 取 data 的原始文本：重新序列化该对象字段（Json 层没有保留原文，故逐键输出）
    return object.getJSONObject('data').rawText();
  }

  static put(json: string, key: string, value: string): string {
    const quotedKey: string = JSON.stringify(key);
    const quotedValue: string = JSON.stringify(value);
    const base: string = json === null || json.length === 0 || json === '{}' ? '' : json;
    if (base.length === 0) {
      return '{' + quotedKey + ':' + quotedValue + '}';
    }
    // 简单场景：在末尾 '}' 前插入
    return base.substring(0, base.length - 1) + ',' + quotedKey + ':' + quotedValue + '}';
  }
}
