/*
 * NAPI 胶水层：ZIP 随机按页解压（Stage C Track P5 - Z2）。
 *
 * 使用 NDK 内置 zlib (-lz) 解析 ZIP Central Directory (EOCD + CD) 并支持
 * STORE (method 0) 与 DEFLATE (method 8) 条目的按页流式随机解压（不预先解包整卷）。
 * 对接 ArchiveGalleryProvider / A7ZipArchive 的 A7ZipBridge，通过 readAt(pos, buf, len)
 * 回调直接读取 UniRandomAccessFile，支持任意 ZIP64 以下标准 ZIP / CBZ。
 *
 * 错误码前缀：[zip:70xx]（与 napi_7z.c 统一）。
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "napi_common.h"

#define EHZIP_MAX_HANDLES 32
#define EHZIP_IO_BUF_SIZE 65536u
#define EHZIP_EOCD_MIN_LEN 22u
#define EHZIP_EOCD_MAX_SEARCH (65535u + 22u)
#define EHZIP_CD_MIN_LEN 46u
#define EHZIP_LFH_LEN 30u
#define EHZIP_MAX_CD_BYTES (32u * 1024u * 1024u)
#define EHZIP_MAX_ENTRY_BYTES (64u * 1024u * 1024u)

#define EHZIP_ERR_BAD_ARG 7002
#define EHZIP_ERR_EXTRACT 7003
#define EHZIP_ERR_PASSWORD 7004

typedef struct {
  char* name;
  uint16_t flags;
  uint16_t method;
  uint32_t compressedSize;
  uint32_t uncompressedSize;
  uint32_t localHeaderOffset;
  bool isDir;
  bool encrypted;
} ZipEntry;

typedef struct {
  bool active;
  napi_ref readAtFnRef;
  napi_ref ioBufRef;
  void* ioBufData;
  size_t ioBufCap;
  uint64_t length;
  ZipEntry* entries;
  uint32_t entryCount;
  bool allEncrypted;
} ZipArchiveSlot;

static ZipArchiveSlot g_zipArchives[EHZIP_MAX_HANDLES];

static void zip_throw_code(napi_env env, int code, const char* message) {
  char buffer[1024];
  snprintf(buffer, sizeof(buffer), "[zip:%d] %s", code, message);
  napi_throw_error(env, NULL, buffer);
}

static uint16_t read_u16_le(const uint8_t* p) {
  return (uint16_t) p[0] | ((uint16_t) p[1] << 8);
}

static uint32_t read_u32_le(const uint8_t* p) {
  return (uint32_t) p[0] |
         ((uint32_t) p[1] << 8) |
         ((uint32_t) p[2] << 16) |
         ((uint32_t) p[3] << 24);
}

static bool zip_read_exact(napi_env env, ZipArchiveSlot* slot, uint64_t offset,
                           uint8_t* dst, size_t len) {
  size_t total = 0;
  napi_value fn = NULL;
  napi_value ioBuf = NULL;
  napi_value global = NULL;

  if (len == 0) {
    return true;
  }
  if (offset > slot->length || (uint64_t) len > slot->length - offset) {
    return false;
  }
  if (napi_get_reference_value(env, slot->readAtFnRef, &fn) != napi_ok ||
      napi_get_reference_value(env, slot->ioBufRef, &ioBuf) != napi_ok ||
      napi_get_global(env, &global) != napi_ok) {
    return false;
  }

  while (total < len) {
    size_t chunk = len - total;
    if (chunk > slot->ioBufCap) {
      chunk = slot->ioBufCap;
    }
    napi_value args[3] = { NULL };
    napi_value ret = NULL;
    bool pending = false;
    int32_t got = 0;

    napi_create_double(env, (double) (offset + total), &args[0]);
    args[1] = ioBuf;
    napi_create_uint32(env, (uint32_t) chunk, &args[2]);
    if (napi_call_function(env, global, fn, 3, args, &ret) != napi_ok) {
      return false;
    }
    napi_is_exception_pending(env, &pending);
    if (pending) {
      return false;
    }
    if (napi_get_value_int32(env, ret, &got) != napi_ok || got <= 0) {
      return false;
    }
    if ((size_t) got > chunk) {
      got = (int32_t) chunk;
    }
    memcpy(dst + total, slot->ioBufData, (size_t) got);
    total += (size_t) got;
  }
  return true;
}

static void close_zip_slot(napi_env env, ZipArchiveSlot* slot) {
  if (slot == NULL || !slot->active) {
    return;
  }
  if (slot->entries != NULL) {
    for (uint32_t i = 0; i < slot->entryCount; i++) {
      free(slot->entries[i].name);
    }
    free(slot->entries);
    slot->entries = NULL;
  }
  if (env != NULL) {
    if (slot->readAtFnRef != NULL) {
      napi_delete_reference(env, slot->readAtFnRef);
    }
    if (slot->ioBufRef != NULL) {
      napi_delete_reference(env, slot->ioBufRef);
    }
  }
  memset(slot, 0, sizeof(*slot));
}

static ZipArchiveSlot* get_zip_slot(napi_env env, napi_value handleVal) {
  int32_t handle = 0;
  if (napi_get_value_int32(env, handleVal, &handle) != napi_ok ||
      handle < 1 || handle > EHZIP_MAX_HANDLES) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "invalid zip archive handle");
    return NULL;
  }
  ZipArchiveSlot* slot = &g_zipArchives[handle - 1];
  if (!slot->active) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "zip archive handle is closed");
    return NULL;
  }
  return slot;
}

static bool parse_zip_directory(napi_env env, ZipArchiveSlot* slot) {
  size_t tailLen;
  uint64_t tailOffset;
  uint8_t* tailBuf = NULL;
  ssize_t eocdIdx = -1;
  uint16_t diskNum;
  uint16_t cdDisk;
  uint16_t diskEntries;
  uint16_t totalEntries;
  uint32_t cdSize;
  uint32_t cdOffset;
  uint8_t* cdBuf = NULL;
  size_t pos = 0;
  uint32_t parsedCount = 0;
  uint32_t nonDirCount = 0;
  uint32_t encryptedNonDirCount = 0;

  if (slot->length < EHZIP_EOCD_MIN_LEN) {
    return false;
  }
  tailLen = slot->length > EHZIP_EOCD_MAX_SEARCH ? EHZIP_EOCD_MAX_SEARCH : (size_t) slot->length;
  tailOffset = slot->length - (uint64_t) tailLen;
  tailBuf = (uint8_t*) malloc(tailLen);
  if (tailBuf == NULL) {
    return false;
  }
  if (!zip_read_exact(env, slot, tailOffset, tailBuf, tailLen)) {
    free(tailBuf);
    return false;
  }

  for (ssize_t i = (ssize_t) (tailLen - EHZIP_EOCD_MIN_LEN); i >= 0; i--) {
    if (tailBuf[i] == 0x50 && tailBuf[i + 1] == 0x4B &&
        tailBuf[i + 2] == 0x05 && tailBuf[i + 3] == 0x06) {
      uint16_t commentLen = read_u16_le(tailBuf + i + 20);
      if ((size_t) i + EHZIP_EOCD_MIN_LEN + (size_t) commentLen == tailLen) {
        eocdIdx = i;
        break;
      }
    }
  }
  if (eocdIdx < 0) {
    free(tailBuf);
    return false;
  }

  const uint8_t* eocd = tailBuf + eocdIdx;
  diskNum = read_u16_le(eocd + 4);
  cdDisk = read_u16_le(eocd + 6);
  diskEntries = read_u16_le(eocd + 8);
  totalEntries = read_u16_le(eocd + 10);
  cdSize = read_u32_le(eocd + 12);
  cdOffset = read_u32_le(eocd + 16);
  free(tailBuf);

  /* 多卷或 ZIP64 哨兵交由上层 ArkTS zlib fallback 处理 */
  if (diskNum != 0 || cdDisk != 0 || diskEntries != totalEntries ||
      totalEntries == 0xFFFFu || cdSize == 0xFFFFFFFFu || cdOffset == 0xFFFFFFFFu) {
    return false;
  }
  if ((uint64_t) cdOffset > slot->length || (uint64_t) cdSize > slot->length - (uint64_t) cdOffset ||
      cdSize > EHZIP_MAX_CD_BYTES) {
    return false;
  }

  if (totalEntries == 0) {
    slot->entries = NULL;
    slot->entryCount = 0;
    slot->allEncrypted = false;
    return true;
  }

  cdBuf = (uint8_t*) malloc((size_t) cdSize);
  if (cdBuf == NULL) {
    return false;
  }
  if (!zip_read_exact(env, slot, (uint64_t) cdOffset, cdBuf, (size_t) cdSize)) {
    free(cdBuf);
    return false;
  }

  slot->entries = (ZipEntry*) calloc(totalEntries, sizeof(ZipEntry));
  if (slot->entries == NULL) {
    free(cdBuf);
    return false;
  }

  while (parsedCount < totalEntries && pos + EHZIP_CD_MIN_LEN <= (size_t) cdSize) {
    const uint8_t* hdr = cdBuf + pos;
    uint32_t sig = read_u32_le(hdr);
    uint16_t nameLen;
    uint16_t extraLen;
    uint16_t commentLen;
    size_t recLen;
    ZipEntry* entry;
    char* nameCopy;

    if (sig != 0x02014B50u) {
      free(cdBuf);
      slot->entryCount = parsedCount;
      return false;
    }

    nameLen = read_u16_le(hdr + 28);
    extraLen = read_u16_le(hdr + 30);
    commentLen = read_u16_le(hdr + 32);
    recLen = EHZIP_CD_MIN_LEN + (size_t) nameLen + (size_t) extraLen + (size_t) commentLen;
    if (pos + recLen > (size_t) cdSize) {
      free(cdBuf);
      slot->entryCount = parsedCount;
      return false;
    }

    nameCopy = (char*) malloc((size_t) nameLen + 1u);
    if (nameCopy == NULL) {
      free(cdBuf);
      slot->entryCount = parsedCount;
      return false;
    }
    if (nameLen > 0) {
      memcpy(nameCopy, hdr + EHZIP_CD_MIN_LEN, (size_t) nameLen);
      for (uint16_t k = 0; k < nameLen; k++) {
        if (nameCopy[k] == '\\') {
          nameCopy[k] = '/';
        }
      }
    }
    nameCopy[nameLen] = '\0';

    entry = &slot->entries[parsedCount];
    entry->name = nameCopy;
    entry->flags = read_u16_le(hdr + 8);
    entry->method = read_u16_le(hdr + 10);
    entry->compressedSize = read_u32_le(hdr + 20);
    entry->uncompressedSize = read_u32_le(hdr + 24);
    entry->localHeaderOffset = read_u32_le(hdr + 42);
    entry->isDir = (nameLen > 0 && nameCopy[nameLen - 1] == '/');
    entry->encrypted = ((entry->flags & 0x0001u) != 0);

    if (!entry->isDir) {
      nonDirCount++;
      if (entry->encrypted) {
        encryptedNonDirCount++;
      }
    }

    parsedCount++;
    pos += recLen;
  }

  free(cdBuf);
  if (parsedCount != totalEntries) {
    slot->entryCount = parsedCount;
    return false;
  }
  slot->entryCount = parsedCount;
  slot->allEncrypted = (nonDirCount > 0 && encryptedNonDirCount == nonDirCount);
  return true;
}

