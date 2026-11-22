/*
 * GL native 侧实现（C-1 契约）。
 *
 * 分四块：
 *   1) XComponent + EGL 生命周期（OnSurfaceCreated/Changed/Destroyed）
 *   2) 4 个 program 的编译与 location 表（shader 源码逐字取自 gl-render 的
 *      GLES20Canvas.ets，attribute/uniform 名不动）
 *   3) 命令流 replay：变长记录 [opcode, argc, args...]，argc 双向校验
 *   4) GL 对象：纹理（含 PixelMap 按 rowStride 逐行上传）/ 缓冲 / FBO
 *
 * 与 ArkTS 侧的三条时序约定（gl-render 2026-10-24 确认）：
 *   - init() 只能在 EGL context 就绪后调用
 *   - init() 不建 BOX_COORDINATES VBO（顶点表 264 float 由 ArkTS 经 genBuffer+bufferDataF32 上传）
 *   - replay() 必须可重入（同帧内多次调用），swap 只在 present() 里做
 */

#include <stdlib.h>
#include <string.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <native_window/external_window.h>
#include <multimedia/image_framework/image/pixelmap_native.h>

#include "gl_engine.h"
#include "gl_region.h"
#include "jni.h"          /* compat：仅为了与其余 NAPI 文件共用 JNIEnv 占位类型 */
#include "../jni/log.h"

/* 联调开关：把每一条 replay 记录落到 hilog，供与 ArkTS 录制器逐条对账。
 * 默认关（零开销）；CMake -DEHVIEWER_GL_TRACE=ON 打开。
 * 日志格式固定为 "GLTRACE op=<n> argc=<n> a=<arg0>,<arg1>,..."，便于脚本 grep 比对。 */
#ifndef EHVIEWER_GL_TRACE
#define EHVIEWER_GL_TRACE 0
#endif

/* ---------------- 1) EGL / XComponent ---------------- */

typedef struct {
  EGLDisplay display;
  EGLConfig config;
  EGLSurface surface;
  EGLContext context;
  void* window;
  int32_t width;
  int32_t height;
  bool ready;
} GlContext;

static GlContext g_ctx = { EGL_NO_DISPLAY, NULL, EGL_NO_SURFACE, EGL_NO_CONTEXT, NULL, 0, 0, false };
static bool g_programs_ready = false;

static void gl_engine_log_egl(const char* stage) {
  LOGE(MSG("EGL stage=%s error=0x%04x"), stage, eglGetError());
}

static bool egl_create_context_locked(void) {
  static const EGLint configAttribs[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
      EGL_DEPTH_SIZE, 0, EGL_STENCIL_SIZE, 8,
      EGL_NONE
  };
  static const EGLint contextAttribs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
  EGLint numConfigs = 0;

  g_ctx.display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (g_ctx.display == EGL_NO_DISPLAY) {
    gl_engine_log_egl("eglGetDisplay");
    return false;
  }
  if (eglInitialize(g_ctx.display, NULL, NULL) != EGL_TRUE) {
    gl_engine_log_egl("eglInitialize");
    g_ctx.display = EGL_NO_DISPLAY;
    return false;
  }
  if (eglChooseConfig(g_ctx.display, configAttribs, &g_ctx.config, 1, &numConfigs) != EGL_TRUE ||
      numConfigs < 1) {
    gl_engine_log_egl("eglChooseConfig");
    eglTerminate(g_ctx.display);
    g_ctx.display = EGL_NO_DISPLAY;
    g_ctx.config = NULL;
    return false;
  }
  g_ctx.context = eglCreateContext(g_ctx.display, g_ctx.config, EGL_NO_CONTEXT, contextAttribs);
  if (g_ctx.context == EGL_NO_CONTEXT) {
    gl_engine_log_egl("eglCreateContext");
    eglTerminate(g_ctx.display);
    g_ctx.display = EGL_NO_DISPLAY;
    g_ctx.config = NULL;
    return false;
  }
  return true;
}

static bool egl_create_surface_locked(void* window) {
  g_ctx.window = window;
  g_ctx.surface = eglCreateWindowSurface(g_ctx.display, g_ctx.config,
      (EGLNativeWindowType) window, NULL);
  if (g_ctx.surface == EGL_NO_SURFACE) {
    gl_engine_log_egl("eglCreateWindowSurface");
    g_ctx.window = NULL;
    return false;
  }
  if (eglMakeCurrent(g_ctx.display, g_ctx.surface, g_ctx.surface, g_ctx.context) != EGL_TRUE) {
    gl_engine_log_egl("eglMakeCurrent");
    eglDestroySurface(g_ctx.display, g_ctx.surface);
    g_ctx.surface = EGL_NO_SURFACE;
    g_ctx.window = NULL;
    return false;
  }
  EGLint w = 0;
  EGLint h = 0;
  eglQuerySurface(g_ctx.display, g_ctx.surface, EGL_WIDTH, &w);
  eglQuerySurface(g_ctx.display, g_ctx.surface, EGL_HEIGHT, &h);
  g_ctx.width = w;
  g_ctx.height = h;
  g_ctx.ready = true;
  return true;
}

static bool gl_engine_ensure_current(void) {
  if (!g_ctx.ready || g_ctx.display == EGL_NO_DISPLAY ||
      g_ctx.surface == EGL_NO_SURFACE || g_ctx.context == EGL_NO_CONTEXT) {
    return false;
  }
  if (eglGetCurrentContext() == g_ctx.context &&
      eglGetCurrentSurface(EGL_DRAW) == g_ctx.surface) {
    return true;
  }
  if (eglMakeCurrent(g_ctx.display, g_ctx.surface, g_ctx.surface, g_ctx.context) != EGL_TRUE) {
    gl_engine_log_egl("gl_engine_ensure_current");
    return false;
  }
  return true;
}

/* 2) program 表 —— 见下方 gl_programs 段 */

/* XComponent 回调：surface 全生命周期收在 native 侧（C-1 归属约定） */
static void OnSurfaceCreatedCB(OH_NativeXComponent* component, void* window) {
  uint64_t width = 0;
  uint64_t height = 0;
  bool created = false;

  LOGI(MSG("XComponent OnSurfaceCreated"));
  if (g_ctx.ready || g_ctx.display != EGL_NO_DISPLAY) {
    gl_engine_destroy_surface();
  }
  if (!egl_create_context_locked()) {
    return;
  }
  created = egl_create_surface_locked(window);
  if (!created) {
    gl_engine_destroy_surface();
    return;
  }
  if (component != NULL &&
      OH_NativeXComponent_GetXComponentSize(component, window, &width, &height) == 0 &&
      width > 0 && height > 0) {
    g_ctx.width = (int32_t) width;
    g_ctx.height = (int32_t) height;
  }
  /* context 就绪后才建 program（gl-render 的时序约束 1） */
  if (gl_engine_init() != GL_OK) {
    LOGE(MSG("gl_engine_init failed"));
  }
  glViewport(0, 0, g_ctx.width, g_ctx.height);
}

