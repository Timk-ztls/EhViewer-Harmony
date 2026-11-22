/*
 * 共享的 ArkTS 运行时桩（供各模块 `harmony/entry/src/test/<module>/run.ps1` require）
 *
 * 背景：`@Observed` / `@Entry` / `@Component` 是 **ArkTS 编译器**处理的装饰器，
 * tsc 侧只有 d.ts 声明（我的 shims.d.ts 里那三行），**Node 运行时并不存在**。
 * 于是任何 import 到 `@Observed` 类（`GalleryInfo` 及其 4 个 DAO 实体全是）的测试，
 * 都会在 require 阶段抛 `ReferenceError: Observed is not defined` —— 报错点还落在被测模块里，
 * 看起来像被测代码坏了，实际是测试基础设施缺一层。
 *
 * 用法（在 run.ps1 里）：
 *   node --require <此文件绝对路径> <编译后的测试入口.js>
 *
 * 三个装饰器都必须是**恒等函数**：
 *   - `@Observed` 的语义（把实例包成可观察对象）只有在 ArkUI 运行时里才成立，
 *     Node 里做任何"模拟"都会引入被测代码没有的行为；恒等函数保证类的构造/字段赋值路径
 *     与生产环境**完全一致**，测试才测的是真代码。
 */

'use strict';

/** 把 ArkTS 的类装饰器补成恒等函数（Node 无语义，只求不抛）。 */
function identityDecorator(target) {
  return target;
}

if (typeof globalThis.Observed === 'undefined') {
  globalThis.Observed = identityDecorator;
}
if (typeof globalThis.Entry === 'undefined') {
  globalThis.Entry = identityDecorator;
}
if (typeof globalThis.Component === 'undefined') {
  globalThis.Component = identityDecorator;
}

/*
 * `$r()` / `$rawfile()`：ArkUI 的**资源引用函数**，Node 运行时不存在。
 * 菜单定义（`ui/menu/*.ets`）与布局里大量出现 `$r('app.string.x')`，
 * 任何 import 到它们的测试都会在 require 阶段抛 `ReferenceError: $r is not defined`。
 *
 * 桩成**恒等函数**（返回入参字符串）而不是返回 `{}`：
 *   - 被测代码若把资源引用当字符串比较（如 `getMenu()` 的 title 字段），恒等返回才能保持比较语义
 *   - 返回 `{}` 会让"字符串拼接/比较"静默变成 "[object Object]"，反而掩盖问题
 * 生产环境仍由 ArkUI 解析真实资源；这个桩只在 Node 单测里生效。
 */
if (typeof globalThis.$r === 'undefined') {
  globalThis.$r = function $r(resource) {
    return resource;
  };
}
if (typeof globalThis.$rawfile === 'undefined') {
  globalThis.$rawfile = function $rawfile(name) {
    return name;
  };
}