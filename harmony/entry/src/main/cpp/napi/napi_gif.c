/*
 * NAPI 胶水层：GifDecoder（鸿蒙侧新增，见 inventory/native-image.extra.txt）。
 *
 * 对应上游 cpp/gif/native-lib.cpp 的 1:1 移植：
 *   GifHandler.loadPath(path)          → decoder.load(buffer) / decoder.loadFd(fd)
 *   GifHandler.getWidth()              → decoder.width
 *   GifHandler.getHeight()             → decoder.height
 *   GifHandler.updateFrame(bitmap)     → decoder.updateFrame() → 返回下一帧延迟，
 *                                        像素写入 decoder.pixels（RGBA_8888）
 *
 * 与上游的唯一差异：上游把帧画进 Java Bitmap（AndroidBitmap_lockPixels），
 * 鸿蒙侧画进自身 malloc 的 RGBA 缓冲，通过 decoder.pixels 以零拷贝 ArrayBuffer 暴露。
 * drawFrame 的绘制/dispose 逻辑逐行保留（含 dispose=1/2/3 与 interlace 分支）。
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#include "napi_common.h"

#include "gif_lib.h"
#include "../jni/log.h"

#define GIF_ARGBA(a, r, g, b) ((((a) & 0xff) << 24) | (((b) & 0xff) << 16) | (((g) & 0xff) << 8) | ((r) & 0xff))
#define GIF_DISPOSE(ext) (((ext)->Bytes[0] & 0x1c) >> 2)
#define GIF_TRANS_INDEX(ext) ((ext)->Bytes[3])
#define GIF_TRANSPARENCY(ext) ((ext)->Bytes[0] & 1)
#define GIF_DELAY(ext) (10 * ((ext)->Bytes[2] << 8 | (ext)->Bytes[1]))

typedef struct {
  const unsigned char* data;
  size_t size;
  size_t position;
  int fd;
} GifSource;

typedef struct {
  GifFileType* gif;
  GifSource source;
  int* delays;
  int totalFrame;
  int currentFrame;
  int width;
  int height;
  int lastDelay;
  unsigned char* pixels;
  size_t pixelsSize;
} GifDecoder;

static int gif_source_read(GifFileType* gif, GifByteType* bytes, int size) {
  GifSource* source = (GifSource*) gif->UserData;
  size_t read;

  if (source == NULL || bytes == NULL || size <= 0) {
    return 0;
  }

  if (source->fd >= 0) {
    ssize_t len = pread(source->fd, bytes, (size_t) size, (off_t) source->position);
    if (len <= 0) {
      return 0;
    }
    source->position += (size_t) len;
    return (int) len;
  }

  if (source->position >= source->size) {
    return 0;
  }
  read = source->size - source->position;
  if (read > (size_t) size) {
    read = (size_t) size;
  }
  memcpy(bytes, source->data + source->position, read);
  source->position += read;

  return (int) read;
}

/* 逐行保留上游 drawFrame 的绘制逻辑 */
static int drawFrame(GifDecoder* decoder, bool forceDispose1) {
  GifFileType* gif = decoder->gif;
  GifColorType* bg = NULL;
  GifColorType* color = NULL;
  SavedImage* frame = NULL;
  ExtensionBlock* ext = NULL;
  GifImageDesc* frameInfo = NULL;
  ColorMapObject* colorMap = NULL;
  int* line = NULL;
  int width = gif->SWidth;
  int height = gif->SHeight;
  int stride = decoder->width * 4;
  int x, y, j, loc, n, inc, p;
  void* px = decoder->pixels;

  if (decoder->currentFrame < 0 || decoder->currentFrame >= gif->ImageCount) {
    return 0;
  }

  frame = &(gif->SavedImages[decoder->currentFrame]);
  frameInfo = &(frame->ImageDesc);

  colorMap = frameInfo->ColorMap != NULL ? frameInfo->ColorMap : gif->SColorMap;
  if (colorMap == NULL || decoder->pixels == NULL || width <= 0 || height <= 0) {
    LOGE(MSG("GIF frame has no color map or invalid canvas"));
    return 0;
  }
  if (frame->RasterBits == NULL || frameInfo->Width <= 0 || frameInfo->Height <= 0) {
    return 0;
  }

  if (gif->SBackGroundColor >= 0 && gif->SBackGroundColor < colorMap->ColorCount) {
    bg = &colorMap->Colors[gif->SBackGroundColor];
  }

  for (j = 0; j < frame->ExtensionBlockCount; j++) {
    if (frame->ExtensionBlocks[j].Function == GRAPHICS_EXT_FUNC_CODE &&
        frame->ExtensionBlocks[j].ByteCount >= 4) {
      ext = &(frame->ExtensionBlocks[j]);
      break;
    }
  }

  /* For dispose = 1, we assume its been drawn */
  px = decoder->pixels;
  if (ext != NULL && GIF_DISPOSE(ext) == 1 && forceDispose1 && decoder->currentFrame > 0) {
    int savedFrame = decoder->currentFrame;
    decoder->currentFrame = savedFrame - 1;
    drawFrame(decoder, true);
    decoder->currentFrame = savedFrame;
  } else if (ext != NULL && GIF_DISPOSE(ext) == 2 && bg != NULL) {
    for (y = 0; y < height; y++) {
      line = (int*) px;
      for (x = 0; x < width; x++) {
        line[x] = GIF_ARGBA(255, bg->Red, bg->Green, bg->Blue);
      }
      px = (int*) ((char*) px + stride);
    }
  } else if (ext != NULL && GIF_DISPOSE(ext) == 3 && decoder->currentFrame > 1) {
    int savedFrame = decoder->currentFrame;
    decoder->currentFrame = savedFrame - 2;
    drawFrame(decoder, true);
    decoder->currentFrame = savedFrame;
  }

  px = decoder->pixels;
  if (frameInfo->Interlace) {
    n = 0;
    inc = 8;
    p = 0;

    for (y = frameInfo->Top; y < frameInfo->Top + frameInfo->Height; y++) {
      if (y >= 0 && y < height) {
        line = (int*) ((char*) decoder->pixels + (size_t) stride * (size_t) y);
        for (x = frameInfo->Left; x < frameInfo->Left + frameInfo->Width; x++) {
          if (x < 0 || x >= width) {
            continue;
          }
          loc = (y - frameInfo->Top) * frameInfo->Width + (x - frameInfo->Left);
          GifByteType idx = frame->RasterBits[loc];
          if (ext != NULL && idx == GIF_TRANS_INDEX(ext) && GIF_TRANSPARENCY(ext)) {
            continue;
          }
          color = (ext != NULL && idx == GIF_TRANS_INDEX(ext))
              ? bg : (idx < colorMap->ColorCount ? &colorMap->Colors[idx] : NULL);
          if (color != NULL) {
            line[x] = GIF_ARGBA(255, color->Red, color->Green, color->Blue);
          }
        }
      }
      n += inc;
      if (n >= frameInfo->Height) {
        n = 0;
        switch (p) {
          case 0:
            inc = 8;
            p++;
            break;
          case 1:
            inc = 4;
            p++;
            break;
          case 2:
            inc = 2;
            p++;
            break;
          default:
            break;
        }
      }
    }
  } else {
    int yStart = frameInfo->Top < 0 ? 0 : frameInfo->Top;
    int yEnd = frameInfo->Top + frameInfo->Height;
    if (yEnd > height) {
      yEnd = height;
    }
    int xStart = frameInfo->Left < 0 ? 0 : frameInfo->Left;
    int xEnd = frameInfo->Left + frameInfo->Width;
    if (xEnd > width) {
      xEnd = width;
    }
    for (y = yStart; y < yEnd; y++) {
      line = (int*) ((char*) px + (size_t) stride * (size_t) y);
      for (x = xStart; x < xEnd; x++) {
        loc = (y - frameInfo->Top) * frameInfo->Width + (x - frameInfo->Left);
        GifByteType idx = frame->RasterBits[loc];
        if (ext != NULL && idx == GIF_TRANS_INDEX(ext) && GIF_TRANSPARENCY(ext)) {
          continue;
        }
        color = (ext != NULL && idx == GIF_TRANS_INDEX(ext))
            ? bg : (idx < colorMap->ColorCount ? &colorMap->Colors[idx] : NULL);
        if (color != NULL) {
          line[x] = GIF_ARGBA(255, color->Red, color->Green, color->Blue);
        }
      }
    }
  }

  return ext == NULL ? 0 : GIF_DELAY(ext);
}