static void OnSurfaceChangedCB(OH_NativeXComponent* component, void* window) {
  uint64_t width = 0;
  uint64_t height = 0;
  (void) window;

  if (component == NULL ||
      OH_NativeXComponent_GetXComponentSize(component, window, &width, &height) != 0) {
    return;
  }
  g_ctx.width = (int32_t) width;
  g_ctx.height = (int32_t) height;
  if (g_ctx.ready) {
    eglMakeCurrent(g_ctx.display, g_ctx.surface, g_ctx.surface, g_ctx.context);
    glViewport(0, 0, g_ctx.width, g_ctx.height);
  }
}

static void OnSurfaceDestroyedCB(OH_NativeXComponent* component, void* window) {
  (void) component;
  (void) window;
  LOGI(MSG("XComponent OnSurfaceDestroyed"));
  gl_engine_destroy_surface();
}

static void DispatchTouchEventCB(OH_NativeXComponent* component, void* window) {
  (void) component;
  (void) window;
  /* 触摸由 ArkTS 侧处理（C-1 只划 GL 边界），这里留空实现以满足回调表 */
}

static OH_NativeXComponent_Callback g_xcomponentCallback = {
    OnSurfaceCreatedCB,
    OnSurfaceChangedCB,
    OnSurfaceDestroyedCB,
    DispatchTouchEventCB,
};

GlErr gl_engine_register_xcomponent(napi_env env, napi_value exports) {
  napi_value exportInstance = NULL;
  OH_NativeXComponent* component = NULL;

  if (env == NULL || exports == NULL) {
    return GL_BAD_ARGUMENT;
  }
  if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) != napi_ok) {
    /* XComponent 尚未声明 libraryname（页面未挂载）时属正常，等下一次加载 */
    LOGW(MSG("XComponent object not found in exports, skip callback registration"));
    return GL_NOT_READY;
  }
  if (napi_unwrap(env, exportInstance, (void**) &component) != napi_ok || component == NULL) {
    LOGE(MSG("can not unwrap OH_NativeXComponent"));
    return GL_NOT_READY;
  }
  if (OH_NativeXComponent_RegisterCallback(component, &g_xcomponentCallback) != 0) {
    LOGE(MSG("OH_NativeXComponent_RegisterCallback failed"));
    return GL_NOT_READY;
  }
  LOGI(MSG("XComponent callbacks registered"));
  return GL_OK;
}

/* ---------------- 2) program 编译 ---------------- */

static const char* DRAW_VERTEX_SHADER =
    "uniform mat4 uMatrix;\n"
    "attribute vec2 aPosition;\n"
    "void main() {\n"
    "  vec4 pos = vec4(aPosition, 0.0, 1.0);\n"
    "  gl_Position = uMatrix * pos;\n"
    "}\n";

static const char* DRAW_FRAGMENT_SHADER =
    "precision mediump float;\n"
    "uniform vec4 uColor;\n"
    "void main() {\n"
    "  gl_FragColor = uColor;\n"
    "}\n";

static const char* TEXTURE_VERTEX_SHADER =
    "uniform mat4 uMatrix;\n"
    "uniform mat4 uTextureMatrix;\n"
    "attribute vec2 aPosition;\n"
    "varying vec2 vTextureCoord;\n"
    "void main() {\n"
    "  vec4 pos = vec4(aPosition, 0.0, 1.0);\n"
    "  gl_Position = uMatrix * pos;\n"
    "  vTextureCoord = (uTextureMatrix * pos).xy;\n"
    "}\n";

static const char* TEXTURE_FRAGMENT_SHADER =
    "precision mediump float;\n"
    "varying vec2 vTextureCoord;\n"
    "uniform float uAlpha;\n"
    "uniform sampler2D uTextureSampler;\n"
    "void main() {\n"
    "  gl_FragColor = texture2D(uTextureSampler, vTextureCoord);\n"
    "  gl_FragColor *= uAlpha;\n"
    "}\n";

static const char* OES_TEXTURE_FRAGMENT_SHADER =
    "#extension GL_OES_EGL_image_external : require\n"
    "precision mediump float;\n"
    "varying vec2 vTextureCoord;\n"
    "uniform float uAlpha;\n"
    "uniform samplerExternalOES uTextureSampler;\n"
    "void main() {\n"
    "  gl_FragColor = texture2D(uTextureSampler, vTextureCoord);\n"
    "  gl_FragColor *= uAlpha;\n"
    "}\n";

static const char* MESH_VERTEX_SHADER =
    "uniform mat4 uMatrix;\n"
    "attribute vec2 aPosition;\n"
    "attribute vec2 aTextureCoordinate;\n"
    "varying vec2 vTextureCoord;\n"
    "void main() {\n"
    "  vec4 pos = vec4(aPosition, 0.0, 1.0);\n"
    "  gl_Position = uMatrix * pos;\n"
    "  vTextureCoord = aTextureCoordinate;\n"
    "}\n";

static GLuint g_programs[GL_PROGRAM_COUNT];
static GLint g_uColor[GL_PROGRAM_COUNT];
static GLint g_uMatrix[GL_PROGRAM_COUNT];
static GLint g_uTextureMatrix[GL_PROGRAM_COUNT];
static GLint g_uTextureSampler[GL_PROGRAM_COUNT];
static GLint g_uAlpha[GL_PROGRAM_COUNT];
/* ATTRIB[kind][slot]：slot0 = aPosition，slot1 = aTextureCoordinate（仅 mesh） */
static GLint g_attrib[GL_PROGRAM_COUNT][2];

