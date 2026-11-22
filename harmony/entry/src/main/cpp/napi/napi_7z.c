/*
 * NAPI 胶水层：7z 解压（D-004 方案 A）。
 *
 * 上游：com.hippo.ehviewer.gallery.A7ZipArchive（Kotlin）→ a7zip_XJ（预编译 .so）。
 * 鸿蒙侧：7-Zip 官方 C 源码 24.09 最小子集（见 cpp/7z/README.md）静态链入本产物，
 *         用 SzArEx 简化 API 解压；归档数据直接从 ArkTS 传入的 ArrayBuffer 读，
 *         不落临时文件。
 *
 * 构建开关（顶层 CMake）：
 *   -DEHVIEWER_7Z=ON  → 编译 cpp/7z/lzma7z 并定义 EHVIEWER_7Z=1，本文件走真实实现
 *   默认 OFF          → 不引用任何 7z 头，extract7z() 抛 7001「未编译」
 * 两种情况下都**没有**纯 JS 假实现。
 *
 * 错误码：7001 未编译 / 7002 参数非法 / 7003 解压失败 / 7004 口令问题
 */

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#include "napi_common.h"

#ifndef EHVIEWER_7Z
#define EHVIEWER_7Z 0
#endif

#define EHVIEWER_7Z_ERR_NOT_BUILT 7001
#define EHVIEWER_7Z_ERR_BAD_ARG   7002
#define EHVIEWER_7Z_ERR_EXTRACT   7003
#define EHVIEWER_7Z_ERR_PASSWORD  7004

static void throw_code(napi_env env, int code, const char* message) {
  /* NAPI 没有统一的「带 code 的 Error」写法：把 code 写进 message 前缀，
   * ArkTS 侧 NativeImageError 原样透传，日志也能按 [7z:70xx] 检索。 */
  char buffer[1024];
  snprintf(buffer, sizeof(buffer), "[7z:%d] %s", code, message);
  napi_throw_error(env, NULL, buffer);
}

#if EHVIEWER_7Z

#include "7z.h"
#include "7zCrc.h"
#include "7zTypes.h"

static void ensure_crc_table(void) {
  static bool crcInitialized = false;
  if (!crcInitialized) {
    CrcGenerateTable();
    crcInitialized = true;
  }
}

/* ---------------- 内存归档流（ILookInStream 只读实现） ---------------- */

typedef struct {
  ILookInStream vt;
  const Byte* data;
  size_t size;
  size_t pos;
} MemoryLookInStream;

static SRes mem_look(ILookInStreamPtr pp, const void** buf, size_t* size) {
  MemoryLookInStream* stream = (MemoryLookInStream*) (void*) pp;
  size_t remain = stream->pos <= stream->size ? stream->size - stream->pos : 0;
  if (*size > remain) {
    *size = remain;
  }
  *buf = stream->data + stream->pos;
  return SZ_OK;
}

static SRes mem_skip(ILookInStreamPtr pp, size_t offset) {
  MemoryLookInStream* stream = (MemoryLookInStream*) (void*) pp;
  if (stream->pos > stream->size || offset > stream->size - stream->pos) {
    return SZ_ERROR_READ;
  }
  stream->pos += offset;
  return SZ_OK;
}

static SRes mem_read(ILookInStreamPtr pp, void* buf, size_t* size) {
  MemoryLookInStream* stream = (MemoryLookInStream*) (void*) pp;
  size_t remain = stream->pos <= stream->size ? stream->size - stream->pos : 0;
  size_t count = *size;
  if (count > remain) {
    count = remain;
  }
  if (count > 0) {
    memcpy(buf, stream->data + stream->pos, count);
  }
  stream->pos += count;
  *size = count;
  return SZ_OK;
}