static napi_value OpenZip(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  double totalLength = 0;
  napi_valuetype fnType = napi_undefined;
  int slotIndex = -1;
  napi_value ioBufVal = NULL;
  ZipArchiveSlot* slot = NULL;
  bool pending = false;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "openZip(length, readAt)");
    return NULL;
  }
  if (napi_get_value_double(env, argv[0], &totalLength) != napi_ok ||
      totalLength < (double) EHZIP_EOCD_MIN_LEN) {
    return ehviewer_napi_int32(env, 0);
  }
  if (napi_typeof(env, argv[1], &fnType) != napi_ok || fnType != napi_function) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "openZip readAt must be a function");
    return NULL;
  }

  for (int i = 0; i < EHZIP_MAX_HANDLES; i++) {
    if (!g_zipArchives[i].active) {
      slotIndex = i;
      break;
    }
  }
  if (slotIndex < 0) {
    zip_throw_code(env, EHZIP_ERR_EXTRACT, "too many open zip archives");
    return NULL;
  }

  slot = &g_zipArchives[slotIndex];
  memset(slot, 0, sizeof(*slot));
  slot->active = true;
  slot->length = (uint64_t) totalLength;
  if (napi_create_arraybuffer(env, EHZIP_IO_BUF_SIZE, &slot->ioBufData, &ioBufVal) != napi_ok ||
      slot->ioBufData == NULL) {
    close_zip_slot(env, slot);
    zip_throw_code(env, EHZIP_ERR_EXTRACT, "out of memory creating zip io buffer");
    return NULL;
  }
  slot->ioBufCap = EHZIP_IO_BUF_SIZE;
  napi_create_reference(env, argv[1], 1, &slot->readAtFnRef);
  napi_create_reference(env, ioBufVal, 1, &slot->ioBufRef);

  bool parsed = parse_zip_directory(env, slot);
  napi_is_exception_pending(env, &pending);
  if (pending) {
    napi_value ignored = NULL;
    napi_get_and_clear_last_exception(env, &ignored);
  }
  if (!parsed) {
    close_zip_slot(env, slot);
    return ehviewer_napi_int32(env, 0);
  }
  return ehviewer_napi_int32(env, slotIndex + 1);
}

