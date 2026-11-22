// runtime-shims.js —— 宿主跑单测时的运行期垫片
//
// 两件事：
//   1. ArkTS 装饰器（@Observed/@Entry…）在 tsc emit 后是**普通函数调用**，
//      只在 shims.d.ts 里 declare 只能过类型检查，运行时必须提供空实现。
//   2. **@ohos.* / @kit.* 模块的兜底**：被测文件往往顺着依赖链 import 到整个应用层
//      （EhDB → DaoSession → 各 Dao → MSQLiteBuilder → @ohos.data.relationalStore →
//      …、@ohos.i18n …）。逐个枚举 stub 是打地鼠（实测每跑一次就冒出一个新的）。
//      这里改用 Module._load 兜底：只有真正 MODULE_NOT_FOUND 且名字是 @ohos/@kit 时，
//      返回一个"万能代理"（任何属性访问/调用/构造都返回自身）。
//      显式 stub（node_modules 里真实存在的）优先，兜底只补没写的。
//
// 注意：兜底**只用于宿主单测**，语义是"这个平台 API 在本测试里不参与断言"，
//       不能当成"实现正确"的证据。真实行为由 build_hap.ps1 + 真机负责。

const passthrough = (t) => t;
const noopDecorator = () => () => {};

globalThis.Observed = passthrough;
globalThis.Entry = passthrough;
globalThis.Component = passthrough;
globalThis.ComponentV2 = passthrough;
globalThis.Reusable = passthrough;
globalThis.Builder = passthrough;
globalThis.Build = passthrough;
globalThis.Style = passthrough;
globalThis.Extend = passthrough;
globalThis.Concurrent = passthrough;
globalThis.CustomDialog = passthrough;
globalThis.Sendable = passthrough;
globalThis.LocalStorageLink = noopDecorator;
globalThis.LocalStorageProp = noopDecorator;
globalThis.StorageLink = noopDecorator;
globalThis.StorageProp = noopDecorator;
globalThis.Provide = noopDecorator;
globalThis.Consume = noopDecorator;
globalThis.Watch = noopDecorator;
globalThis.State = noopDecorator;
globalThis.Prop = noopDecorator;
globalThis.Link = noopDecorator;
globalThis.ObjectLink = noopDecorator;
globalThis.Require = noopDecorator;
globalThis.Track = noopDecorator;
globalThis.Monitor = noopDecorator;

// ---------------------------------------------------------------------------
// @ohos.* / @kit.* 缺失兜底（递归代理：属性访问 → 自身；调用/构造 → 自身）
// ---------------------------------------------------------------------------
function makeUniversalStub() {
  const proxy = new Proxy(function stub() {
    return proxy;
  }, {
    get(t, prop) {
      if (prop === 'then') {
        return undefined;          // 别把自己当 thenable，否则 await 会挂
      }
      if (prop === Symbol.toPrimitive) {
        return () => 0;
      }
      if (prop === 'toString' || prop === 'valueOf') {
        return () => '';
      }
      return proxy;
    },
    apply() {
      return proxy;
    },
    construct() {
      return proxy;
    }
  });
  return proxy;
}

const Module = require('module');
const originalLoad = Module._load;
const PLATFORM_SPEC = /^@(ohos|kit)[./]/;

Module._load = function load(request, parent, isMain) {
  try {
    return originalLoad.call(this, request, parent, isMain);
  } catch (e) {
    if (e && e.code === 'MODULE_NOT_FOUND' && PLATFORM_SPEC.test(request)) {
      if (!globalThis.__platformStubLog) {
        globalThis.__platformStubLog = new Set();
      }
      if (!globalThis.__platformStubLog.has(request)) {
        globalThis.__platformStubLog.add(request);
        process.stderr.write(`[runtime-shims] 平台 API 兜底（不参与断言）: ${request}\n`);
      }
      return makeUniversalStub();
    }
    throw e;
  }
};

// ---- $r / $rawfile 资源桩（ui-scene 首例需要）----
// ArkUI 的 `$r('app.string.x')` 在 Node 里不存在。桩成**恒等函数**（返回入参字符串），
// 而不是返回 {} —— 这样"资源键当字符串比较"的断言才成立；
// 返回 {} 会让比较静默变成 "[object Object]"，反而掩盖问题。
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