static SRes mem_seek(ILookInStreamPtr pp, Int64* pos, ESzSeek origin) {
  MemoryLookInStream* stream = (MemoryLookInStream*) (void*) pp;
  Int64 base;
  Int64 next;

  switch (origin) {
    case SZ_SEEK_SET: base = 0; break;
    case SZ_SEEK_CUR: base = (Int64) stream->pos; break;
    case SZ_SEEK_END: base = (Int64) stream->size; break;
    default: return SZ_ERROR_PARAM;
  }
  next = base + *pos;
  if (next < 0 || (UInt64) next > (UInt64) stream->size) {
    return SZ_ERROR_READ;
  }
  stream->pos = (size_t) next;
  *pos = next;
  return SZ_OK;
}

static void memory_look_in_stream_init(MemoryLookInStream* stream, const Byte* data, size_t size) {
  stream->vt.Look = mem_look;
  stream->vt.Skip = mem_skip;
  stream->vt.Read = mem_read;
  stream->vt.Seek = mem_seek;
  stream->data = data;
  stream->size = size;
  stream->pos = 0;
}

/* ---------------- 分配器 ---------------- */

static void* eh7z_alloc(ISzAllocPtr p, size_t size) {
  (void) p;
  return malloc(size);
}

static void eh7z_free(ISzAllocPtr p, void* address) {
  (void) p;
  free(address);
}

static const ISzAlloc g_eh7z_alloc = { eh7z_alloc, eh7z_free };

/* ---------------- UTF-16 → UTF-8 ---------------- */

static char* utf16_to_utf8(const UInt16* src) {
  size_t capacity = 1;
  size_t length = 0;
  char* out;

  for (size_t i = 0; src[i] != 0; i++) {
    UInt32 code = src[i];
    if (code >= 0xD800 && code <= 0xDBFF && src[i + 1] >= 0xDC00 && src[i + 1] <= 0xDFFF) {
      code = 0x10000 + (((code - 0xD800) << 10) | (src[i + 1] - 0xDC00));
      i++;
    }
    capacity += code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
  }

  out = (char*) malloc(capacity);
  if (out == NULL) {
    return NULL;
  }
  for (size_t i = 0; src[i] != 0; i++) {
    UInt32 code = src[i];
    if (code >= 0xD800 && code <= 0xDBFF && src[i + 1] >= 0xDC00 && src[i + 1] <= 0xDFFF) {
      code = 0x10000 + (((code - 0xD800) << 10) | (src[i + 1] - 0xDC00));
      i++;
    }
    if (code < 0x80) {
      out[length++] = (char) code;
    } else if (code < 0x800) {
      out[length++] = (char) (0xC0 | (code >> 6));
      out[length++] = (char) (0x80 | (code & 0x3F));
    } else if (code < 0x10000) {
      out[length++] = (char) (0xE0 | (code >> 12));
      out[length++] = (char) (0x80 | ((code >> 6) & 0x3F));
      out[length++] = (char) (0x80 | (code & 0x3F));
    } else {
      out[length++] = (char) (0xF0 | (code >> 18));
      out[length++] = (char) (0x80 | ((code >> 12) & 0x3F));
      out[length++] = (char) (0x80 | ((code >> 6) & 0x3F));
      out[length++] = (char) (0x80 | (code & 0x3F));
    }
  }
  out[length] = '\0';
  return out;
}

/* ---------------- 文件系统 ---------------- */

static bool mkdirs(const char* path) {
  char buffer[4096];
  size_t length = strlen(path);

  if (length == 0 || length >= sizeof(buffer)) {
    return false;
  }
  memcpy(buffer, path, length + 1);
  for (size_t i = 1; i < length; i++) {
    if (buffer[i] == '/') {
      struct stat st;
      buffer[i] = '\0';
      if (mkdir(buffer, 0755) != 0) {
        if (stat(buffer, &st) != 0 || !S_ISDIR(st.st_mode)) {
          return false;
        }
      }
      buffer[i] = '/';
    }
  }
  if (mkdir(buffer, 0755) != 0) {
    struct stat st;
    if (stat(buffer, &st) != 0) {
      return false;
    }
    return S_ISDIR(st.st_mode);
  }
  return true;
}