static void gif_decoder_release(GifDecoder* decoder) {
  if (decoder == NULL) {
    return;
  }
  if (decoder->gif != NULL) {
    int error = 0;
    DGifCloseFile(decoder->gif, &error);
    decoder->gif = NULL;
  }
  if (decoder->source.fd >= 0) {
    close(decoder->source.fd);
    decoder->source.fd = -1;
  }
  free(decoder->delays);
  decoder->delays = NULL;
  free(decoder->pixels);
  decoder->pixels = NULL;
  decoder->pixelsSize = 0;
  decoder->totalFrame = 0;
  decoder->currentFrame = 0;
}

static void gif_decoder_finalize(napi_env env, void* data, void* hint) {
  GifDecoder* decoder = (GifDecoder*) data;
  (void) env;
  (void) hint;
  if (decoder == NULL) {
    return;
  }
  gif_decoder_release(decoder);
  free(decoder);
}

static bool gif_decoder_open(napi_env env, GifDecoder* decoder, GifSource source) {
  int error = 0;
  ExtensionBlock* ext = NULL;

  decoder->source = source;
  decoder->gif = DGifOpen(&decoder->source, gif_source_read, &error);
  if (decoder->gif == NULL) {
    napi_throw_error(env, NULL, "DGifOpen failed");
    if (decoder->source.fd >= 0) {
      close(decoder->source.fd);
      decoder->source.fd = -1;
    }
    return false;
  }
  if (DGifSlurp(decoder->gif) != GIF_OK) {
    napi_throw_error(env, NULL, "DGifSlurp failed");
    gif_decoder_release(decoder);
    return false;
  }

  decoder->totalFrame = decoder->gif->ImageCount;
  decoder->currentFrame = 0;
  decoder->width = decoder->gif->SWidth;
  decoder->height = decoder->gif->SHeight;
  if (decoder->totalFrame <= 0 || decoder->width <= 0 || decoder->height <= 0 ||
      (size_t) decoder->width > SIZE_MAX / 4u / (size_t) decoder->height) {
    napi_throw_error(env, NULL, "invalid GIF metadata");
    gif_decoder_release(decoder);
    return false;
  }
  decoder->delays = (int*) malloc(sizeof(int) * (size_t) decoder->totalFrame);
  if (decoder->delays == NULL) {
    napi_throw_error(env, NULL, "out of memory");
    gif_decoder_release(decoder);
    return false;
  }
  memset(decoder->delays, 0, sizeof(int) * (size_t) decoder->totalFrame);

  for (int i = 0; i < decoder->totalFrame; ++i) {
    SavedImage frame = decoder->gif->SavedImages[i];
    ext = NULL;
    for (int j = 0; j < frame.ExtensionBlockCount; ++j) {
      if (frame.ExtensionBlocks[j].Function == GRAPHICS_EXT_FUNC_CODE &&
          frame.ExtensionBlocks[j].ByteCount >= 3) {
        ext = &frame.ExtensionBlocks[j];
        break;
      }
    }
    if (ext != NULL) {
      decoder->delays[i] = 10 * (ext->Bytes[2] << 8 | ext->Bytes[1]);
    }
  }

  decoder->pixelsSize = (size_t) decoder->width * (size_t) decoder->height * 4;
  decoder->pixels = (unsigned char*) malloc(decoder->pixelsSize);
  if (decoder->pixels == NULL) {
    napi_throw_error(env, NULL, "out of memory");
    gif_decoder_release(decoder);
    return false;
  }
  memset(decoder->pixels, 0, decoder->pixelsSize);

  return true;
}

