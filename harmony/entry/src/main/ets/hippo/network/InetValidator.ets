/*
 * Copyright 2017 Hippo Seven
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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/InetValidator.java
 * （inventory S0439，56 行）
 *
 * IPv4 地址与端口校验。`EhConfig.updateUconfig()` 用它决定 H@H 客户端地址是否写进 uconfig。
 *
 * 逐行照搬的边界：
 *   - 每段必须非空且 <= 255
 *   - 多位数不允许前导 0（"01.2.3.4" 非法）
 *   - 端口范围 0..65535
 */
export class InetValidator {
  private static readonly IPV4_PATTERN: RegExp =
    /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;

  static isValidInet4Address(inet4Address: string | null): boolean {
    if (inet4Address === null || inet4Address === undefined) {
      return false;
    }
    const m: RegExpMatchArray | null = inet4Address.match(InetValidator.IPV4_PATTERN);
    if (m === null) {
      return false;
    }
    for (let i = 1; i <= 4; i++) {
      const seg: string = m[i];
      if (seg === null || seg === undefined || seg.length === 0) {
        return false;
      }
      const v: number = Number.parseInt(seg, 10);
      if (Number.isNaN(v)) {
        return false;
      }
      if (v > 255) {
        return false;
      }
      if (seg.length > 1 && seg.startsWith('0')) {
        return false;
      }
    }
    return true;
  }

  static isValidInetPort(inetPort: number): boolean {
    return inetPort >= 0 && inetPort <= 65535;
  }
}