/* 归档内路径不得逃出 outDir（zip-slip） */
static bool is_safe_relative_path(const char* name) {
  const char* p;

  if (name == NULL || name[0] == '\0' || name[0] == '/' || name[0] == '\\') {
    return false;
  }
  if (strstr(name, ":") != NULL || strstr(name, "\\") != NULL) {
    return false;
  }
  p = name;
  while (*p != '\0') {
    if ((p == name || p[-1] == '/') && p[0] == '.' && p[1] == '.' &&
        (p[2] == '/' || p[2] == '\0')) {
      return false;
    }
    p++;
  }
  return true;
}

static int write_file(const char* path, const Byte* data, size_t size) {
  FILE* file = fopen(path, "wb");
  size_t written;

  if (file == NULL) {
    return -1;
  }
  written = size == 0 ? 0 : fwrite(data, 1, size, file);
  fclose(file);
  return written == size ? 0 : -1;
}

/* ---------------- extract7z ---------------- */

static napi_value Extract7z(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = { NULL };
  void* archive = NULL;
  size_t archiveLength = 0;
  char outDir[1024];
  size_t outDirLength = 0;
  char password[256];
  size_t passwordLength = 0;
  MemoryLookInStream stream;
  CSzArEx db;
  SRes res;
  UInt32 fileIndex;
  UInt32 blockIndex = 0xFFFFFFFF;
  Byte* outBuffer = NULL;
  size_t outBufferSize = 0;
  int extracted = 0;
  char message[512];

  ensure_crc_table();

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "extract7z(archive, outDir, password?)");
    return NULL;
  }
  if (!ehviewer_napi_get_bytes(env, argv[0], &archive, &archiveLength) || archive == NULL ||
      archiveLength == 0) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "archive must be a non-empty ArrayBuffer");
    return NULL;
  }
  if (napi_get_value_string_utf8(env, argv[1], outDir, sizeof(outDir), &outDirLength) != napi_ok ||
      outDirLength == 0) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "outDir must be a non-empty string");
    return NULL;
  }
  if (argc >= 3) {
    napi_get_value_string_utf8(env, argv[2], password, sizeof(password), &passwordLength);
  }
  /* outDir 必须已存在且是目录：不在 native 侧静默创建顶层目录 */
  {
    struct stat st;
    if (stat(outDir, &st) != 0 || !S_ISDIR(st.st_mode)) {
      throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "outDir does not exist or is not a directory");
      return NULL;
    }
  }

  memory_look_in_stream_init(&stream, (const Byte*) archive, archiveLength);
  SzArEx_Init(&db);

  res = SzArEx_Open(&db, &stream.vt, &g_eh7z_alloc, &g_eh7z_alloc);
  if (res != SZ_OK) {
    SzArEx_Free(&db, &g_eh7z_alloc);
    if (passwordLength > 0) {
      throw_code(env, EHVIEWER_7Z_ERR_PASSWORD,
          "SzArEx simple API (24.09) has no password path; encrypted 7z needs the full 7zDec route");
    } else {
      snprintf(message, sizeof(message), "SzArEx_Open failed, SRes=%d", (int) res);
      throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, message);
    }
    return NULL;
  }

  for (fileIndex = 0; fileIndex < db.NumFiles; fileIndex++) {
    size_t nameLength = SzArEx_GetFileNameUtf16(&db, fileIndex, NULL);
    UInt16* name16 = NULL;
    char* nameUtf8 = NULL;
    char fullPath[4096];
    char parent[4096];
    size_t offset = 0;
    size_t outSizeProcessed = 0;
    size_t pathLength;
    bool done = false;

    if (nameLength == 0) {
      continue;
    }
    name16 = (UInt16*) malloc(nameLength * sizeof(UInt16));
    if (name16 == NULL) {
      throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "out of memory while reading file name");
      break;
    }
    SzArEx_GetFileNameUtf16(&db, fileIndex, name16);
    nameUtf8 = utf16_to_utf8(name16);
    free(name16);
    if (nameUtf8 == NULL) {
      throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "bad file name encoding in archive");
      break;
    }
    if (!is_safe_relative_path(nameUtf8)) {
      snprintf(message, sizeof(message), "unsafe archive path rejected: %s", nameUtf8);
      free(nameUtf8);
      throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, message);
      break;
    }
    if (outDirLength + 1 + strlen(nameUtf8) >= sizeof(fullPath)) {
      free(nameUtf8);
      throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "extracted entry path exceeds buffer limit");
      break;
    }
    snprintf(fullPath, sizeof(fullPath), "%s/%s", outDir, nameUtf8);
    pathLength = strlen(fullPath);

    if (SzArEx_IsDir(&db, fileIndex)) {
      if (!mkdirs(fullPath)) {
        snprintf(message, sizeof(message), "mkdir failed: %s", fullPath);
        free(nameUtf8);
        throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, message);
        break;
      }
      free(nameUtf8);
      continue;
    }

    /* 先建父目录 */
    memcpy(parent, fullPath, pathLength + 1);
    for (size_t i = pathLength; i > 0; i--) {
      if (parent[i] == '/') {
        parent[i] = '\0';
        mkdirs(parent);
        break;
      }
    }

    res = SzArEx_Extract(&db, &stream.vt, fileIndex, &blockIndex, &outBuffer, &outBufferSize,
        &offset, &outSizeProcessed, &g_eh7z_alloc, &g_eh7z_alloc);
    if (res == SZ_OK) {
      done = write_file(fullPath, outBuffer + offset, outSizeProcessed) == 0;
      if (!done) {
        snprintf(message, sizeof(message), "write failed: %s", fullPath);
      }
    } else {
      snprintf(message, sizeof(message), "SzArEx_Extract failed at %s, SRes=%d", nameUtf8, (int) res);
    }
    free(nameUtf8);

    if (!done) {
      throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, message);
      break;
    }
    extracted++;
  }

  if (outBuffer != NULL) {
    eh7z_free(&g_eh7z_alloc, outBuffer);
  }
  SzArEx_Free(&db, &g_eh7z_alloc);

  return ehviewer_napi_int32(env, extracted);
}