static GLuint compile_shader(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  GLint status = 0;
  GLint length = 0;
  char* infoLog = NULL;

  if (shader == 0) {
    return 0;
  }
  glShaderSource(shader, 1, &source, NULL);
  glCompileShader(shader);
  glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
  if (status != GL_TRUE) {
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
    if (length > 0) {
      infoLog = (char*) malloc((size_t) length);
      if (infoLog != NULL) {
        glGetShaderInfoLog(shader, length, NULL, infoLog);
        LOGE(MSG("shader compile failed: %s"), infoLog);
        free(infoLog);
      }
    }
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

static GLuint link_program(const char* vertexSource, const char* fragmentSource) {
  GLuint vertex = compile_shader(GL_VERTEX_SHADER, vertexSource);
  GLuint fragment = compile_shader(GL_FRAGMENT_SHADER, fragmentSource);
  GLuint program = 0;
  GLint status = 0;
  GLint length = 0;
  char* infoLog = NULL;

  if (vertex == 0 || fragment == 0) {
    if (vertex != 0) {
      glDeleteShader(vertex);
    }
    if (fragment != 0) {
      glDeleteShader(fragment);
    }
    return 0;
  }

  program = glCreateProgram();
  glAttachShader(program, vertex);
  glAttachShader(program, fragment);
  glLinkProgram(program);
  glGetProgramiv(program, GL_LINK_STATUS, &status);
  glDeleteShader(vertex);
  glDeleteShader(fragment);
  if (status != GL_TRUE) {
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
    if (length > 0) {
      infoLog = (char*) malloc((size_t) length);
      if (infoLog != NULL) {
        glGetProgramInfoLog(program, length, NULL, infoLog);
        LOGE(MSG("program link failed: %s"), infoLog);
        free(infoLog);
      }
    }
    glDeleteProgram(program);
    return 0;
  }
  return program;
}

static void resolve_program_locations(int kind, bool withTextureMatrix, bool withColor,
                                      bool withSampler, bool withMeshCoord) {
  g_uMatrix[kind] = glGetUniformLocation(g_programs[kind], "uMatrix");
  g_uColor[kind] = withColor ? glGetUniformLocation(g_programs[kind], "uColor") : -1;
  g_uTextureMatrix[kind] =
      withTextureMatrix ? glGetUniformLocation(g_programs[kind], "uTextureMatrix") : -1;
  g_uTextureSampler[kind] =
      withSampler ? glGetUniformLocation(g_programs[kind], "uTextureSampler") : -1;
  g_uAlpha[kind] = withSampler ? glGetUniformLocation(g_programs[kind], "uAlpha") : -1;
  g_attrib[kind][0] = glGetAttribLocation(g_programs[kind], "aPosition");
  g_attrib[kind][1] =
      withMeshCoord ? glGetAttribLocation(g_programs[kind], "aTextureCoordinate") : -1;
}

GlErr gl_engine_init(void) {
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (g_programs_ready) {
    return GL_OK;
  }

  g_programs[GL_PROGRAM_DRAW] = link_program(DRAW_VERTEX_SHADER, DRAW_FRAGMENT_SHADER);
  g_programs[GL_PROGRAM_TEXTURE] = link_program(TEXTURE_VERTEX_SHADER, TEXTURE_FRAGMENT_SHADER);
  g_programs[GL_PROGRAM_OES] = link_program(TEXTURE_VERTEX_SHADER, OES_TEXTURE_FRAGMENT_SHADER);
  g_programs[GL_PROGRAM_MESH] = link_program(MESH_VERTEX_SHADER, TEXTURE_FRAGMENT_SHADER);

  for (int kind = 0; kind < GL_PROGRAM_COUNT; kind++) {
    if (g_programs[kind] == 0) {
      LOGE(MSG("program kind %d failed"), kind);
      return GL_PROGRAM_FAILED;
    }
  }

  resolve_program_locations(GL_PROGRAM_DRAW, false, true, false, false);
  resolve_program_locations(GL_PROGRAM_TEXTURE, true, false, true, false);
  resolve_program_locations(GL_PROGRAM_OES, true, false, true, false);
  resolve_program_locations(GL_PROGRAM_MESH, false, false, true, true);

  /* 上游 GLES20Canvas 构造后设置的混合模式；BOX_COORDINATES VBO 不在这里建 */
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

  g_programs_ready = true;
  LOGI(MSG("GL programs ready (%dx%d)"), g_ctx.width, g_ctx.height);
  return GL_OK;
}

/* ---------------- 3) 命令流 replay ---------------- */

/*
 * 命令流格式：Float32Array，变长记录 [opcode, argc, arg0..arg(argc-1)]，顺序即语义。
 * 整数也用 float 承载（精确上限 2^24）。
 *
 * C-1 补充（Lead 2026-10-24）：**每个 opcode 每个参数的单位必须在下面写死**，
 * gl-render 侧用 16 项断言锁同一条契约；本表与 GLCommandBuffer 的录制代码一一对应。
 *
 *  opcode 名称                  argc  参数（单位）
 *  ------ --------------------- ----  --------------------------------------------------
 *   1  SET_VIEWPORT              2    w, h                       （px，非 vp）
 *   2  CLEAR                     4    r, g, b, a                 （0..1 float）
 *   3  USE_PROGRAM               1    kind ∈ {0 draw,1 texture,2 oes,3 mesh}
 *   4  BLEND_ENABLE              1    0/1
 *   5  BLEND_COLOR               4    r, g, b, a                 （0..1 float）
 *   6  LINE_WIDTH                1    w                          （px，float）
 *   7  UNIFORM_COLOR             5    kind, r, g, b, a           （预乘 alpha）
 *   8  UNIFORM_MATRIX           17    kind + 16 floats（列主序 mat4）
 *   9  UNIFORM_TEXTURE_MATRIX   17    kind + 16 floats
 *  10  BIND_ARRAY_BUFFER         1    buffer id（0 = 解绑）
 *  11  VERTEX_ATTRIB_POINTER     4    kind, attrSlot(0=aPosition,1=aTextureCoordinate),
 *                                    size(=2, vec2), **offsetBytes**（首顶点字节偏移：
 *                                    fillRect=0 / drawLine=32 / drawRect=48 /
 *                                    fillOval|fillSector=80 / drawOval 外径=88）
 *                                    —— stride 不进命令流，恒为 size*sizeof(float)=8
 *  12  BIND_TEXTURE              2    target, texture id
 *  13  UNIFORM_SAMPLER           2    kind, texture unit
 *  14  UNIFORM_ALPHA             2    kind, alpha（0..1 float）
 *  15  ENABLE_ATTRIB             2    kind, attrSlot
 *  16  DISABLE_ATTRIB            2    kind, attrSlot
 *  17  DRAW_ARRAYS               3    mode, first(顶点下标), count
 *  18  BIND_ELEMENT_ARRAY_BUFFER 1    buffer id（0 = 解绑）
 *  19  DRAW_ELEMENTS             4    mode, count, type, offsetBytes
 *  20  BIND_FRAMEBUFFER          1    framebuffer id（0 = 解绑）
 *  21  ATTACH_TEXTURE            4    target(GL_FRAMEBUFFER=0x8D40；ES3 可能是
 *                                    GL_DRAW_FRAMEBUFFER), attachment, texTarget, texId
 *  22  END_FRAME                 0    哨兵；swap 只由 present() 做
 *  23  TEX_PARAMETER             3    target, pname, value(int)
 *  24  TEX_IMAGE_2D              6    target, internalformat, w, h, format, type（pixels=NULL）
 *  25  BLEND_FUNC                2    src, dst
 *
 * 全部整数参数以 float 承载，落地前一律 (int) 截断；越界/argc 不符/记录截断/末尾残留
 * 一律返回 GL_BAD_ARGUMENT 停帧（错位后再读会越界，必须硬停）。
 */

/* 期望 argc 表：与 gl-render 的 GLCommandBuffer 编码一一对应 */
static const int kExpectedArgc[GL_CMD_MAX_OPCODE + 1] = {
    /*0 unused*/ -1,
    /*1  SET_VIEWPORT*/ 2,
    /*2  CLEAR*/ 4,
    /*3  USE_PROGRAM*/ 1,
    /*4  BLEND_ENABLE*/ 1,
    /*5  BLEND_COLOR*/ 4,
    /*6  LINE_WIDTH*/ 1,
    /*7  UNIFORM_COLOR*/ 5,
    /*8  UNIFORM_MATRIX*/ 17,
    /*9  UNIFORM_TEXTURE_MATRIX*/ 17,
    /*10 BIND_ARRAY_BUFFER*/ 1,
    /*11 VERTEX_ATTRIB_POINTER*/ 4,
    /*12 BIND_TEXTURE*/ 2,
    /*13 UNIFORM_SAMPLER*/ 2,
    /*14 UNIFORM_ALPHA*/ 2,
    /*15 ENABLE_ATTRIB*/ 2,
    /*16 DISABLE_ATTRIB*/ 2,
    /*17 DRAW_ARRAYS*/ 3,
    /*18 BIND_ELEMENT_ARRAY_BUFFER*/ 1,
    /*19 DRAW_ELEMENTS*/ 4,
    /*20 BIND_FRAMEBUFFER*/ 1,
    /*21 ATTACH_TEXTURE*/ 4,
    /*22 END_FRAME*/ 0,
    /*23 TEX_PARAMETER*/ 3,
    /*24 TEX_IMAGE_2D*/ 6,
    /*25 BLEND_FUNC*/ 2,
};

static bool valid_kind(int kind) {
  return kind >= 0 && kind < GL_PROGRAM_COUNT;
}

static bool valid_slot(int kind, int slot) {
  if (slot != 0 && slot != 1) {
    return false;
  }
  return g_attrib[kind][slot] >= 0;
}

GlErr gl_engine_replay(const float* buffer, size_t count) {
  size_t i = 0;

  if (buffer == NULL) {
    return GL_BAD_ARGUMENT;
  }
  if (!g_programs_ready || !gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  /* 可重入：本函数不持有任何一次性状态，只有 GL 调用与局部变量 */
  while (i + 2 <= count) {
    const int op = (int) buffer[i];
    const int argc = (int) buffer[i + 1];
    const float* a = &buffer[i + 2];

    if (op < 1 || op > GL_CMD_MAX_OPCODE || kExpectedArgc[op] != argc) {
      LOGE(MSG("bad command op=%d argc=%d at %zu"), op, argc, i);
      return GL_BAD_ARGUMENT;
    }
    if (i + 2 + (size_t) argc > count) {
      LOGE(MSG("truncated command stream at %zu"), i);
      return GL_BAD_ARGUMENT;
    }

#if EHVIEWER_GL_TRACE
    /* 联调对账：格式固定 "GLTRACE op=<n> argc=<n> a=<...>"，最多打 8 个参数
     * （UNIFORM_MATRIX 的 16/17 个矩阵元素只打前 8 个，避免刷屏） */
    if (argc == 0) {
      LOGI("GLTRACE op=%d argc=0", op);
    } else if (argc <= 8) {
      LOGI("GLTRACE op=%d argc=%d a=%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
          op, argc, a[0], argc > 1 ? a[1] : 0.0f, argc > 2 ? a[2] : 0.0f,
          argc > 3 ? a[3] : 0.0f, argc > 4 ? a[4] : 0.0f, argc > 5 ? a[5] : 0.0f,
          argc > 6 ? a[6] : 0.0f, argc > 7 ? a[7] : 0.0f);
    } else {
      LOGI("GLTRACE op=%d argc=%d a[0..3]=%.4f,%.4f,%.4f,%.4f ... a[%d]=%.4f",
          op, argc, a[0], a[1], a[2], a[3], argc - 1, a[argc - 1]);
    }
#endif

    switch (op) {
      case 1: /* SET_VIEWPORT */
        glViewport(0, 0, (GLsizei) a[0], (GLsizei) a[1]);
        g_ctx.width = (int32_t) a[0];
        g_ctx.height = (int32_t) a[1];
        break;
      case 2: /* CLEAR */
        glClearColor(a[0], a[1], a[2], a[3]);
        glClear(GL_COLOR_BUFFER_BIT);
        break;
      case 3: { /* USE_PROGRAM */
        int kind = (int) a[0];
        if (!valid_kind(kind)) {
          return GL_BAD_ARGUMENT;
        }
        glUseProgram(g_programs[kind]);
        break;
      }
      case 4: /* BLEND_ENABLE */
        if ((int) a[0] != 0) {
          glEnable(GL_BLEND);
        } else {
          glDisable(GL_BLEND);
        }
        break;
      case 5: /* BLEND_COLOR */
        glBlendColor(a[0], a[1], a[2], a[3]);
        break;
      case 6: /* LINE_WIDTH */
        glLineWidth(a[0]);
        break;
      case 7: { /* UNIFORM_COLOR */
        int kind = (int) a[0];
        if (!valid_kind(kind) || g_uColor[kind] < 0) {
          return GL_BAD_ARGUMENT;
        }
        glUniform4f(g_uColor[kind], a[1], a[2], a[3], a[4]);
        break;
      }
      case 8: { /* UNIFORM_MATRIX */
        int kind = (int) a[0];
        if (!valid_kind(kind) || g_uMatrix[kind] < 0) {
          return GL_BAD_ARGUMENT;
        }
        glUniformMatrix4fv(g_uMatrix[kind], 1, GL_FALSE, a + 1);
        break;
      }
      case 9: { /* UNIFORM_TEXTURE_MATRIX */
        int kind = (int) a[0];
        if (!valid_kind(kind) || g_uTextureMatrix[kind] < 0) {
          return GL_BAD_ARGUMENT;
        }
        glUniformMatrix4fv(g_uTextureMatrix[kind], 1, GL_FALSE, a + 1);
        break;
      }
      case 10: /* BIND_ARRAY_BUFFER */
        glBindBuffer(GL_ARRAY_BUFFER, (GLuint) a[0]);
        break;
      case 11: { /* VERTEX_ATTRIB_POINTER(kind, slot, size, offsetBytes) */
        int kind = (int) a[0];
        int slot = (int) a[1];
        /* stride 不进命令流：BOXF 顶点表是紧凑的 vec2 数组，stride 恒为 size*sizeof(float)
         * a[3] 是**字节偏移**（顶点下标 * 8）：fillRect=0 / drawLine=32 / drawRect=48 /
         * fillOval|fillSector=80 / drawOval 外径=88。早期版本把 a[3] 当 stride、offset 恒 0，
         * 会让除 fillRect 外的 4 条路径全画错（线变矩形、椭圆变三角带）且不报错。 */
        GLsizei stride = (GLsizei) ((int) a[2] * (int) sizeof(float));
        if (!valid_kind(kind) || !valid_slot(kind, slot)) {
          return GL_BAD_ARGUMENT;
        }
        glVertexAttribPointer((GLuint) g_attrib[kind][slot], (GLint) a[2], GL_FLOAT, GL_FALSE,
            stride, (const void*) (uintptr_t) (int) a[3]);
        break;
      }
      case 12: /* BIND_TEXTURE(target, id) */
        glActiveTexture(GL_TEXTURE0);
        glBindTexture((GLenum) a[0], (GLuint) a[1]);
        break;
      case 13: { /* UNIFORM_SAMPLER */
        int kind = (int) a[0];
        if (!valid_kind(kind) || g_uTextureSampler[kind] < 0) {
          return GL_BAD_ARGUMENT;
        }
        glUniform1i(g_uTextureSampler[kind], (GLint) a[1]);
        break;
      }
      case 14: { /* UNIFORM_ALPHA */
        int kind = (int) a[0];
        if (!valid_kind(kind) || g_uAlpha[kind] < 0) {
          return GL_BAD_ARGUMENT;
        }
        glUniform1f(g_uAlpha[kind], a[1]);
        break;
      }
      case 15: { /* ENABLE_ATTRIB */
        int kind = (int) a[0];
        int slot = (int) a[1];
        if (!valid_kind(kind) || !valid_slot(kind, slot)) {
          return GL_BAD_ARGUMENT;
        }
        glEnableVertexAttribArray((GLuint) g_attrib[kind][slot]);
        break;
      }
      case 16: { /* DISABLE_ATTRIB */
        int kind = (int) a[0];
        int slot = (int) a[1];
        if (!valid_kind(kind) || !valid_slot(kind, slot)) {
          return GL_BAD_ARGUMENT;
        }
        glDisableVertexAttribArray((GLuint) g_attrib[kind][slot]);
        break;
      }
      case 17: /* DRAW_ARRAYS(mode, first, count) */
        glDrawArrays((GLenum) a[0], (GLint) a[1], (GLsizei) a[2]);
        break;
      case 18: /* BIND_ELEMENT_ARRAY_BUFFER */
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, (GLuint) a[0]);
        break;
      case 19: /* DRAW_ELEMENTS(mode, count, type, offsetBytes) */
        glDrawElements((GLenum) a[0], (GLsizei) a[1], (GLenum) a[2],
            (const void*) (uintptr_t) (int) a[3]);
        break;
      case 20: /* BIND_FRAMEBUFFER */
        glBindFramebuffer(GL_FRAMEBUFFER, (GLuint) a[0]);
        break;
      case 21: /* ATTACH_TEXTURE(target, attachment, texTarget, texId) */
        glFramebufferTexture2D((GLenum) a[0], (GLenum) a[1], (GLenum) a[2], (GLuint) a[3], 0);
        break;
      case 22: /* END_FRAME：哨兵，swap 由 present() 负责 */
        break;
      case 23: /* TEX_PARAMETER */
        glTexParameteri((GLenum) a[0], (GLenum) a[1], (GLint) a[2]);
        break;
      case 24: /* TEX_IMAGE_2D(target, internalformat, w, h, format, type) */
        glTexImage2D((GLenum) a[0], 0, (GLint) a[1], (GLsizei) a[2], (GLsizei) a[3], 0,
            (GLenum) a[4], (GLenum) a[5], NULL);
        break;
      case 25: /* BLEND_FUNC */
        glBlendFunc((GLenum) a[0], (GLenum) a[1]);
        break;
      default:
        return GL_BAD_ARGUMENT;
    }
    i += 2 + (size_t) argc;
  }

  /* 流里若残留半条记录，视为坏帧 */
  if (i != count) {
    LOGE(MSG("trailing bytes in command stream (%zu/%zu)"), i, count);
    return GL_BAD_ARGUMENT;
  }
  return GL_OK;
}

/* ---------------- 4) GL 对象 ---------------- */

int32_t gl_engine_gen_texture(void) {
  GLuint texture = 0;
  if (!gl_engine_ensure_current()) {
    return -1;
  }
  glGenTextures(1, &texture);
  return (int32_t) texture;
}

GlErr gl_engine_delete_texture(uint32_t id) {
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (id == 0) {
    return GL_BAD_ID;
  }
  glDeleteTextures(1, &id);
  return GL_OK;
}

/* PixelMap → 像素：按 rowStride 逐行上传，不假设 stride == width*4（C-1 §3） */
static GlErr upload_pixelmap(OH_PixelmapNative* pixelmap, int32_t* outWidth, int32_t* outHeight,
                            uint32_t* outStride, unsigned char** outData) {
  OH_Pixelmap_ImageInfo* info = NULL;
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t rowStride = 0;
  void* addr = NULL;
  Image_ErrorCode code;

  if (pixelmap == NULL) {
    return GL_BAD_ARGUMENT;
  }
  code = OH_PixelmapImageInfo_Create(&info);
  if (code != IMAGE_SUCCESS || info == NULL) {
    LOGE(MSG("OH_PixelmapImageInfo_Create failed: %d"), code);
    return GL_BAD_ARGUMENT;
  }
  code = OH_PixelmapNative_GetImageInfo(pixelmap, info);
  if (code == IMAGE_SUCCESS) {
    OH_PixelmapImageInfo_GetWidth(info, &width);
    OH_PixelmapImageInfo_GetHeight(info, &height);
    OH_PixelmapImageInfo_GetRowStride(info, &rowStride);
  }
  OH_PixelmapImageInfo_Release(info);
  if (code != IMAGE_SUCCESS || width == 0 || height == 0) {
    LOGE(MSG("pixelmap info invalid: %d"), code);
    return GL_BAD_ARGUMENT;
  }

  code = OH_PixelmapNative_AccessPixels(pixelmap, &addr);
  if (code != IMAGE_SUCCESS || addr == NULL) {
    LOGE(MSG("OH_PixelmapNative_AccessPixels failed: %d"), code);
    return GL_OUT_OF_RESOURCES;
  }

  *outWidth = (int32_t) width;
  *outHeight = (int32_t) height;
  *outStride = rowStride == 0 ? width * 4 : rowStride;
  *outData = (unsigned char*) addr;
  return GL_OK;
}

GlErr gl_engine_tex_image_2d(uint32_t id, int32_t width, int32_t height,
                             uint32_t format, uint32_t type, napi_env env, napi_value pixelmapValue) {
  OH_PixelmapNative* pixelmap = NULL;
  unsigned char* data = NULL;
  int32_t pxWidth = 0;
  int32_t pxHeight = 0;
  uint32_t stride = 0;
  GlErr err;
  bool tightRows;

  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (id == 0) {
    return GL_BAD_ID;
  }
  if (OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env, pixelmapValue, &pixelmap) != IMAGE_SUCCESS ||
      pixelmap == NULL) {
    LOGE(MSG("can not convert napi value to OH_PixelmapNative"));
    return GL_BAD_ARGUMENT;
  }

  err = upload_pixelmap(pixelmap, &pxWidth, &pxHeight, &stride, &data);
  if (err != GL_OK) {
    OH_PixelmapNative_Release(pixelmap);
    return err;
  }
  /* gl-render 传的是逻辑宽高；这里以 PixelMap 实际尺寸为准并记录差异 */
  if (width != pxWidth || height != pxHeight) {
    LOGW(MSG("texImage2D size mismatch caller=%dx%d pixelmap=%dx%d, use pixelmap"),
        width, height, pxWidth, pxHeight);
  }

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, id);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

  tightRows = (stride == (uint32_t) pxWidth * 4);
  if (tightRows) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, pxWidth, pxHeight, 0, (GLenum) format, (GLenum) type, data);
  } else {
    /* stride != width*4：先申请紧凑空间，逐行拷，再一次性上传 */
    size_t tight = (size_t) pxWidth * (size_t) pxHeight * 4;
    unsigned char* packed = (unsigned char*) malloc(tight);
    if (packed == NULL) {
      OH_PixelmapNative_UnaccessPixels(pixelmap);
      OH_PixelmapNative_Release(pixelmap);
      return GL_OUT_OF_RESOURCES;
    }
    for (int32_t y = 0; y < pxHeight; y++) {
      memcpy(packed + (size_t) y * (size_t) pxWidth * 4,
             data + (size_t) y * (size_t) stride, (size_t) pxWidth * 4);
    }
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, pxWidth, pxHeight, 0, (GLenum) format, (GLenum) type, packed);
    free(packed);
  }

  OH_PixelmapNative_UnaccessPixels(pixelmap);
  OH_PixelmapNative_Release(pixelmap);
  return GL_OK;
}

