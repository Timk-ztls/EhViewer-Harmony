/*
 * 对位上游：app/src/main/java/com/hippo/unifile/MediaFile.java
 *
 * ── 结构对位表（D-017 要求）─────────────────────────────────────────────────
 *   上游文件                      本文件（HarmonyOS）        实现体实际所在
 *   unifile/MediaFile.java  →  unifile/MediaFile.ets     →  unifile/UniFile.ets 中
 *                                                          `export class MediaFile`
 *
 * 为什么实现体不在本文件：ArkTS（ESM）无法承受「基类模块 ←→ 子类模块」双向 import +
 * 子类 `extends` 基类 —— 求值期抛 `ReferenceError: Cannot access 'UniFile' before initialization`
 * （真实复现见 MR !10）。上游 Java 靠 JVM 惰性链接规避。取舍与备选方案见 unifile/UniFile.ets 头注释。
 *
 * 本文件是同一模块的具名转出口：目标路径对位上游，import 形状不变，类本体在 UniFile.ets。
 */

export { MediaFile } from './UniFile';