/* ---------------- 逐条目流式 7z 句柄表（供 A7ZipArchive / A7ZipBridge 使用） ---------------- */

#define EH7Z_IO_BUF_SIZE 65536u
#define EH7Z_MAX_HANDLES 32
#define EH7Z_AES_METHOD_ID 0x06F10701u

typedef struct {
  ISeekInStream vt;
  napi_env env;
  napi_ref readAtFnRef;
  napi_ref ioBufRef;
  void* ioBufData;
  size_t ioBufCap;
  int64_t pos;
  int64_t length;
} CallbackSeekInStream;

typedef struct {
  bool active;
  CallbackSeekInStream seekStream;
  CLookToRead2 lookStream;
  Byte* lookBuf;
  CSzArEx db;
  bool dbInited;
  UInt32 blockIndex;
  Byte* outBuffer;
  size_t outBufferSize;
} SzArchiveSlot;

static SzArchiveSlot g_archives[EH7Z_MAX_HANDLES];

static SRes cb_read(ISeekInStreamPtr pp, void* buf, size_t* size) {
  CallbackSeekInStream* s = (CallbackSeekInStream*) (void*) pp;
  size_t want;
  size_t avail;
  napi_value fn = NULL;
  napi_value ioBuf = NULL;
  napi_value global = NULL;
  napi_value args[3] = { NULL };
  napi_value ret = NULL;
  bool pending = false;
  int32_t got = 0;

  if (size == NULL) {
    return SZ_ERROR_PARAM;
  }
  want = *size;
  *size = 0;
  if (want == 0) {
    return SZ_OK;
  }
  if (s->env == NULL || buf == NULL) {
    return SZ_ERROR_READ;
  }
  if (s->pos >= s->length) {
    return SZ_OK;
  }
  avail = (size_t) (s->length - s->pos);
  if (want > avail) {
    want = avail;
  }
  if (want > s->ioBufCap) {
    want = s->ioBufCap;
  }
  if (napi_get_reference_value(s->env, s->readAtFnRef, &fn) != napi_ok ||
      napi_get_reference_value(s->env, s->ioBufRef, &ioBuf) != napi_ok ||
      napi_get_global(s->env, &global) != napi_ok) {
    return SZ_ERROR_READ;
  }
  napi_create_double(s->env, (double) s->pos, &args[0]);
  args[1] = ioBuf;
  napi_create_uint32(s->env, (uint32_t) want, &args[2]);
  if (napi_call_function(s->env, global, fn, 3, args, &ret) != napi_ok) {
    return SZ_ERROR_READ;
  }
  napi_is_exception_pending(s->env, &pending);
  if (pending) {
    return SZ_ERROR_READ;
  }
  if (napi_get_value_int32(s->env, ret, &got) != napi_ok || got < 0) {
    return SZ_ERROR_READ;
  }
  if (got == 0) {
    return SZ_OK;
  }
  if ((size_t) got > want) {
    got = (int32_t) want;
  }
  memcpy(buf, s->ioBufData, (size_t) got);
  s->pos += got;
  *size = (size_t) got;
  return SZ_OK;
}

