/*
 * 对位上游：app/src/main/java/com/hippo/unifile/RawFile.java
 *
 * ── 结构对位表（D-017 要求）─────────────────────────────────────────────────
 *   上游文件                    本文件（HarmonyOS）   实现体实际所在
 *   unifile/RawFile.java  →  unifile/RawFile.ets   →  unifile/UniFile.ets 中 `export class RawFile`
 *
 * 为什么实现体不在本文件：
 *   上游 Java 里 UniFile 是抽象基类，本类 `extends UniFile`；而 UniFile 的静态工厂
 *   （fromFile/fromUri…）又反过来 `new RawFile(...)` —— 形成「基类模块 ←→ 子类模块」双向 import。
 *   JVM 靠惰性链接容忍这种环；ArkTS（ESM 求值顺序）不行：子类模块求值到
 *   `class RawFile extends UniFile` 时基类绑定仍在 TDZ，直接抛
 *       ReferenceError: Cannot access 'UniFile' before initialization
 *   （真实复现见 MR !10「循环依赖复现」：两个互相 import 的 ESM 模块里执行 `class B extends A`
 *     即复现同一报错；ArkTS 与 ESM 同语义）。
 *   三选一后取「实现体集中到基类模块」：
 *     A) 基类下沉到 Contracts —— 类型面与上游错位，`f instanceof UniFile` 失效；
 *     B) `import lazy`（API 12+ 新语法）—— 本机整包构建当时不可用，无法验证，不赌；
 *     C) 实现体集中到 UniFile.ets（当前）。
 *
 * 本文件不是空壳占位：目标路径与上游一一对应（inventory 一字不差），
 * `import { RawFile } from '.../unifile/RawFile'` 的调用点形状不变，类本体在 UniFile.ets。
 */

export { RawFile } from './UniFile';
