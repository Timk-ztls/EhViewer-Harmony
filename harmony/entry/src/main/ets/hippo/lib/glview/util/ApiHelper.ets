/*
 * Copyright (C) 2012 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * `com.hippo.lib.glview.util.ApiHelper` 的 ArkTS 等价实现。
 *
 * 上游这个类只有一个职责：**用反射探测 Android 版本/字段/方法是否存在**，让同一份代码
 * 兼容 API 10 ~ 18。鸿蒙上不存在这套"老系统降级"问题，但为了保持 1:1 独占的调用点
 * 不变（glview 内 3 处 + 其他模块若干），这里保留全部常量名，并把语义重新定义成
 * "鸿蒙侧等价能力是否存在"。
 *
 * 逐项裁决（不能靠猜，所以写清楚）：
 *
 * | 上游常量 | 鸿蒙侧取值 | 依据 |
 * |---|---|---|
 * | `VERSION_CODES.*` | 原样保留 Android 数值 | 仅用作"上游分支阈值"的比较常量，不代表鸿蒙版本 |
 * | `AT_LEAST_16` | `true` | 鸿蒙 API 20 起点远高于 Android 16 的能力面 |
 * | `USE_888_PIXEL_FORMAT` | `true` | 鸿蒙解码统一 RGBA8888，无 RGB565 通道 |
 * | `HAS_MOTION_EVENT_TRANSFORM` | `true` | `MotionEvent.transform()` 由本项目自实现（等价层），恒可用 |
 * | `HAS_GLES20_REQUIRED` | `true` | XComponent + GLES3 是唯一渲染路径（DEVIATIONS D-007） |
 * | `HAS_VIEW_SYSTEM_UI_FLAG_*` / `HAS_SET_SYSTEM_UI_VISIBILITY` | `false` | 鸿蒙无 `View.setSystemUiVisibility`；全屏由 `window.setWindowLayoutFullScreen` 实现，不走该分支 |
 * | `HAS_SURFACE_TEXTURE*` / `HAS_SET_DEFALT_BUFFER_SIZE` | `false` | 鸿蒙用 XComponent Surface，无 `SurfaceTexture` |
 * | `HAS_MEDIA_*` / `HAS_FACE_DETECTION` / `HAS_CAMERA_*` / `HAS_GET_CAMERA_DISABLED` | `false` | 相机/媒体库属于其他模块（`ehviewer/client` 等），gl-render 不承接 |
 * | `HAS_OBJECT_ANIMATION` / `HAS_VIEW_PROPERTY_ANIMATOR` / `HAS_ROTATION_ANIMATION` 等 | `false` | 鸿蒙动画走 `@ohos.animator`/ArkUI 属性动画，上游这些分支只影响 Android 侧兼容 |
 *
 * 结论：**gl-render 内的实际行为只依赖 `HAS_MOTION_EVENT_TRANSFORM`（true）**，
 * 因此这次移植对本模块渲染/手势结果零影响；其余常量保留是为了让 1:1 对照审查时
 * 上游的 `if (ApiHelper.HAS_XXX)` 分支仍能读懂、且编译通过。
 */

/** 鸿蒙系统 API 版本（`deviceInfo.sdkApiVersion`，编译期不可知，运行时取值）。 */
const HARMONY_SDK_API: number = deviceInfo.sdkApiVersion;

export class ApiHelper {
  /** 上游 `Build.VERSION_CODES` 常量表，原样保留（数值即 Android API level）。 */
  static readonly GINGERBREAD_MR1: number = 10;
  static readonly HONEYCOMB: number = 11;
  static readonly HONEYCOMB_MR1: number = 12;
  static readonly HONEYCOMB_MR2: number = 13;
  static readonly ICE_CREAM_SANDWICH: number = 14;
  static readonly ICE_CREAM_SANDWICH_MR1: number = 15;
  static readonly JELLY_BEAN: number = 16;
  static readonly JELLY_BEAN_MR1: number = 17;
  static readonly JELLY_BEAN_MR2: number = 18;

  /** 鸿蒙侧实际 SDK 版本，等价上游的 `Build.VERSION.SDK_INT`。 */
  static readonly SDK_INT: number = HARMONY_SDK_API;

  static readonly AT_LEAST_16: boolean = true;
  static readonly USE_888_PIXEL_FORMAT: boolean = true;