static SRes cb_seek(ISeekInStreamPtr pp, Int64* pos, ESzSeek origin) {
  CallbackSeekInStream* s = (CallbackSeekInStream*) (void*) pp;
  Int64 base;
  Int64 next;

  switch (origin) {
    case SZ_SEEK_SET: base = 0; break;
    case SZ_SEEK_CUR: base = s->pos; break;
    case SZ_SEEK_END: base = s->length; break;
    default: return SZ_ERROR_PARAM;
  }
  next = base + *pos;
  if (next < 0 || next > s->length) {
    return SZ_ERROR_READ;
  }
  s->pos = next;
  *pos = next;
  return SZ_OK;
}

static void close_archive_slot(napi_env env, SzArchiveSlot* slot) {
  if (slot == NULL || !slot->active) {
    return;
  }
  if (slot->outBuffer != NULL) {
    eh7z_free(&g_eh7z_alloc, slot->outBuffer);
    slot->outBuffer = NULL;
  }
  slot->outBufferSize = 0;
  slot->blockIndex = 0xFFFFFFFFu;
  if (slot->dbInited) {
    SzArEx_Free(&slot->db, &g_eh7z_alloc);
    slot->dbInited = false;
  }
  free(slot->lookBuf);
  slot->lookBuf = NULL;
  if (env != NULL) {
    if (slot->seekStream.readAtFnRef != NULL) {
      napi_delete_reference(env, slot->seekStream.readAtFnRef);
    }
    if (slot->seekStream.ioBufRef != NULL) {
      napi_delete_reference(env, slot->seekStream.ioBufRef);
    }
  }
  memset(slot, 0, sizeof(*slot));
}

static SzArchiveSlot* get_archive_slot(napi_env env, napi_value handleVal) {
  int32_t handle = 0;
  if (napi_get_value_int32(env, handleVal, &handle) != napi_ok ||
      handle < 1 || handle > EH7Z_MAX_HANDLES) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "invalid 7z archive handle");
    return NULL;
  }
  SzArchiveSlot* slot = &g_archives[handle - 1];
  if (!slot->active || !slot->dbInited) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "7z archive handle is closed");
    return NULL;
  }
  return slot;
}