static bool unwrap_gif(napi_env env, napi_callback_info info, GifDecoder** out,
                       size_t* argc, napi_value* argv) {
  napi_value thisValue = NULL;
  if (napi_get_cb_info(env, info, argc, argv, &thisValue, NULL) != napi_ok) {
    napi_throw_error(env, NULL, "can not get callback info");
    return false;
  }
  if (napi_unwrap(env, thisValue, (void**) out) != napi_ok || *out == NULL) {
    napi_throw_error(env, NULL, "invalid GifDecoder handle");
    return false;
  }
  return true;
}

static napi_value GifConstructor(napi_env env, napi_callback_info info) {
  napi_value thisValue = NULL;
  GifDecoder* decoder = NULL;

  (void) info;

  if (napi_get_cb_info(env, info, NULL, NULL, &thisValue, NULL) != napi_ok) {
    return NULL;
  }
  decoder = (GifDecoder*) malloc(sizeof(GifDecoder));
  if (decoder == NULL) {
    napi_throw_error(env, NULL, "out of memory");
    return NULL;
  }
  memset(decoder, 0, sizeof(GifDecoder));
  decoder->source.fd = -1;

  if (napi_wrap(env, thisValue, decoder, gif_decoder_finalize, NULL, NULL) != napi_ok) {
    free(decoder);
    napi_throw_error(env, NULL, "can not wrap GifDecoder");
    return NULL;
  }
  return thisValue;
}