static napi_value CloseZip(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  int32_t handle = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) == napi_ok && argc >= 1 &&
      napi_get_value_int32(env, argv[0], &handle) == napi_ok &&
      handle >= 1 && handle <= EHZIP_MAX_HANDLES) {
    close_zip_slot(env, &g_zipArchives[handle - 1]);
  }
  return NULL;
}

static napi_value GetZipEntryCount(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  ZipArchiveSlot* slot = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "getZipEntryCount(handle)");
    return NULL;
  }
  slot = get_zip_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  return ehviewer_napi_int32(env, (int32_t) slot->entryCount);
}

static napi_value GetZipEntryName(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  ZipArchiveSlot* slot = NULL;
  int32_t index = 0;
  napi_value ret = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "getZipEntryName(handle, index)");
    return NULL;
  }
  slot = get_zip_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (uint32_t) index >= slot->entryCount) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "zip entry index out of range");
    return NULL;
  }
  const char* name = slot->entries[index].name != NULL ? slot->entries[index].name : "";
  napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &ret);
  return ret;
}

static napi_value IsZipEntryDir(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  ZipArchiveSlot* slot = NULL;
  int32_t index = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "isZipEntryDir(handle, index)");
    return NULL;
  }
  slot = get_zip_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (uint32_t) index >= slot->entryCount) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "zip entry index out of range");
    return NULL;
  }
  return ehviewer_napi_bool(env, slot->entries[index].isDir);
}