static bool folder_uses_aes(const CSzArEx* db, UInt32 folderIndex) {
  CSzFolder folder;
  CSzData sd;

  if (db == NULL || folderIndex >= db->db.NumFolders) {
    return false;
  }
  sd.Data = db->db.CodersData + db->db.FoCodersOffsets[folderIndex];
  sd.Size = db->db.FoCodersOffsets[folderIndex + 1] - db->db.FoCodersOffsets[folderIndex];
  if (SzGetNextFolderItem(&folder, &sd) != SZ_OK) {
    return false;
  }
  for (UInt32 c = 0; c < folder.NumCoders; c++) {
    if (folder.Coders[c].MethodID == EH7Z_AES_METHOD_ID) {
      return true;
    }
  }
  return false;
}

static napi_value Open7z(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  double totalLength = 0;
  napi_valuetype fnType = napi_undefined;
  int slotIndex = -1;
  napi_value ioBufVal = NULL;
  SzArchiveSlot* slot = NULL;
  SRes res;
  bool pending = false;

  ensure_crc_table();

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "open7z(length, readAt)");
    return NULL;
  }
  if (napi_get_value_double(env, argv[0], &totalLength) != napi_ok || totalLength <= 0) {
    return ehviewer_napi_int32(env, 0);
  }
  if (napi_typeof(env, argv[1], &fnType) != napi_ok || fnType != napi_function) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "open7z readAt must be a function");
    return NULL;
  }

  for (int i = 0; i < EH7Z_MAX_HANDLES; i++) {
    if (!g_archives[i].active) {
      slotIndex = i;
      break;
    }
  }
  if (slotIndex < 0) {
    throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "too many open 7z archives");
    return NULL;
  }

  slot = &g_archives[slotIndex];
  memset(slot, 0, sizeof(*slot));
  slot->active = true;
  slot->blockIndex = 0xFFFFFFFFu;
  slot->lookBuf = (Byte*) malloc(EH7Z_IO_BUF_SIZE);
  if (slot->lookBuf == NULL) {
    memset(slot, 0, sizeof(*slot));
    throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "out of memory allocating 7z buffer");
    return NULL;
  }
  if (napi_create_arraybuffer(env, EH7Z_IO_BUF_SIZE, &slot->seekStream.ioBufData, &ioBufVal) != napi_ok ||
      slot->seekStream.ioBufData == NULL) {
    close_archive_slot(env, slot);
    throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "out of memory creating 7z io buffer");
    return NULL;
  }
  slot->seekStream.ioBufCap = EH7Z_IO_BUF_SIZE;
  napi_create_reference(env, argv[1], 1, &slot->seekStream.readAtFnRef);
  napi_create_reference(env, ioBufVal, 1, &slot->seekStream.ioBufRef);
  slot->seekStream.vt.Read = cb_read;
  slot->seekStream.vt.Seek = cb_seek;
  slot->seekStream.pos = 0;
  slot->seekStream.length = (int64_t) totalLength;
  slot->seekStream.env = env;

  LookToRead2_CreateVTable(&slot->lookStream, False);
  slot->lookStream.buf = slot->lookBuf;
  slot->lookStream.bufSize = EH7Z_IO_BUF_SIZE;
  slot->lookStream.realStream = &slot->seekStream.vt;
  LookToRead2_INIT(&slot->lookStream);

  SzArEx_Init(&slot->db);
  slot->dbInited = true;

  res = SzArEx_Open(&slot->db, &slot->lookStream.vt, &g_eh7z_alloc, &g_eh7z_alloc);
  slot->seekStream.env = NULL;

  napi_is_exception_pending(env, &pending);
  if (pending) {
    napi_value ignored = NULL;
    napi_get_and_clear_last_exception(env, &ignored);
  }
  if (res != SZ_OK) {
    close_archive_slot(env, slot);
    return ehviewer_napi_int32(env, 0);
  }
  return ehviewer_napi_int32(env, slotIndex + 1);
}

