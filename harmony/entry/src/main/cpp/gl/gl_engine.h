/*
 * GL native 侧（C-1 契约，鸿蒙侧新增，见 inventory/native-image.extra.txt）。
 *
 * 对应上游：glview 的 GLES20Canvas/GLES20IdImpl 背后的真实 GL 调用，
 * 鸿蒙侧 ArkTS 只录制命令流，真正的 GL 调用全部在这里执行。
 *
 * 线程：全部函数在 render 线程调用（C-1 §4），本模块不做自己的线程调度。
 * 返回码：统一 GlErr，禁止裸 bool（C-1 §2）。
 */
#ifndef EHVIEWER_GL_ENGINE_H
#define EHVIEWER_GL_ENGINE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <napi/native_api.h>

/* 与 ets/native/GLNativeBridge.ets 的 GLErr 一一对应 */
typedef enum {
  GL_OK = 0,
  GL_NOT_READY = 1,
  GL_BAD_ID = 2,
  GL_OUT_OF_RESOURCES = 3,
  GL_PROGRAM_FAILED = 4,
  GL_GL_ERROR = 5,
  GL_BAD_ARGUMENT = 6
} GlErr;

/* program 种类：命令流 USE_PROGRAM 的 arg0 */
#define GL_PROGRAM_DRAW    0
#define GL_PROGRAM_TEXTURE 1
#define GL_PROGRAM_OES     2
#define GL_PROGRAM_MESH    3
#define GL_PROGRAM_COUNT   4

#define GL_CMD_MAX_OPCODE 25

/* XComponent 回调注册（在 napi Init 里调用，需 exports 上有 __NATIVE_XCOMPONENT_OBJ__） */
GlErr gl_engine_register_xcomponent(napi_env env, napi_value exports);

/* 生命周期 */
GlErr gl_engine_init(void);
GlErr gl_engine_set_surface(int32_t width, int32_t height);
GlErr gl_engine_destroy_surface(void);
GlErr gl_engine_present(void);
GlErr gl_engine_is_ready(bool* ready);

/* 命令流：变长记录 [opcode, argc, args...]，argc 与期望表双向校验 */
GlErr gl_engine_replay(const float* buffer, size_t count);

/* 纹理 */
int32_t gl_engine_gen_texture(void);
GlErr gl_engine_delete_texture(uint32_t id);
GlErr gl_engine_tex_image_2d(uint32_t id, int32_t width, int32_t height,
                             uint32_t format, uint32_t type, napi_env env, napi_value pixelmap);
GlErr gl_engine_tex_sub_image_2d(uint32_t id, int32_t xOffset, int32_t yOffset,
                                 int32_t width, int32_t height, uint32_t format, uint32_t type,
                                 napi_env env, napi_value pixelmap);
GlErr gl_engine_tex_sub_image_2d_fill(uint32_t id, int32_t xOffset, int32_t yOffset,
                                      int32_t width, int32_t height, uint32_t format,
                                      uint32_t type, uint32_t argb);
/* 区域 blit（C-1 补充，gl-render 的 ImageTexture 依赖）：允许 dst 负偏移，越界部分裁剪。
 * init=true 时先分配纹理存储；src 与 dst 1:1 不缩放。 */
GlErr gl_engine_tex_image_region(uint32_t id, bool init, napi_env env, napi_value pixelmap,
                                 int32_t srcX, int32_t srcY, int32_t srcW, int32_t srcH,
                                 int32_t dstX, int32_t dstY, int32_t texW, int32_t texH);

/* 顶点/索引缓冲 */
int32_t gl_engine_gen_buffer(uint32_t target);
GlErr gl_engine_buffer_data_f32(uint32_t id, const float* data, size_t count);
GlErr gl_engine_buffer_data_u8(uint32_t id, const unsigned char* data, size_t count);
GlErr gl_engine_delete_buffer(uint32_t id);

/* 离屏渲染目标 */
int32_t gl_engine_gen_framebuffer(void);
GlErr gl_engine_bind_framebuffer(uint32_t id);
GlErr gl_engine_attach_texture(uint32_t target, uint32_t attachment, uint32_t texTarget, uint32_t textureId);
GlErr gl_engine_delete_framebuffer(uint32_t id);
GlErr gl_engine_unbind_framebuffer(void);

/* 查询 */
int32_t gl_engine_get_error(void);
const char* gl_engine_get_string(uint32_t what);

#endif /* EHVIEWER_GL_ENGINE_H */


