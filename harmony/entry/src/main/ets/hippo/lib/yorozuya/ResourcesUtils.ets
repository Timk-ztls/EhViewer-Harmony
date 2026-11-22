/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0420   上游: com/hippo/lib/yorozuya/ResourcesUtils.java（85 行）
 * 目标   : harmony/entry/src/main/ets/hippo/lib/yorozuya/ResourcesUtils.ets
 *
 * 上游四个方法都是"从 `TypedValue` 取某个类型的值，**类型不符就抛 NotFoundException**"。
 * 真正被移植的是**类型校验 + 抛错语义**（异常消息含 `#0x` 十六进制 id 与 type）；
 * 取值本身由平台 API 完成。
 *
 * 平台差异：
 *  1. `Resources.getValue(resId, outValue, true)` / `Context.getTheme().resolveAttribute(...)`
 *     → 注入 `readValue(resId | attrId): TypedValueLike | null`。
 *     ArkUI **没有运行期主题属性解析**（`?attr/xxx` 在编译期解析成具体资源），
 *     故 `getAttr*` 系列在鸿蒙侧通常由调用方直接传具体资源值 —— 这里保留**校验逻辑**，
 *     让"传错类型"仍然抛错（而不是静默返回 0）。
 *  2. `TypedValue` → `TypedValueLike { type, data }`；`TYPE_FIRST_INT = 0x10`、
 *     `TYPE_LAST_INT = 0x1f`、`TYPE_DIMENSION = 0x05` 全部镜像为常量。
 *  3. `synchronized (mAccessLock)` → **不移植**（ArkTS 无 synchronized；已落地的做法是
 *     每次调用新建 TypedValue，避免共享可变状态 —— 见各方法注释）。
 *  4. `ResourcesNotFoundException` → 抛 `Error`，消息格式**逐字保留**（`#0x` + hex）。
 */

/** 上游 `TypedValue` 用到的两个字段（`type` 是资源类型，`data` 是原始值） */
export interface TypedValueLike {
  type: number;
  data: number;
}

export class ResourcesUtils {

  /** 上游 `TypedValue.TYPE_FIRST_INT` */
  static readonly TYPE_FIRST_INT: number = 0x10;
  /** 上游 `TypedValue.TYPE_LAST_INT` */
  static readonly TYPE_LAST_INT: number = 0x1f;
  /** 上游 `TypedValue.TYPE_DIMENSION` */
  static readonly TYPE_DIMENSION: number = 0x05;

  /** 对应上游 `getFloat(resources, resId)`：直接取 float 值（不做类型校验，上游也没有） */
  static getFloat(readValue: (resId: number) => TypedValueLike | null, resId: number): number {
    const v: TypedValueLike | null = readValue(resId);
    if (v === null) {
      return 0;
    }
    return v.data;
  }

  /**
   * 对应上游 `getAttrColor(context, attrId)`：**类型必须是 int 段（0x10..0x1f）**，否则抛错。
   * 注：上游复用 `mTmpValue` 减少分配；ArkTS 每次新建（不可变更安全，且这里不是热点路径）。
   */
  static getAttrColor(readAttr: (attrId: number) => TypedValueLike | null, attrId: number): number {
    const v: TypedValueLike | null = readAttr(attrId);
    if (v === null) {
      throw new Error('Attribute ID #0x' + attrId.toString(16) + ' not found');
    }
    if (v.type >= ResourcesUtils.TYPE_FIRST_INT && v.type <= ResourcesUtils.TYPE_LAST_INT) {
      return v.data;
    }
    throw new Error('Attribute ID #0x' + attrId.toString(16)
      + ' type #0x' + v.type.toString(16) + ' is not valid');
  }

  /** 对应上游 `getAttrBoolean`：同样要求 int 段，`data != 0` 为 true */
  static getAttrBoolean(readAttr: (attrId: number) => TypedValueLike | null, attrId: number): boolean {
    const v: TypedValueLike | null = readAttr(attrId);
    if (v === null) {
      throw new Error('Attribute ID #0x' + attrId.toString(16) + ' not found');
    }
    if (v.type >= ResourcesUtils.TYPE_FIRST_INT && v.type <= ResourcesUtils.TYPE_LAST_INT) {
      return v.data !== 0;
    }
    throw new Error('Attribute ID #0x' + attrId.toString(16)
      + ' type #0x' + v.type.toString(16) + ' is not valid');
  }

  /**
   * 对应上游 `getAttrDimensionPixelOffset`：**类型必须是 TYPE_DIMENSION(0x05)**，
   * 然后 `complexToDimensionPixelOffset(data, metrics)`。
   * 复杂值解码（`TypedValue.complexToDimensionPixelOffset`）属 Android 资源二进制格式 →
   * 注入 `complexToDimensionPixelOffset(data): number`，由 ui-widget/平台提供换算
   * （鸿蒙用 `px2vp`/`vp2px` 或 `resourceManager.getNumber`）。
   */
  static getAttrDimensionPixelOffset(readAttr: (attrId: number) => TypedValueLike | null,
    convert: (data: number) => number, attrId: number): number {
    const v: TypedValueLike | null = readAttr(attrId);
    if (v === null) {
      throw new Error('Attribute ID #0x' + attrId.toString(16) + ' not found');
    }
    if (v.type === ResourcesUtils.TYPE_DIMENSION) {
      return convert(v.data);
    }
    throw new Error('Attribute ID #0x' + attrId.toString(16)
      + ' type #0x' + v.type.toString(16) + ' is not valid');
  }
}