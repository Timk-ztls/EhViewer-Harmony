/*
 * 纹理区域 blit 的**纯整数裁剪**（无 GL / 无 EGL / 无 NAPI 依赖，可独立编译测试）。
 *
 * 为什么单独抽出来：这是 `nativeTexImageRegion` 唯一容易写错的部分（负偏移 + 越界 +
 * src/dst 同步平移），抽成纯函数后可以用 host 编译器 + 断言直接验证，不需要设备与 GL 上下文。
 *
 * 语义（与 gl-render 对齐，等价上游 nativeTexImage 的"区域渲染到任意偏移"）：
 *   输入：源区域 (srcX, srcY, srcW, srcH)、目标偏移 (dstX, dstY)、纹理尺寸 (texW, texH)
 *   输出：实际可写入的交集区域（dstPixX/Y 与 srcPixX/Y 及 w/h）；若无交集返回 false
 *
 * 规则：
 *   1. dst 允许为负：负的部分裁掉，同时 src 相应**正向平移**（-dstX / -dstY）
 *   2. dst 超出纹理右侧/下方：超出的部分裁掉（src 端不变，只减 w/h）
 *   3. src 允许超出 pixelMap：由调用方按 pixelMap 实际尺寸再裁一次（本函数只管纹理边界）
 *   4. src 与 dst **1:1 不缩放**：裁剪量同时作用于两边，w/h 保持一致
 */
#ifndef EHVIEWER_GL_REGION_H
#define EHVIEWER_GL_REGION_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
  int32_t srcPixX;  /* 源起点（已按 dst 负偏移平移） */
  int32_t srcPixY;
  int32_t dstPixX;  /* 纹理写入起点（一定 >= 0） */
  int32_t dstPixY;
  int32_t width;    /* 实际写入宽（> 0） */
  int32_t height;   /* 实际写入高（> 0） */
} GlRegionClip;

/*
 * 计算裁剪后的写入区域。
 * 返回 false 表示：参数非法（texW/texH <= 0、srcW/srcH <= 0）或**完全在纹理外**（无需写入）。
 * 返回 true 时 out 的四个偏移均为非负，且 width/height > 0。
 */
static inline bool gl_region_clip(int32_t srcX, int32_t srcY, int32_t srcW, int32_t srcH,
                                  int32_t dstX, int32_t dstY,
                                  int32_t texW, int32_t texH, GlRegionClip* out) {
  int32_t left;
  int32_t top;
  int32_t right;
  int32_t bottom;

  if (out == NULL || texW <= 0 || texH <= 0 || srcW <= 0 || srcH <= 0) {
    return false;
  }

  /* dst 负偏移：裁掉左侧/上方，src 同步正向平移 */
  left = dstX < 0 ? -dstX : 0;
  top = dstY < 0 ? -dstY : 0;
  /* dst 超出纹理右/下：裁掉超出的部分 */
  right = srcW;
  if (dstX + srcW > texW) {
    right = texW - dstX;
  }
  bottom = srcH;
  if (dstY + srcH > texH) {
    bottom = texH - dstY;
  }

  /* 无交集（完全在纹理外，或源区域本身为负尺寸） */
  if (right <= left || bottom <= top) {
    return false;
  }

  out->srcPixX = srcX + left;
  out->srcPixY = srcY + top;
  out->dstPixX = dstX + left;
  out->dstPixY = dstY + top;
  out->width = right - left;
  out->height = bottom - top;
  return true;
}

/*
 * 按目标纹理边界与源图像尺寸联合裁剪。
 *
 * 相比 gl_region_clip 增加对源偏移为负（tile 左/上边框，如 srcX = -1）及源右下越界的同步裁剪：
 *   - dstX/dstY < 0：目标端从 0 起写，srcPixX/Y 同步右/下移
 *   - srcPixX/Y < 0（扣除 dst 负偏移后仍落在源图左/上之外）：源从 0 起读，dstPixX/Y 同步右/下移
 *   - src 超过 srcBoundW/H 或 dst 超过 texW/texH：两边同时收窄宽高
 * 返回 true 时 srcPixX/Y >= 0、dstPixX/Y >= 0、width/height > 0 且均不越界。
 */
static inline bool gl_region_clip_with_source(int32_t srcX, int32_t srcY,
                                              int32_t srcW, int32_t srcH,
                                              int32_t dstX, int32_t dstY,
                                              int32_t texW, int32_t texH,
                                              int32_t srcBoundW, int32_t srcBoundH,
                                              GlRegionClip* out) {
  int32_t shiftX;
  int32_t shiftY;

  if (srcBoundW <= 0 || srcBoundH <= 0) {
    return false;
  }
  if (!gl_region_clip(srcX, srcY, srcW, srcH, dstX, dstY, texW, texH, out)) {
    return false;
  }

  /* 源左/上越界：源钳到 0，同时目标起点与宽度按 1:1 同步收缩/右移 */
  if (out->srcPixX < 0) {
    shiftX = -out->srcPixX;
    out->srcPixX = 0;
    out->dstPixX += shiftX;
    out->width -= shiftX;
  }
  if (out->srcPixY < 0) {
    shiftY = -out->srcPixY;
    out->srcPixY = 0;
    out->dstPixY += shiftY;
    out->height -= shiftY;
  }

  /* 源右/下越界（此时 dst 已不越界；进一步收窄不会突破 texW/texH） */
  if (out->width > 0 && out->srcPixX + out->width > srcBoundW) {
    out->width = srcBoundW - out->srcPixX;
  }
  if (out->height > 0 && out->srcPixY + out->height > srcBoundH) {
    out->height = srcBoundH - out->srcPixY;
  }

  return out->width > 0 && out->height > 0 &&
      out->dstPixX < texW && out->dstPixY < texH;
}

#endif /* EHVIEWER_GL_REGION_H */