GlErr gl_engine_tex_sub_image_2d(uint32_t id, int32_t xOffset, int32_t yOffset,
                                 int32_t width, int32_t height, uint32_t format, uint32_t type,
                                 napi_env env, napi_value pixelmapValue) {
  OH_PixelmapNative* pixelmap = NULL;
  unsigned char* data = NULL;
  int32_t pxWidth = 0;
  int32_t pxHeight = 0;
  uint32_t stride = 0;
  GlErr err;
  bool tightRows;

  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (id == 0) {
    return GL_BAD_ID;
  }
  if (OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env, pixelmapValue, &pixelmap) != IMAGE_SUCCESS ||
      pixelmap == NULL) {
    return GL_BAD_ARGUMENT;
  }
  err = upload_pixelmap(pixelmap, &pxWidth, &pxHeight, &stride, &data);
  if (err != GL_OK) {
    OH_PixelmapNative_Release(pixelmap);
    return err;
  }

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, id);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

  tightRows = (stride == (uint32_t) pxWidth * 4);
  if (tightRows) {
    glTexSubImage2D(GL_TEXTURE_2D, 0, xOffset, yOffset, pxWidth, pxHeight,
        (GLenum) format, (GLenum) type, data);
  } else {
    size_t tight = (size_t) pxWidth * (size_t) pxHeight * 4;
    unsigned char* packed = (unsigned char*) malloc(tight);
    if (packed == NULL) {
      OH_PixelmapNative_UnaccessPixels(pixelmap);
      OH_PixelmapNative_Release(pixelmap);
      return GL_OUT_OF_RESOURCES;
    }
    for (int32_t y = 0; y < pxHeight; y++) {
      memcpy(packed + (size_t) y * (size_t) pxWidth * 4,
             data + (size_t) y * (size_t) stride, (size_t) pxWidth * 4);
    }
    glTexSubImage2D(GL_TEXTURE_2D, 0, xOffset, yOffset, pxWidth, pxHeight,
        (GLenum) format, (GLenum) type, packed);
    free(packed);
  }

  OH_PixelmapNative_UnaccessPixels(pixelmap);
  OH_PixelmapNative_Release(pixelmap);
  return GL_OK;
}