static napi_value GifLoad(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  GifDecoder* decoder = NULL;
  GifSource source;
  void* data = NULL;
  size_t length = 0;

  if (!unwrap_gif(env, info, &decoder, &argc, argv)) {
    return NULL;
  }
  if (argc < 1 || !ehviewer_napi_get_bytes(env, argv[0], &data, &length)) {
    napi_throw_error(env, NULL, "load(buffer) needs an ArrayBuffer");
    return NULL;
  }
  if (decoder->gif != NULL) {
    gif_decoder_release(decoder);
  }

  memset(&source, 0, sizeof(source));
  source.data = (const unsigned char*) data;
  source.size = length;
  source.fd = -1;

  if (!gif_decoder_open(env, decoder, source)) {
    return NULL;
  }
  return ehviewer_napi_bool(env, true);
}

static napi_value GifLoadFd(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  GifDecoder* decoder = NULL;
  GifSource source;
  int32_t fd = -1;
  int dupFd;

  if (!unwrap_gif(env, info, &decoder, &argc, argv)) {
    return NULL;
  }
  if (argc < 1) {
    napi_throw_error(env, NULL, "loadFd(fd) needs a file descriptor");
    return NULL;
  }
  napi_get_value_int32(env, argv[0], &fd);
  if (fd < 0) {
    napi_throw_error(env, NULL, "invalid file descriptor");
    return NULL;
  }
  if (decoder->gif != NULL) {
    gif_decoder_release(decoder);
  }

  dupFd = dup(fd);
  if (dupFd < 0) {
    napi_throw_error(env, NULL, "can not dup file descriptor");
    return NULL;
  }

  memset(&source, 0, sizeof(source));
  source.fd = dupFd;
  if (!gif_decoder_open(env, decoder, source)) {
    return NULL;
  }
  return ehviewer_napi_bool(env, true);
}

static napi_value GifUpdateFrame(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  GifDecoder* decoder = NULL;

  if (!unwrap_gif(env, info, &decoder, &argc, NULL)) {
    return NULL;
  }
  if (decoder->gif == NULL) {
    napi_throw_error(env, NULL, "GifDecoder is not loaded");
    return NULL;
  }

  decoder->lastDelay = drawFrame(decoder, false);

  if (decoder->totalFrame <= 0) {
    return ehviewer_napi_int32(env, 0);
  }
  decoder->currentFrame += 1;
  if (decoder->currentFrame >= decoder->totalFrame) {
    decoder->currentFrame = 0;
  }

  return ehviewer_napi_int32(env, decoder->delays == NULL ? 0 : decoder->delays[decoder->currentFrame]);
}