static napi_value IsZipEncrypted(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  ZipArchiveSlot* slot = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "isZipEncrypted(handle)");
    return NULL;
  }
  slot = get_zip_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  return ehviewer_napi_bool(env, slot->allEncrypted);
}

static napi_value IsZipEntryEncrypted(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  ZipArchiveSlot* slot = NULL;
  int32_t index = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "isZipEntryEncrypted(handle, index)");
    return NULL;
  }
  slot = get_zip_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (uint32_t) index >= slot->entryCount) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "zip entry index out of range");
    return NULL;
  }
  return ehviewer_napi_bool(env, slot->entries[index].encrypted);
}

static napi_value ExtractZipEntry(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  ZipArchiveSlot* slot = NULL;
  int32_t index = 0;
  const ZipEntry* entry = NULL;
  uint8_t lfh[EHZIP_LFH_LEN];
  uint16_t lfhNameLen;
  uint16_t lfhExtraLen;
  uint64_t dataOffset;
  uint8_t* srcBuf = NULL;
  void* dstData = NULL;
  napi_value outAb = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "extractZipEntry(handle, index)");
    return NULL;
  }
  slot = get_zip_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (uint32_t) index >= slot->entryCount) {
    zip_throw_code(env, EHZIP_ERR_BAD_ARG, "zip entry index out of range");
    return NULL;
  }
  entry = &slot->entries[index];
  if (entry->isDir) {
    if (napi_create_arraybuffer(env, 0, &dstData, &outAb) != napi_ok) {
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "failed to create empty ArrayBuffer");
      return NULL;
    }
    return outAb;
  }
  if (entry->encrypted) {
    zip_throw_code(env, EHZIP_ERR_PASSWORD, "encrypted zip entry is not supported");
    return NULL;
  }
  if (entry->uncompressedSize > EHZIP_MAX_ENTRY_BYTES ||
      entry->compressedSize > EHZIP_MAX_ENTRY_BYTES) {
    zip_throw_code(env, EHZIP_ERR_EXTRACT, "zip entry exceeds 64MB limit");
    return NULL;
  }
  if (!zip_read_exact(env, slot, (uint64_t) entry->localHeaderOffset, lfh, EHZIP_LFH_LEN) ||
      read_u32_le(lfh) != 0x04034B50u) {
    zip_throw_code(env, EHZIP_ERR_EXTRACT, "invalid zip local file header");
    return NULL;
  }
  lfhNameLen = read_u16_le(lfh + 26);
  lfhExtraLen = read_u16_le(lfh + 28);
  dataOffset = (uint64_t) entry->localHeaderOffset + (uint64_t) EHZIP_LFH_LEN +
               (uint64_t) lfhNameLen + (uint64_t) lfhExtraLen;

  if (entry->uncompressedSize == 0) {
    if (napi_create_arraybuffer(env, 0, &dstData, &outAb) != napi_ok) {
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "failed to create empty ArrayBuffer");
      return NULL;
    }
    return outAb;
  }

  if (entry->compressedSize == 0 && entry->method == 0) {
    if (napi_create_arraybuffer(env, 0, &dstData, &outAb) != napi_ok) {
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "failed to create empty ArrayBuffer");
      return NULL;
    }
    return outAb;
  }

  if (entry->compressedSize > 0) {
    srcBuf = (uint8_t*) malloc((size_t) entry->compressedSize);
    if (srcBuf == NULL) {
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "out of memory reading compressed zip entry");
      return NULL;
    }
    if (!zip_read_exact(env, slot, dataOffset, srcBuf, (size_t) entry->compressedSize)) {
      free(srcBuf);
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "failed to read zip entry bytes");
      return NULL;
    }
  }

  if (entry->method == 0) {
    /* STORE */
    if (entry->compressedSize != entry->uncompressedSize) {
      free(srcBuf);
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "stored zip size mismatch");
      return NULL;
    }
    if (napi_create_arraybuffer(env, (size_t) entry->uncompressedSize, &dstData, &outAb) != napi_ok ||
        dstData == NULL) {
      free(srcBuf);
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "failed to allocate output ArrayBuffer");
      return NULL;
    }
    memcpy(dstData, srcBuf, (size_t) entry->uncompressedSize);
    free(srcBuf);
    return outAb;
  }

  if (entry->method == 8) {
    /* DEFLATE: raw deflate stream (-MAX_WBITS) */
    if (napi_create_arraybuffer(env, (size_t) entry->uncompressedSize, &dstData, &outAb) != napi_ok ||
        dstData == NULL) {
      free(srcBuf);
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "failed to allocate inflate output ArrayBuffer");
      return NULL;
    }
    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    zs.next_in = (Bytef*) srcBuf;
    zs.avail_in = (uInt) entry->compressedSize;
    zs.next_out = (Bytef*) dstData;
    zs.avail_out = (uInt) entry->uncompressedSize;
    int initRet = inflateInit2(&zs, -MAX_WBITS);
    if (initRet != Z_OK) {
      free(srcBuf);
      zip_throw_code(env, EHZIP_ERR_EXTRACT, "inflateInit2 failed");
      return NULL;
    }
    int infRet = inflate(&zs, Z_FINISH);
    inflateEnd(&zs);
    free(srcBuf);
    if (infRet != Z_STREAM_END && !(infRet == Z_OK && zs.total_out == entry->uncompressedSize)) {
      char msg[128];
      snprintf(msg, sizeof(msg), "inflate failed: ret=%d", infRet);
      zip_throw_code(env, EHZIP_ERR_EXTRACT, msg);
      return NULL;
    }
    return outAb;
  }

  free(srcBuf);
  {
    char msg[128];
    snprintf(msg, sizeof(msg), "unsupported zip compression method: %u", (unsigned) entry->method);
    zip_throw_code(env, EHZIP_ERR_EXTRACT, msg);
  }
  return NULL;
}

napi_value napi_zip_init(napi_env env, napi_value exports) {
  napi_property_descriptor functions[] = {
      { "openZip", NULL, OpenZip, NULL, NULL, NULL, napi_default, NULL },
      { "closeZip", NULL, CloseZip, NULL, NULL, NULL, napi_default, NULL },
      { "getZipEntryCount", NULL, GetZipEntryCount, NULL, NULL, NULL, napi_default, NULL },
      { "getZipEntryName", NULL, GetZipEntryName, NULL, NULL, NULL, napi_default, NULL },
      { "isZipEntryDir", NULL, IsZipEntryDir, NULL, NULL, NULL, napi_default, NULL },
      { "isZipEncrypted", NULL, IsZipEncrypted, NULL, NULL, NULL, napi_default, NULL },
      { "isZipEntryEncrypted", NULL, IsZipEntryEncrypted, NULL, NULL, NULL, napi_default, NULL },
      { "extractZipEntry", NULL, ExtractZipEntry, NULL, NULL, NULL, napi_default, NULL },
  };

  napi_define_properties(env, exports, sizeof(functions) / sizeof(functions[0]), functions);
  return exports;
}