  static readonly HAS_MOTION_EVENT_TRANSFORM: boolean = true;

  static readonly HAS_GLES20_REQUIRED: boolean = true;
  static readonly HAS_VIEW_SYSTEM_UI_FLAG_LAYOUT_STABLE: boolean = false;
  static readonly HAS_VIEW_SYSTEM_UI_FLAG_HIDE_NAVIGATION: boolean = false;
  static readonly HAS_SET_SYSTEM_UI_VISIBILITY: boolean = false;

  static readonly HAS_SURFACE_TEXTURE: boolean = false;
  static readonly HAS_SET_DEFALT_BUFFER_SIZE: boolean = false;
  static readonly HAS_RELEASE_SURFACE_TEXTURE: boolean = false;
  static readonly HAS_SURFACE_TEXTURE_RECORDING: boolean = false;

  static readonly HAS_MEDIA_COLUMNS_WIDTH_AND_HEIGHT: boolean = false;
  static readonly HAS_REUSING_BITMAP_IN_BITMAP_REGION_DECODER: boolean = true;
  static readonly HAS_REUSING_BITMAP_IN_BITMAP_FACTORY: boolean = true;
  static readonly HAS_OPTIONS_IN_MUTABLE: boolean = true;
  static readonly HAS_MEDIA_PROVIDER_FILES_TABLE: boolean = false;
  static readonly HAS_MEDIA_ACTION_SOUND: boolean = false;
  static readonly HAS_MTP: boolean = false;
  static readonly HAS_MEDIA_MUXER: boolean = false;

  static readonly HAS_FACE_DETECTION: boolean = false;
  static readonly HAS_GET_CAMERA_DISABLED: boolean = false;
  static readonly HAS_CAMERA_FOCUS_AREA: boolean = false;
  static readonly HAS_CAMERA_METERING_AREA: boolean = false;
  static readonly HAS_CAMERA_HDR: boolean = false;
  static readonly HAS_AUTO_FOCUS_MOVE_CALLBACK: boolean = false;
  static readonly HAS_TIME_LAPSE_RECORDING: boolean = false;
  static readonly HAS_ZOOM_WHEN_RECORDING: boolean = false;
  static readonly HAS_GET_SUPPORTED_VIDEO_SIZE: boolean = false;
  static readonly CAN_START_PREVIEW_IN_JPEG_CALLBACK: boolean = false;
  static readonly HAS_EFFECTS_RECORDING: boolean = false;
  static readonly HAS_EFFECTS_RECORDING_CONTEXT_INPUT: boolean = false;

  static readonly HAS_SET_BEAM_PUSH_URIS: boolean = false;
  static readonly HAS_REMOTE_VIEWS_SERVICE: boolean = false;
  static readonly HAS_INTENT_EXTRA_LOCAL_ONLY: boolean = false;

  static readonly HAS_ACTION_BAR: boolean = false;
  static readonly HAS_VIEW_TRANSFORM_PROPERTIES: boolean = false;
  static readonly HAS_VIEW_PROPERTY_ANIMATOR: boolean = false;
  static readonly HAS_OBJECT_ANIMATION: boolean = false;
  static readonly HAS_POST_ON_ANIMATION: boolean = false;
  static readonly HAS_ROTATION_ANIMATION: boolean = false;
  static readonly HAS_ORIENTATION_LOCK: boolean = true;
  static readonly HAS_CANCELLATION_SIGNAL: boolean = true;
  static readonly HAS_DISPLAY_LISTENER: boolean = true;
  static readonly HAS_ANNOUNCE_FOR_ACCESSIBILITY: boolean = true;
  static readonly HAS_SET_ICON_ATTRIBUTE: boolean = false;
  static readonly ENABLE_PHOTO_EDITOR: boolean = false;

  /**
   * 等价上游 `getIntFieldIfExists(Class, String, Object, int)`。
   * 鸿蒙无反射（ArkTS 硬约束第 1 条），因此恒返回默认值 —— 上游所有调用点都是
   * "拿不到就用默认值"的降级语义，取值一致。
   */
  static getIntFieldIfExists(_klass: Object | null, _fieldName: string, _obj: Object | null,
    defaultVal: number): number {
    // 参数名保留上游语义（klass/fieldName/obj），前缀下划线仅为满足 noUnusedParameters。
    return defaultVal;
  }
}