static napi_value GifPixels(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  GifDecoder* decoder = NULL;

  if (!unwrap_gif(env, info, &decoder, &argc, NULL)) {
    return NULL;
  }
  if (decoder->pixels == NULL || decoder->pixelsSize == 0) {
    napi_throw_error(env, NULL, "GifDecoder is not loaded");
    return NULL;
  }
  return ehviewer_napi_external_buffer(env, decoder->pixels, decoder->pixelsSize);
}

static napi_value GifSeek(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value argv[1] = { NULL };
  GifDecoder* decoder = NULL;
  int32_t index = 0;

  if (!unwrap_gif(env, info, &decoder, &argc, argv)) {
    return NULL;
  }
  if (decoder->gif == NULL) {
    napi_throw_error(env, NULL, "GifDecoder is not loaded");
    return NULL;
  }
  napi_get_value_int32(env, argv[0], &index);
  if (index < 0 || index >= decoder->totalFrame) {
    napi_throw_error(env, NULL, "frame index out of range");
    return NULL;
  }
  decoder->currentFrame = index;
  decoder->lastDelay = drawFrame(decoder, false);
  return ehviewer_napi_int32(env, decoder->lastDelay);
}

static napi_value GifRecycle(napi_env env, napi_callback_info info) {
  size_t argc = 0;
  GifDecoder* decoder = NULL;

  if (!unwrap_gif(env, info, &decoder, &argc, NULL)) {
    return NULL;
  }
  gif_decoder_release(decoder);
  return NULL;
}

#define GIF_GETTER(name, expr)                                            \
  static napi_value name(napi_env env, napi_callback_info info) {         \
    size_t argc = 0;                                                      \
    GifDecoder* decoder = NULL;                                           \
    if (!unwrap_gif(env, info, &decoder, &argc, NULL)) {                   \
      return NULL;                                                        \
    }                                                                     \
    return ehviewer_napi_int32(env, (int32_t) (expr));                     \
  }

GIF_GETTER(GifGetWidth, decoder->width)
GIF_GETTER(GifGetHeight, decoder->height)
GIF_GETTER(GifGetFrameCount, decoder->totalFrame)
GIF_GETTER(GifGetCurrentFrame, decoder->currentFrame)
GIF_GETTER(GifGetDelay, decoder->lastDelay)

napi_value napi_gif_init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      { "load", NULL, GifLoad, NULL, NULL, NULL, napi_default_method, NULL },
      { "loadFd", NULL, GifLoadFd, NULL, NULL, NULL, napi_default_method, NULL },
      { "updateFrame", NULL, GifUpdateFrame, NULL, NULL, NULL, napi_default_method, NULL },
      { "seek", NULL, GifSeek, NULL, NULL, NULL, napi_default_method, NULL },
      { "recycle", NULL, GifRecycle, NULL, NULL, NULL, napi_default_method, NULL },
      { "pixels", NULL, NULL, GifPixels, NULL, NULL, napi_default, NULL },
      { "width", NULL, NULL, GifGetWidth, NULL, NULL, napi_default, NULL },
      { "height", NULL, NULL, GifGetHeight, NULL, NULL, napi_default, NULL },
      { "frameCount", NULL, NULL, GifGetFrameCount, NULL, NULL, napi_default, NULL },
      { "currentFrame", NULL, NULL, GifGetCurrentFrame, NULL, NULL, napi_default, NULL },
      { "delay", NULL, NULL, GifGetDelay, NULL, NULL, napi_default, NULL },
  };
  napi_value constructor = NULL;

  napi_define_class(env, "GifDecoder", NAPI_AUTO_LENGTH, GifConstructor, NULL,
      sizeof(properties) / sizeof(properties[0]), properties, &constructor);
  napi_set_named_property(env, exports, "GifDecoder", constructor);

  return exports;
}
