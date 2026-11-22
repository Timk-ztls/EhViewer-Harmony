# 模块单测约定（C-10 落地版，2026-10-24）

> 适用范围：`harmony/entry/src/test/<module>/`
> 沉淀自 storage-db 的实践；`requestpump` / `spiderinfo` / `spidenden` / `historyinfo` /
> `buffersink` / `archiveprovider` 共 **192 条断言**按此约定运行。

## 1. 目录与跑法

```
harmony/entry/src/test/<module>/
  run.ps1                 # 运行器（每模块一份，约定相同）
  xxx.test.ets            # 测试文件，文件名以 .test.ets 结尾
```

```powershell
pwsh -File harmony/entry/src/test/<module>/run.ps1            # 全量
pwsh -File harmony/entry/src/test/<module>/run.ps1 -Filter foo # 只跑 foo.test
```

## 2. 运行器做什么（照抄即可，别另发明）

1. 把 `src/main/ets` 与 `src/test` 整树镜像到临时目录，**只把 `.ets` 改名 `.ts`**
   —— 于是测试里的 `../../main/ets/hippo/...` 相对路径原样成立，**不改写任何 import**
   （改写规则一旦漂移，测试就测不到真实代码）。
2. **临时目录必须带 PID**：`storage-db-tests-<PID>`。两个 run.ps1 同时跑时若共用目录，
   会出现「A 删目录、B 正在 Copy」→ 镜像残缺 → tsc 报 `Cannot find module xxx`，
   看着像代码坏了。**storage-db 踩过一次，排查半小时。**
3. `shims.d.ts`：`@ohos.*` / `@kit.*` 的编译期声明（含类型位置，如 `fs.File`、`image.PixelMap`）。
4. `node_modules/<@ohos.xxx>/index.js`：运行时桩（`New-StubModule`），**必须在 `npm install` 之后建**
   —— npm 会 prune 掉 package.json 之外的 node_modules。
5. `node --require <test/shared/decorators.js> <out>.js`：补 `@Observed/@Entry/@Component`
   三个**恒等**装饰器（Node 没有 ArkTS 装饰器语义）。

## 3. 门禁口径（**必须写清楚，否则红绿都无意义**）

```
tsc 只对「本模块自己负责的包 + 测试文件」做门禁；
依赖链（其他模块 / SDK shim）的报错单独计数并打印「（依赖链 shim 缺失 N 条，不计入门禁）」。
```

理由：SDK shim 永远追不上平台 d.ts，把它的缺口计入门禁会让测试**永远跑不起来**；
而「红」和「绿」若不声明覆盖范围，本身就是一条测量陷阱
（CONTRIBUTING「H. 测量陷阱」第 6 条）。

## 4. 断言写法

- 自写 `eq/ok` 计数器（不引测试框架）：`eq(name, got, want)` 用 `JSON.stringify` 比对，
  失败时打印 `got/want`；末尾 `process.exit(1)`。
- **优先断言「不报错但行为错」的点**，而不是 happy path：
  - 持久化格式（文件名 `%08d`、文件头魔数、`spider_info` 字节布局）—— 错了就丢数据
  - 排序语义（自然序 `b1,b2,b10` vs 字节序 `b1,b10,b2`）
  - 失败分支（打不开文件 / 非法归档 / 越界 / 空条目）—— 上游都是「静默通知失败」
  - 「不该发生」的事（不该拷贝的字段仍是默认值、不该写入的字节数不变）
- **不要断言来自 SDK/资源的文案**（如 `GetText.getString('error_x')`）：Node 里没有资源管理器，
  断言它等于在测桩。改为断言**状态机与 index**这类真实数据。

## 5. 异步测试

CommonJS 下不允许 top-level await：把异步用例收进 `async function runCases()`，
`runCases().then(report).catch(e => { fails.push(...); report(); })`。

## 6. 假对象三原则

1. **假的是「模块边界」，不是「被测逻辑」**：假 `A7ZipBridge`（NDK 边界）、假 `GLRoot`（渲染边界）
   可以；把被测类的一半方法换成假的就不行。
2. **装饰器用恒等函数而不是模拟**：`@Observed` 的真实语义只在 ArkUI 运行时成立，
   Node 里模拟会引入被测代码没有的行为 → 测试就不再测真代码。
3. **能力开关尽量做成构造参数并给生产默认值**（如 `BufferSink(limit = MAX_BUFFER_BYTES)`）：
   既能测「超限抛错」，又不改变生产行为。

## 7. 共享文件

| 文件 | 用途 |
|---|---|
| `test/shared/decorators.js` | ArkTS 装饰器恒等桩，任何模块 `node --require` 即可 |
