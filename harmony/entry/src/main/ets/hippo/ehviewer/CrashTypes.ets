/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0119（配套）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/CrashTypes.ets
 *
 * `Crash` 需要的三组数据快照，抽成独立文件（ArkTS 同文件多类可用，但拆开后
 * ui-scene/AppWiring 只需 import 类型，不必把 `Crash` 的实现拉进依赖）。
 *
 * 平台映射（**没有的字段填空串，不编造**）：
 *  · `PacketInfo`      ← `bundleManager.getBundleInfoForSelf()` 的 name/versionName/versionCode
 *  · `CrashDeviceInfo` ← `@ohos.deviceInfo`（deviceType/manufacture/model/osFullName/sdkApiVersion…）
 *    鸿蒙没有 BOARD/BOOTLOADER/CPU_ABI2/FINGERPRINT/HOST/RADIO/SERIAL/TAGS/TYPE/USER/CODENAME/
 *    INCREMENTAL 这些概念 → 对应字段填空串（日志里显示 `KEY=`，与上游"取不到时为空"表现一致）
 *  · `CrashMemoryInfo` ← `@ohos.hidebug`/`process` 的内存数字（字节）
 */

/** 上游 `PackageInfo` 用到的四个字段 */
export class PacketInfo {
  packageName: string;
  versionName: string | null;
  versionCode: number;

  constructor(packageName: string, versionName: string | null, versionCode: number) {
    this.packageName = packageName;
    this.versionName = versionName;
    this.versionCode = versionCode;
  }
}

/** 上游 `collectInfo` 里 `Build.*` 的 22 个字段（鸿蒙缺的填空串） */
export class CrashDeviceInfo {
  board: string = '';
  bootloader: string = '';
  cpuAbi: string = '';
  cpuAbi2: string = '';
  device: string = '';
  display: string = '';
  fingerprint: string = '';
  hardware: string = '';
  host: string = '';
  id: string = '';
  manufacturer: string = '';
  model: string = '';
  product: string = '';
  radio: string = '';
  serial: string = '';
  tags: string = '';
  type: string = '';
  user: string = '';
  codename: string = '';
  incremental: string = '';
  release: string = '';
  sdkInt: number = 0;

  constructor() {
  }
}

/** 四行内存（字节数，格式化走 `humanReadableByteCount(…, false)`） */
export class CrashMemoryInfo {
  /** 上游 `OSUtils.getAppAllocatedMemory()` */
  appAllocated: number = 0;
  /** 上游 `Debug.getNativeHeapAllocatedSize()` */
  nativeAllocated: number = 0;
  /** 上游 `OSUtils.getAppMaxMemory()` */
  appMax: number = 0;
  /** 上游 `OSUtils.getTotalMemory()` */
  total: number = 0;

  constructor() {
  }
}
/** 上游 `Activity.getClass().getName()` + `StageActivity.getTopSceneClass().getName()` */
export class CrashRuntimeInfo {
  topActivityClassName: string | null;
  topSceneClassName: string | null;

  constructor(topActivityClassName: string | null, topSceneClassName: string | null) {
    this.topActivityClassName = topActivityClassName;
    this.topSceneClassName = topSceneClassName;
  }
}