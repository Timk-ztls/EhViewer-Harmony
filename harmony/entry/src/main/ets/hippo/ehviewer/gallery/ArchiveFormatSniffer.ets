/*
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

import { UniRandomAccessFile } from '../../unifile/UniRandomAccessFile';

export enum ArchiveFormat {
  UNKNOWN = 0,
  ZIP = 1,
  SEVEN_ZIP = 2,
  RAR = 3,
}

export const RAR_UNSUPPORTED_ERROR_MARKER: string = '[rar:unsupported]';

export function detectArchiveFormat(header: Uint8Array): ArchiveFormat {
  if (header.length >= 6 &&
    header[0] === 0x37 && header[1] === 0x7A && header[2] === 0xBC &&
    header[3] === 0xAF && header[4] === 0x27 && header[5] === 0x1C) {
    return ArchiveFormat.SEVEN_ZIP;
  }
  if (header.length >= 6 &&
    header[0] === 0x52 && header[1] === 0x61 && header[2] === 0x72 &&
    header[3] === 0x21 && header[4] === 0x1A && header[5] === 0x07) {
    return ArchiveFormat.RAR;
  }
  if (header.length >= 4 && header[0] === 0x50 && header[1] === 0x4B &&
    ((header[2] === 0x03 && header[3] === 0x04) ||
      (header[2] === 0x05 && header[3] === 0x06) ||
      (header[2] === 0x07 && header[3] === 0x08))) {
    return ArchiveFormat.ZIP;
  }
  return ArchiveFormat.UNKNOWN;
}

export function sniffRandomAccessFormat(file: UniRandomAccessFile): ArchiveFormat {
  let prevPos: number = 0;
  try {
    prevPos = file.getFilePointer();
  } catch (_e) {
    prevPos = 0;
  }
  try {
    file.seek(0);
    const buf: ArrayBuffer = new ArrayBuffer(8);
    const n: number = file.readBytes(buf, 0, 8);
    if (n <= 0) {
      return ArchiveFormat.UNKNOWN;
    }
    return detectArchiveFormat(new Uint8Array(buf, 0, n));
  } catch (_e) {
    return ArchiveFormat.UNKNOWN;
  } finally {
    try {
      file.seek(prevPos);
    } catch (_restoreErr) {
      // ignore seek restore errors on closing handle
    }
  }
}

export function isRarUnsupportedError(err: Object | null | undefined): boolean {
  if (err === null || err === undefined) {
    return false;
  }
  const msg: string = err instanceof Error ? err.message : String(err);
  return msg.indexOf(RAR_UNSUPPORTED_ERROR_MARKER) >= 0;
}