/* 把 pixelMap 的 [srcX,srcY,srcW,srcH) 区域 blit 到 id 纹理的 (dstX,dstY)。
 *
 * 为什么需要它（gl-render 的 ImageTexture）：大图被切成 254/508 内容 + 1/2 像素边框的 tile，
 * 每块上传时 dst 是 offsetX - borderSize，**首行首列是负偏移**；而 glTexSubImage2D 的
 * xoffset/yoffset 不允许为负（GL_INVALID_VALUE）。上游 nativeTexImage 支持"区域渲染到任意偏移
 * + 越界裁剪"，本函数是它的等价实现。
 *
 * 语义：
 *   - srcX/srcY/srcW/srcH 允许超出 pixelMap（超出部分跳过）
 *   - dstX/dstY 允许为负（负的部分裁掉），裁多少 src 就平移多少（**1:1 不缩放**）
 *   - init=true 时先用 glTexImage2D(GL_RGBA, texW, texH, NULL) 分配纹理存储，再 blit
 *   - 完全在纹理外 → 返回 GL_OK（无写入，不是错误）
 */
GlErr gl_engine_tex_image_region(uint32_t id, bool init, napi_env env, napi_value pixelmapValue,
                                 int32_t srcX, int32_t srcY, int32_t srcW, int32_t srcH,
                                 int32_t dstX, int32_t dstY, int32_t texW, int32_t texH) {
  OH_PixelmapNative* pixelmap = NULL;
  OH_Pixelmap_ImageInfo* info = NULL;
  unsigned char* data = NULL;
  void* addr = NULL;
  uint32_t pmWidth = 0;
  uint32_t pmHeight = 0;
  uint32_t rowStride = 0;
  GlRegionClip clip;
  int32_t readX;
  int32_t readY;
  int32_t readW;
  int32_t readH;
  unsigned char* packed = NULL;
  Image_ErrorCode code;

  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (id == 0 || texW <= 0 || texH <= 0) {
    return GL_BAD_ARGUMENT;
  }
  if (OH_PixelmapNative_ConvertPixelmapNativeFromNapi(env, pixelmapValue, &pixelmap) != IMAGE_SUCCESS ||
      pixelmap == NULL) {
    return GL_BAD_ARGUMENT;
  }

  code = OH_PixelmapImageInfo_Create(&info);
  if (code != IMAGE_SUCCESS || info == NULL) {
    OH_PixelmapNative_Release(pixelmap);
    return GL_BAD_ARGUMENT;
  }
  code = OH_PixelmapNative_GetImageInfo(pixelmap, info);
  if (code == IMAGE_SUCCESS) {
    OH_PixelmapImageInfo_GetWidth(info, &pmWidth);
    OH_PixelmapImageInfo_GetHeight(info, &pmHeight);
    OH_PixelmapImageInfo_GetRowStride(info, &rowStride);
  }
  OH_PixelmapImageInfo_Release(info);
  if (code != IMAGE_SUCCESS || pmWidth == 0 || pmHeight == 0) {
    OH_PixelmapNative_Release(pixelmap);
    return GL_BAD_ARGUMENT;
  }
  if (rowStride == 0) {
    rowStride = pmWidth * 4;
  }

  /* 先计算纹理边界 + 源图边界联合裁剪，确定写入矩形 */
  bool hasClip = gl_region_clip_with_source(
      srcX, srcY, srcW, srcH, dstX, dstY, texW, texH,
      (int32_t) pmWidth, (int32_t) pmHeight, &clip);

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, id);
  if (init) {
    bool fullCover = hasClip &&
        clip.dstPixX == 0 && clip.dstPixY == 0 &&
        clip.width == texW && clip.height == texH;
    if (fullCover) {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texW, texH, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    } else {
      /* 未全覆盖时把纹理底板清为全透明黑，防止 tile 边缘采到未初始化显存 */
      void* zeroBuf = NULL;
      size_t pixelCount = (size_t) texW * (size_t) texH;
      if (texW > 0 && texH > 0 && pixelCount <= SIZE_MAX / 4u) {
        zeroBuf = calloc(pixelCount, 4u);
      }
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, texW, texH, 0, GL_RGBA, GL_UNSIGNED_BYTE, zeroBuf);
      free(zeroBuf);
    }
  }

  if (!hasClip) {
    /* 完全在纹理/源图之外：无写入，语义上不是错误 */
    OH_PixelmapNative_Release(pixelmap);
    return GL_OK;
  }

  readX = clip.srcPixX;
  readY = clip.srcPixY;
  readW = clip.width;
  readH = clip.height;

  code = OH_PixelmapNative_AccessPixels(pixelmap, &addr);
  if (code != IMAGE_SUCCESS || addr == NULL) {
    LOGE(MSG("OH_PixelmapNative_AccessPixels failed: %d"), code);
    OH_PixelmapNative_Release(pixelmap);
    return GL_OUT_OF_RESOURCES;
  }
  data = (unsigned char*) addr;

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  if (readX == 0 && rowStride == (uint32_t) readW * 4) {
    /* 紧凑行：直接把源指针按行偏移传进去（glTexSubImage2D 支持任意指针） */
    glTexSubImage2D(GL_TEXTURE_2D, 0, clip.dstPixX, clip.dstPixY, readW, readH,
        GL_RGBA, GL_UNSIGNED_BYTE, data + (size_t) readY * rowStride + (size_t) readX * 4);
  } else {
    /* 非紧凑行：逐行拷进临时缓冲，一次上传（每 tile 一次 malloc，不是每行一次调用） */
    size_t tight = (size_t) readW * (size_t) readH * 4;
    packed = (unsigned char*) malloc(tight);
    if (packed == NULL) {
      OH_PixelmapNative_UnaccessPixels(pixelmap);
      OH_PixelmapNative_Release(pixelmap);
      return GL_OUT_OF_RESOURCES;
    }
    for (int32_t y = 0; y < readH; y++) {
      memcpy(packed + (size_t) y * (size_t) readW * 4,
             data + (size_t) (readY + y) * rowStride + (size_t) readX * 4,
             (size_t) readW * 4);
    }
    glTexSubImage2D(GL_TEXTURE_2D, 0, clip.dstPixX, clip.dstPixY, readW, readH,
        GL_RGBA, GL_UNSIGNED_BYTE, packed);
    free(packed);
  }

  OH_PixelmapNative_UnaccessPixels(pixelmap);
  OH_PixelmapNative_Release(pixelmap);
  return GL_OK;
}
/* 用单色填充一块纹理区域（替代上游「全零 Bitmap 刷 4 条边」的写法）。
 * 用途：非 2 次幂纹理的边框填充（左 1×texHeight、上 texWidth×1、右/下同理），
 * 不刷这 4 条边会在 GL_CLAMP_TO_EDGE + LINEAR 下采到内容像素，表现为右/下 1px 拖影。
 * argb 采用 Android/GL 习惯的 **0xAARRGGBB**（与上游 Color.argb 一致）：
 *   0x11223344 → a=0x11, r=0x22, g=0x33, b=0x44
 *   0xFF00FF00 → 不透明绿；0x00000000 → 全透明（当前唯一调用方用的就是这个）
 * 内存顺序按 GL_RGBA/GL_UNSIGNED_BYTE 落成 r,g,b,a 四字节，不做预乘。
 */