static napi_value Close7z(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  int32_t handle = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) == napi_ok && argc >= 1 &&
      napi_get_value_int32(env, argv[0], &handle) == napi_ok &&
      handle >= 1 && handle <= EH7Z_MAX_HANDLES) {
    close_archive_slot(env, &g_archives[handle - 1]);
  }
  return NULL;
}

static napi_value Get7zEntryCount(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  SzArchiveSlot* slot = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "get7zEntryCount(handle)");
    return NULL;
  }
  slot = get_archive_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  return ehviewer_napi_int32(env, (int32_t) slot->db.NumFiles);
}

static napi_value Get7zEntryName(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  SzArchiveSlot* slot = NULL;
  int32_t index = 0;
  size_t nameLength = 0;
  UInt16* name16 = NULL;
  char* nameUtf8 = NULL;
  napi_value ret = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "get7zEntryName(handle, index)");
    return NULL;
  }
  slot = get_archive_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (UInt32) index >= slot->db.NumFiles) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "7z entry index out of range");
    return NULL;
  }
  nameLength = SzArEx_GetFileNameUtf16(&slot->db, (size_t) index, NULL);
  if (nameLength == 0) {
    napi_create_string_utf8(env, "", 0, &ret);
    return ret;
  }
  name16 = (UInt16*) malloc(nameLength * sizeof(UInt16));
  if (name16 == NULL) {
    throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "out of memory reading 7z entry name");
    return NULL;
  }
  SzArEx_GetFileNameUtf16(&slot->db, (size_t) index, name16);
  nameUtf8 = utf16_to_utf8(name16);
  free(name16);
  if (nameUtf8 == NULL) {
    throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "invalid utf-16 entry name in 7z");
    return NULL;
  }
  napi_create_string_utf8(env, nameUtf8, NAPI_AUTO_LENGTH, &ret);
  free(nameUtf8);
  return ret;
}

static napi_value Is7zEntryDir(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  SzArchiveSlot* slot = NULL;
  int32_t index = 0;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "is7zEntryDir(handle, index)");
    return NULL;
  }
  slot = get_archive_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (UInt32) index >= slot->db.NumFiles) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "7z entry index out of range");
    return NULL;
  }
  return ehviewer_napi_bool(env, SzArEx_IsDir(&slot->db, (UInt32) index) != 0);
}

static napi_value Is7zEncrypted(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  SzArchiveSlot* slot = NULL;
  bool encrypted = false;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 1) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "is7zEncrypted(handle)");
    return NULL;
  }
  slot = get_archive_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  for (UInt32 fi = 0; fi < slot->db.db.NumFolders; fi++) {
    if (folder_uses_aes(&slot->db, fi)) {
      encrypted = true;
      break;
    }
  }
  return ehviewer_napi_bool(env, encrypted);
}

static napi_value Is7zEntryEncrypted(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  SzArchiveSlot* slot = NULL;
  int32_t index = 0;
  UInt32 folderIndex;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "is7zEntryEncrypted(handle, index)");
    return NULL;
  }
  slot = get_archive_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (UInt32) index >= slot->db.NumFiles) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "7z entry index out of range");
    return NULL;
  }
  folderIndex = slot->db.FileToFolder[index];
  return ehviewer_napi_bool(env, folderIndex != (UInt32) -1 && folder_uses_aes(&slot->db, folderIndex));
}

