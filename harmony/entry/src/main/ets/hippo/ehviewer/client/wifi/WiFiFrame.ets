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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/wifi/WiFiFrame.java
 * （inventory S0117，27 行）
 *
 * 帧头 5 个整型 + 可选 payload。字段顺序即协议顺序（见 WiFiFrameCodec 的 22 字节头）。
 */
export class WiFiFrame {
  messageType: number = 0;
  dataType: number = 0;
  pageIndex: number = 0;
  pageSize: number = 0;
  flags: number = 0;
  payload: ArrayBuffer | null = null;

  constructor(messageType?: number, dataType?: number, pageIndex?: number, pageSize?: number,
    flags?: number, payload?: ArrayBuffer | null) {
    if (messageType !== undefined) {
      this.messageType = messageType;
    }
    if (dataType !== undefined) {
      this.dataType = dataType;
    }
    if (pageIndex !== undefined) {
      this.pageIndex = pageIndex;
    }
    if (pageSize !== undefined) {
      this.pageSize = pageSize;
    }
    if (flags !== undefined) {
      this.flags = flags;
    }
    if (payload !== undefined) {
      this.payload = payload;
    }
  }
}