GlErr gl_engine_tex_sub_image_2d_fill(uint32_t id, int32_t xOffset, int32_t yOffset,
                                      int32_t width, int32_t height, uint32_t format,
                                      uint32_t type, uint32_t argb) {
  uint32_t a = (argb >> 24) & 0xFFu;
  uint32_t r = (argb >> 16) & 0xFFu;
  uint32_t g = (argb >> 8) & 0xFFu;
  uint32_t b = argb & 0xFFu;
  uint32_t packed;
  uint32_t* pixels = NULL;
  size_t pixelCount;

  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (id == 0) {
    return GL_BAD_ID;
  }
  if (width <= 0 || height <= 0) {
    return GL_BAD_ARGUMENT;
  }

  pixelCount = (size_t) width * (size_t) height;
  pixels = (uint32_t*) malloc(pixelCount * sizeof(uint32_t));
  if (pixels == NULL) {
    return GL_OUT_OF_RESOURCES;
  }
  /* little-endian 下按 r,g,b,a 顺序落在字节上 */
  packed = r | (g << 8) | (b << 16) | (a << 24);
  for (size_t i = 0; i < pixelCount; i++) {
    pixels[i] = packed;
  }

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, id);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexSubImage2D(GL_TEXTURE_2D, 0, xOffset, yOffset, width, height,
      (GLenum) format, (GLenum) type, pixels);

  free(pixels);
  return GL_OK;
}