static napi_value Extract7zEntry(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = { NULL };
  SzArchiveSlot* slot = NULL;
  int32_t index = 0;
  size_t offset = 0;
  size_t outSizeProcessed = 0;
  SRes res;
  bool pending = false;
  void* dstData = NULL;
  napi_value outAb = NULL;

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "extract7zEntry(handle, index)");
    return NULL;
  }
  slot = get_archive_slot(env, argv[0]);
  if (slot == NULL) {
    return NULL;
  }
  if (napi_get_value_int32(env, argv[1], &index) != napi_ok ||
      index < 0 || (UInt32) index >= slot->db.NumFiles) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "7z entry index out of range");
    return NULL;
  }

  slot->seekStream.env = env;
  res = SzArEx_Extract(&slot->db, &slot->lookStream.vt, (UInt32) index,
      &slot->blockIndex, &slot->outBuffer, &slot->outBufferSize,
      &offset, &outSizeProcessed, &g_eh7z_alloc, &g_eh7z_alloc);
  slot->seekStream.env = NULL;

  napi_is_exception_pending(env, &pending);
  if (pending) {
    return NULL;
  }
  if (res != SZ_OK) {
    char message[256];
    snprintf(message, sizeof(message), "SzArEx_Extract failed at entry %d, SRes=%d", index, (int) res);
    throw_code(env, res == SZ_ERROR_UNSUPPORTED ? EHVIEWER_7Z_ERR_PASSWORD : EHVIEWER_7Z_ERR_EXTRACT,
        message);
    return NULL;
  }
  if (napi_create_arraybuffer(env, outSizeProcessed, &dstData, &outAb) != napi_ok) {
    throw_code(env, EHVIEWER_7Z_ERR_EXTRACT, "failed to allocate output ArrayBuffer");
    return NULL;
  }
  if (outSizeProcessed > 0 && dstData != NULL && slot->outBuffer != NULL) {
    memcpy(dstData, slot->outBuffer + offset, outSizeProcessed);
  }
  return outAb;
}

#else /* EHVIEWER_7Z == 0 */

static napi_value Extract7z(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = { NULL };

  if (napi_get_cb_info(env, info, &argc, argv, NULL, NULL) != napi_ok || argc < 2) {
    throw_code(env, EHVIEWER_7Z_ERR_BAD_ARG, "extract7z(archive, outDir, password?)");
    return NULL;
  }
  throw_code(env, EHVIEWER_7Z_ERR_NOT_BUILT,
      "7z support is not compiled into libnative-lib.so (EHVIEWER_7Z=0)");
  return NULL;
}

static napi_value Stub7zNotBuilt(napi_env env, napi_callback_info info) {
  (void) info;
  throw_code(env, EHVIEWER_7Z_ERR_NOT_BUILT,
      "7z support is not compiled into libnative-lib.so (EHVIEWER_7Z=0)");
  return NULL;
}

#define Open7z Stub7zNotBuilt
#define Close7z Stub7zNotBuilt
#define Get7zEntryCount Stub7zNotBuilt
#define Get7zEntryName Stub7zNotBuilt
#define Is7zEntryDir Stub7zNotBuilt
#define Is7zEncrypted Stub7zNotBuilt
#define Is7zEntryEncrypted Stub7zNotBuilt
#define Extract7zEntry Stub7zNotBuilt

#endif /* EHVIEWER_7Z */

napi_value napi_7z_init(napi_env env, napi_value exports) {
  napi_property_descriptor functions[] = {
      { "extract7z", NULL, Extract7z, NULL, NULL, NULL, napi_default, NULL },
      { "open7z", NULL, Open7z, NULL, NULL, NULL, napi_default, NULL },
      { "close7z", NULL, Close7z, NULL, NULL, NULL, napi_default, NULL },
      { "get7zEntryCount", NULL, Get7zEntryCount, NULL, NULL, NULL, napi_default, NULL },
      { "get7zEntryName", NULL, Get7zEntryName, NULL, NULL, NULL, napi_default, NULL },
      { "is7zEntryDir", NULL, Is7zEntryDir, NULL, NULL, NULL, napi_default, NULL },
      { "is7zEncrypted", NULL, Is7zEncrypted, NULL, NULL, NULL, napi_default, NULL },
      { "is7zEntryEncrypted", NULL, Is7zEntryEncrypted, NULL, NULL, NULL, napi_default, NULL },
      { "extract7zEntry", NULL, Extract7zEntry, NULL, NULL, NULL, napi_default, NULL },
  };

  napi_define_properties(env, exports, sizeof(functions) / sizeof(functions[0]), functions);

  return exports;
}
