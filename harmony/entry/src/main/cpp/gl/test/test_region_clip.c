/*
 * gl_region_clip 的 host 侧断言程序（无 GL / 无 EGL / 无 NAPI 依赖）。
 *
 * 构建（OH NDK clang，仅编译不运行）：
 *   clang --target=aarch64-linux-ohos --sysroot=<ndk>/sysroot -O1 -o test_region_clip.exe \
 *         harmony/entry/src/main/cpp/gl/test/test_region_clip.c
 * 运行需要 aarch64 设备/模拟器；桌面端可用任意 host C 编译器（gcc/clang）直接编译运行，
 * 因为它只依赖 <stdio.h> 与 gl_region.h。
 *
 * 覆盖 Lead 要求的四类用例：
 *   1. dstX/dstY 为负（首行首列 tile）
 *   2. srcW/srcH 超出纹理边界
 *   3. 完全在纹理外（返回 false，不写）
 *   4. 纹理尺寸/源尺寸非法
 * 外加：1:1 不缩放（裁剪量同时作用于 src 与 dst）、以及 gl-render 的真实 tile 场景（-1/-2 边框）。
 */
#include <stdio.h>

#include "../gl_region.h"

static int g_failures = 0;

static void expect_true(const char* name, bool value) {
  if (!value) {
    printf("FAIL %s: expected true\n", name);
    g_failures++;
  }
}

static void expect_false(const char* name, bool value) {
  if (value) {
    printf("FAIL %s: expected false\n", name);
    g_failures++;
  }
}

static void expect_int(const char* name, int32_t actual, int32_t expected) {
  if (actual != expected) {
    printf("FAIL %s: actual=%d expected=%d\n", name, (int) actual, (int) expected);
    g_failures++;
  }
}

int main(void) {
  GlRegionClip c;

  /* 1) 常规：整图贴到 (0,0) */
  expect_true("normal", gl_region_clip(0, 0, 100, 50, 0, 0, 100, 50, &c));
  expect_int("normal.srcPixX", c.srcPixX, 0);
  expect_int("normal.dstPixX", c.dstPixX, 0);
  expect_int("normal.w", c.width, 100);
  expect_int("normal.h", c.height, 50);

  /* 2) dst 为负（首行首列 tile）：dst=(-1,-1)，src=(0,0)，tex=508x254
   *    → 裁掉左侧 1 列与上方 1 行，src 平移 (+1,+1)，dst 从 (0,0) 开始 */
  expect_true("negDst", gl_region_clip(0, 0, 254, 254, -1, -1, 508, 254, &c));
  expect_int("negDst.srcPixX", c.srcPixX, 1);
  expect_int("negDst.srcPixY", c.srcPixY, 1);
  expect_int("negDst.dstPixX", c.dstPixX, 0);
  expect_int("negDst.dstPixY", c.dstPixY, 0);
  expect_int("negDst.w", c.width, 253);
  expect_int("negDst.h", c.height, 253);

  /* 3) dst 为负 -2（2px 边框 tile） */
  expect_true("negDst2", gl_region_clip(0, 0, 10, 10, -2, -2, 100, 100, &c));
  expect_int("negDst2.srcPixX", c.srcPixX, 2);
  expect_int("negDst2.w", c.width, 8);
  expect_int("negDst2.h", c.height, 8);

  /* 4) src 超出纹理右/下：dst=(90,40) srcW/H=20，tex=100x50 → 只写 10x10 */
  expect_true("overRightBottom", gl_region_clip(0, 0, 20, 20, 90, 40, 100, 50, &c));
  expect_int("overRightBottom.dstPixX", c.dstPixX, 90);
  expect_int("overRightBottom.dstPixY", c.dstPixY, 40);
  expect_int("overRightBottom.w", c.width, 10);
  expect_int("overRightBottom.h", c.height, 10);

  /* 5) 同时负偏移 + 超右：dst=(-3,0) srcW=10 texW=5 → 左裁 3、右裁 2 → 宽 5 */
  expect_true("negAndOver", gl_region_clip(0, 0, 10, 10, -3, 0, 5, 10, &c));
  expect_int("negAndOver.srcPixX", c.srcPixX, 3);
  expect_int("negAndOver.dstPixX", c.dstPixX, 0);
  expect_int("negAndOver.w", c.width, 5);

  /* 6) 完全在纹理外（dst 在右侧之外）→ false，不写 */
  expect_false("outsideRight", gl_region_clip(0, 0, 10, 10, 100, 0, 100, 100, &c));
  expect_false("outsideBottom", gl_region_clip(0, 0, 10, 10, 0, 100, 100, 100, &c));

  /* 7) 非法参数 */
  expect_false("zeroTex", gl_region_clip(0, 0, 10, 10, 0, 0, 0, 100, &c));
  expect_false("zeroSrc", gl_region_clip(0, 0, 0, 10, 0, 0, 100, 100, &c));
  expect_false("nullOut", gl_region_clip(0, 0, 10, 10, 0, 0, 100, 100, NULL));

  /* 8) 1:1 不缩放：宽高裁剪量对 src/dst 相同（用偏移差验证） */
  expect_true("noScale", gl_region_clip(5, 7, 30, 40, -4, -6, 200, 200, &c));
  expect_int("noScale.srcXShift", c.srcPixX - 5, 4);
  expect_int("noScale.dstXShift", c.dstPixX - (-4), 4);
  expect_int("noScale.srcYShift", c.srcPixY - 7, 6);
  expect_int("noScale.dstYShift", c.dstPixY - (-6), 6);

  /* 9) 源起点为负（ImageTextureTile 首行首列：src=(-1,-1), dst=(0,0)）：
   *    源裁到 (0,0)，目标必须右移/下移 (+1,+1) 以保留 1px 透明边框 */
  expect_true("negSrcTile0", gl_region_clip_with_source(-1, -1, 256, 256, 0, 0, 256, 256, 800, 1200, &c));
  expect_int("negSrcTile0.srcPixX", c.srcPixX, 0);
  expect_int("negSrcTile0.srcPixY", c.srcPixY, 0);
  expect_int("negSrcTile0.dstPixX", c.dstPixX, 1);
  expect_int("negSrcTile0.dstPixY", c.dstPixY, 1);
  expect_int("negSrcTile0.w", c.width, 255);
  expect_int("negSrcTile0.h", c.height, 255);

  /* 10) 源图小图 + 负源偏移 + 目标越界同时出现 */
  expect_true("negSrcRightClip", gl_region_clip_with_source(-2, -1, 258, 258, 0, 0, 256, 256, 100, 80, &c));
  expect_int("negSrcRightClip.srcPixX", c.srcPixX, 0);
  expect_int("negSrcRightClip.srcPixY", c.srcPixY, 0);
  expect_int("negSrcRightClip.dstPixX", c.dstPixX, 2);
  expect_int("negSrcRightClip.dstPixY", c.dstPixY, 1);
  expect_int("negSrcRightClip.w", c.width, 100);
  expect_int("negSrcRightClip.h", c.height, 80);

  /* 11) 负 src 与负 dst 叠加且完全超出源图右侧 */
  expect_false("negSrcOutsideBound", gl_region_clip_with_source(100, 0, 20, 20, 0, 0, 256, 256, 100, 100, &c));
  expect_false("negSrcZeroBound", gl_region_clip_with_source(0, 0, 10, 10, 0, 0, 10, 10, 0, 10, &c));

  if (g_failures == 0) {
    printf("ALL PASS (11 groups, 40 assertions)\n");
    return 0;
  }
  printf("%d FAILURE(S)\n", g_failures);
  return 1;
}