/* 缓冲：记录 genBuffer 时的 target，bufferData 时按记录绑回 */
#define GL_MAX_TRACKED_BUFFERS 256
typedef struct {
  uint32_t id;
  uint32_t target;
} BufferSlot;

static BufferSlot g_buffers[GL_MAX_TRACKED_BUFFERS];

static BufferSlot* find_buffer(uint32_t id) {
  for (int i = 0; i < GL_MAX_TRACKED_BUFFERS; i++) {
    if (g_buffers[i].id == id) {
      return &g_buffers[i];
    }
  }
  return NULL;
}

int32_t gl_engine_gen_buffer(uint32_t target) {
  GLuint buffer = 0;
  if (!gl_engine_ensure_current()) {
    return -1;
  }
  if (target != GL_ARRAY_BUFFER && target != GL_ELEMENT_ARRAY_BUFFER) {
    return -1;
  }
  glGenBuffers(1, &buffer);
  if (buffer == 0) {
    return -1;
  }
  for (int i = 0; i < GL_MAX_TRACKED_BUFFERS; i++) {
    if (g_buffers[i].id == 0) {
      g_buffers[i].id = buffer;
      g_buffers[i].target = target;
      break;
    }
  }
  return (int32_t) buffer;
}

static GlErr buffer_data(uint32_t id, const void* data, size_t byteCount) {
  BufferSlot* slot = find_buffer(id);
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (slot == NULL) {
    return GL_BAD_ID;
  }
  glBindBuffer(slot->target, id);
  glBufferData(slot->target, (GLsizeiptr) byteCount, data, GL_STATIC_DRAW);
  return GL_OK;
}

GlErr gl_engine_buffer_data_f32(uint32_t id, const float* data, size_t count) {
  if (data == NULL) {
    return GL_BAD_ARGUMENT;
  }
  return buffer_data(id, data, count * sizeof(float));
}

GlErr gl_engine_buffer_data_u8(uint32_t id, const unsigned char* data, size_t count) {
  if (data == NULL) {
    return GL_BAD_ARGUMENT;
  }
  return buffer_data(id, data, count);
}

GlErr gl_engine_delete_buffer(uint32_t id) {
  BufferSlot* slot = find_buffer(id);
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (slot == NULL) {
    return GL_BAD_ID;
  }
  glDeleteBuffers(1, &id);
  slot->id = 0;
  slot->target = 0;
  return GL_OK;
}

int32_t gl_engine_gen_framebuffer(void) {
  GLuint framebuffer = 0;
  if (!gl_engine_ensure_current()) {
    return -1;
  }
  glGenFramebuffers(1, &framebuffer);
  return (int32_t) framebuffer;
}

GlErr gl_engine_bind_framebuffer(uint32_t id) {
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  glBindFramebuffer(GL_FRAMEBUFFER, id);
  return GL_OK;
}

GlErr gl_engine_attach_texture(uint32_t target, uint32_t attachment, uint32_t texTarget,
                               uint32_t textureId) {
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  glFramebufferTexture2D((GLenum) target, (GLenum) attachment, (GLenum) texTarget, textureId, 0);
  return GL_OK;
}

GlErr gl_engine_delete_framebuffer(uint32_t id) {
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (id == 0) {
    return GL_BAD_ID;
  }
  glDeleteFramebuffers(1, &id);
  return GL_OK;
}

GlErr gl_engine_unbind_framebuffer(void) {
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  return GL_OK;
}

/* ---------------- 生命周期 / 查询 ---------------- */

GlErr gl_engine_set_surface(int32_t width, int32_t height) {
  if (!g_ctx.ready) {
    return GL_NOT_READY;
  }
  if (width > 0 && height > 0) {
    g_ctx.width = width;
    g_ctx.height = height;
  }
  if (eglMakeCurrent(g_ctx.display, g_ctx.surface, g_ctx.surface, g_ctx.context) != EGL_TRUE) {
    gl_engine_log_egl("eglMakeCurrent");
    return GL_GL_ERROR;
  }
  glViewport(0, 0, g_ctx.width, g_ctx.height);
  return GL_OK;
}

GlErr gl_engine_present(void) {
  if (!gl_engine_ensure_current()) {
    return GL_NOT_READY;
  }
  if (eglSwapBuffers(g_ctx.display, g_ctx.surface) != EGL_TRUE) {
    gl_engine_log_egl("eglSwapBuffers");
    return GL_GL_ERROR;
  }
  return GL_OK;
}

GlErr gl_engine_destroy_surface(void) {
  if (g_ctx.display == EGL_NO_DISPLAY) {
    g_ctx.ready = false;
    g_ctx.surface = EGL_NO_SURFACE;
    g_ctx.context = EGL_NO_CONTEXT;
    g_ctx.config = NULL;
    g_ctx.window = NULL;
    g_ctx.width = 0;
    g_ctx.height = 0;
    return GL_OK;
  }
  if (g_programs_ready && g_ctx.context != EGL_NO_CONTEXT && g_ctx.surface != EGL_NO_SURFACE) {
    eglMakeCurrent(g_ctx.display, g_ctx.surface, g_ctx.surface, g_ctx.context);
    for (int kind = 0; kind < GL_PROGRAM_COUNT; kind++) {
      if (g_programs[kind] != 0) {
        glDeleteProgram(g_programs[kind]);
        g_programs[kind] = 0;
      }
    }
    g_programs_ready = false;
  }
  eglMakeCurrent(g_ctx.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  if (g_ctx.surface != EGL_NO_SURFACE) {
    eglDestroySurface(g_ctx.display, g_ctx.surface);
    g_ctx.surface = EGL_NO_SURFACE;
  }
  if (g_ctx.context != EGL_NO_CONTEXT) {
    eglDestroyContext(g_ctx.display, g_ctx.context);
    g_ctx.context = EGL_NO_CONTEXT;
  }
  eglTerminate(g_ctx.display);
  g_ctx.display = EGL_NO_DISPLAY;
  g_ctx.config = NULL;
  g_ctx.window = NULL;
  g_ctx.width = 0;
  g_ctx.height = 0;
  memset(g_buffers, 0, sizeof(g_buffers));
  g_ctx.ready = false;
  return GL_OK;
}

GlErr gl_engine_is_ready(bool* ready) {
  if (ready == NULL) {
    return GL_BAD_ARGUMENT;
  }
  *ready = g_ctx.ready && g_programs_ready;
  return GL_OK;
}

int32_t gl_engine_get_error(void) {
  if (!gl_engine_ensure_current()) {
    return 0;
  }
  return (int32_t) glGetError();
}

const char* gl_engine_get_string(uint32_t what) {
  if (!gl_engine_ensure_current()) {
    return "";
  }
  const GLubyte* value = glGetString((GLenum) what);
  return value == NULL ? "" : (const char*) value;
}




