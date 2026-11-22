| **D-056** | `glrenderer/MultiLineTexture.java`(44) —— 多行文字纹理，上游用 `StaticLayout`（Android 断行引擎） | **断行自行实现（按字符），登记为近似** | **做法**：在 `@ohos.graphics.drawing` 之上自行断行，不引入 `@ohos.graphics.text` 的第二套文字栈 —— 显式 `\n` 分段 + 超宽行按**字符**折行；行高 = `FontMetrics.descent - ascent`；基线 = `i * lineHeight - ascent`；三种对齐按行宽算 x 起点。<br>**与上游的可见差异**：上游按**词**断行，西文长词会**整词下移**；本项目按字符断，西文长词可能在**词中断开**（CJK 无差异）。<br>**触发条件**：当前用该纹理的是错误文案（中英混排短句），差异不可见；若出现长西文文案（连续 > 20 字符无空格），改走 `@ohos.graphics.text` 的 `Paragraph`（届时本条降级为"已修复"）。<br>**为什么允许**：① 只为断行引入第二套文字 API，会让字号/度量/字形三处口径分叉（D-031 已经因为 `Typeface` 无族名构造受限）② `drawing` 与 `text` 两套栈的 `Font` 不共享缓存 | gl-render |
# 平台差异裁决记录（DEVIATIONS）

> 规则：**只有 Lead 能写本文件。**任何与上游 Android 行为不一致的实现，必须在此登记并说明理由；未登记的差异视为缺陷。
> 裁决人：用户（2026-10-24 逐项确认）。状态：`已裁决` / `已实现` / `待实现`

## 用户裁决（8 项，2026-10-24）

| # | 上游行为 | 鸿蒙平台限制 | 裁决结果 | 状态 |
|---|---|---|---|---|
| **D-001** | 包名由 `applicationId` 决定 | HarmonyOS `app.json5` `bundleName` 配置 | **`bundleName = com.ehviewer.harmony`**（开源分支默认包名，可在 `app.json5` 与签名 profile 保持一致的前提下按需修改） | 已裁决·已落地 |
| **D-002** | WiFi 直连传书：`WifiServerService` 反射 `WifiManager` 建热点 + `WifiClient` 扫描连接 | 三方应用无热点创建 API（`@ohos.wifiManager` 只暴露状态查询与连接） | **方案 A**：降级为「同一局域网 HTTP 传书」——本机起 HTTP 服务 + 二维码/手填 IP，移除热点创建与自动连接 | 已裁决·待实现 |
| **D-003** | `AppUpdater.kt` 下载 APK 后 `ACTION_INSTALL_PACKAGE` 安装 | 三方应用不能安装 HAP，必须经系统/应用市场 | **方案 B**：**删除 `updater` 模块**，`VersionPreference` 应用内更新入口一并移除 | 已裁决·已落地 |
| **D-004** | 7z 归档解压（`a7zip_XJ` 依赖） | 鸿蒙无现成 7z 库 | **方案 A**：NDK 编译 LZMA SDK / 7-Zip C 源 + NAPI 封装，与 `cpp/` 同构建体系 | 已裁决·待实现 |
| **D-005** | `Conscrypt` 自定义 TLS Provider | 系统网络栈固定，不可替换 Provider | 删除 `conscrypt-android`，TLS 参数走 `@ohos.net.http` 的 `HttpRequestOptions` | 已裁决·无行为影响 |
| **D-006** | Firebase Crashlytics + Analytics 上报 | 鸿蒙无 GMS | **方案 A**：移除依赖与初始化，崩溃日志落本地文件 | 已裁决·待实现 |
| **D-007** | 阅读器自绘 OpenGL 栈（`glview` 67 文件 / 14.8k 行） | 无 `GLSurfaceView`，但有 `XComponent` + native EGL/GLES3 | **方案 A**：`XComponent` + NDK EGL/GLES3 重写，保留 `GLCanvas/GLES20Canvas/Texture` 结构（Stage C P5 已落地 `GalleryReaderPage` 切接 + Watchdog/3 次错误自动回退 ArkUI `Swiper`） | 已裁决·已落地 |
| **D-008** | 安装包装载于零售机 | 本机 SDK 20 缺 `hms` 组件，`HmosSdkLoader` 报 `SDK component missing` | **方案 A**：`runtimeOS: "OpenHarmony"` + `compileSdkVersion: 20` 编译（已验证 BUILD SUCCESSFUL）；上架前再补 DevEco all-in-one 环境切回 `HarmonyOS` | 已裁决·已落地 |
| **D-009** | — | HarmonyOS 应用签名机制 | 仓库不提交私钥与 `.p7b` 签名材料；本地调试请使用 DevEco Studio 自动签名或自备签名证书 | 已裁决·已落地 |

## D-007 的"1:1"技术口径

"1:1"指**功能与交互对齐**，不承诺像素级相同：

- **承诺**：功能 100% 对齐（翻页/双页/双击缩放/长按/预加载/预解码/坏图重试/进度回调/纹理回收）；交互常量直接搬上游数值（Fling 阻尼、滚动摩擦、缩放曲线）
- **不承诺**：像素级一致。唯一系统性差异源是**文字纹理**（`StringTexture`/`MultiLineTexture`/`MovableTextTexture`/`ImageMovableTextTexture`）——上游用 Skia 的 `FontMetricsInt` 算基线，鸿蒙字体引擎不同，同字号下基线可能差 1–2 px
- **验收方式**：双端同页截图对比（差异像素比例阈值 + 人眼复核），不是"看起来一样"

## 依赖面实测（支撑 D-007 可行性）

| Android API | 引用次数 | 鸿蒙侧 | 难度 |
|---|---:|---|---|
| `android.opengl.GLES20/GLUtils/Matrix` | 9 | NDK GLES3 / 自实现 GLUtils | 直接等价 |
| `javax.microedition.khronos.egl.*` | 10 | native EGL + XComponent 回调 | 直接等价 |
| `android.graphics.Bitmap` | 17 | `PixelMap` | 直接等价 |
| `Rect`/`RectF`/`Color`/`Matrix` | 40 | 自写值对象 | 直接等价 |
| `MotionEvent` | 7 | `TouchEvent` | 直接等价 |
| `Canvas`/`Paint`/`Typeface`/`FontMetricsInt`/`TextPaint` | 17 | ArkUI Canvas / native 字体栈 | **中等风险** |

风险分级：`GLCanvas/GLES20Canvas/GLES11Canvas`(3) 低 · `Texture` 体系(14) 低 · 文字纹理(4) 中 · `GLRootView/GLView`(8) 中 · `glgallery` 手势(10) 低。

## 变更留痕

| 日期 | 变更 | 依据 |
|---|---|---|
| 2026-10-24 | 初始 6 项（WiFi/自更新/7z/Firebase/bundleName/渲染路线） | 方案 §7 |
| 2026-10-24 | 用户逐项裁决 8 项；自更新由"保留入口"改为**删除模块**（D-003） | 用户回复 |
| 2026-10-24 | 新增 D-008（SDK 路线）、D-009（签名时效） | 构建实测发现 |

## 成员实施中确认的平台差异（Lead 逐条签字）

| # | 差异 | 决定 | 影响面 | 登记来源 |
|---|---|---|---|---|
| **D-012** | `@ohos.data.relationalStore` 无同步 API（只用 Promise/callback），上游 GreenDAO 全同步 | **DAO 全层 async**：方法名/参数不变，返回 `Promise<T>`，调用方加 `await`。不采用 TaskPool+SharedArrayBuffer+Atomics 伪造同步（会阻塞 UI 线程，违反 §5-⑩） | storage-db / download-sync / ui-scene / core-runtime(EhDB) | storage-db |
| **D-013** | 实体 `Parcelable`（CREATOR/writeToParcel）在 ArkTS 无对位 | **去除 Parcel**，保留字段与 getter/setter、保留 `toJson/fromJson`；页面路由参数改 `Record<string, Object>` | storage-db | storage-db |
| **D-014** | `LongIdGenerator`、`Messenger` 上游**全仓 0 外部引用** | 标 `na`（**因上游死代码，非平台限制**），notes 必须写明"0 引用，属死代码"。与"因平台限制 na"在验收时性质不同，报表单列 | core-runtime | core-runtime |
| **D-015** | `OSUtils.getAppMaxMemory()` 用 `Runtime.maxMemory()` | **标 `TODO(platform)`**，返回 `-1` 并注释"鸿蒙无 heap 上限概念"；调用点 2 处（`Crash.java:117`、`EhApplication.java:551`）须对 `-1` 有处理 | core-runtime | core-runtime |
| **D-016** | `SparseILArray/SparseJLArray` 的 `gc()/clear()` 上游写 `null` 释放引用 | ArkTS 泛型数组写不进 `null`，只清 `boolean[] mDeleted` 标记位。**行为一致，GC 释放时机不同**：数组重建（`CollectionUtils.insert/append` 扩容）才真正释放，滞留上限 = capacity | core-runtime | core-runtime |
| **D-017** | `unifile` 的 `RawFile/SingleDocumentFile/TreeDocumentFile/MediaFile` 四个文件改为"结构对位转出口" | ArkTS ESM 在"基类模块 ←→ 子类模块"双向 `import` + `extends` 下会触发求值期 TDZ（JVM 惰性链接规避了此问题）。实现体集中于 `UniFile.ets`，目标路径与 import 形状不变 | storage-db | storage-db |
| **D-018** | `Utilities.getExtensionFromMimeType` 依赖 `android.webkit.MimeTypeMap`（系统 600+ 条） | 内置 17 条覆盖 EhViewer 实际用到的类型，未知返回 `undefined`（**能力降级**）。要求调用方有 fallback，不许强解包 | core-runtime | core-runtime |

## 评审口径：`na` 的两种性质

验收报表必须分开统计，不能混为一谈：

| 类型 | 含义 | 例 |
|---|---|---|
| `na`（死代码） | 上游自身没有调用方，移植了也永远不执行 | `LongIdGenerator`、`Messenger` |
| `na`（平台删除） | 上游有调用方，但平台物理上做不到，经用户裁决删除 | `AppUpdater`（D-003） |

| **D-019** | `lib/image/ImageBitmap.kt`（335 行）与 `ImageDrawable.kt`（88 行）上游**整体被注释掉**，有效代码 0 行，无编译产物、无调用点 | 保留同名文件与 target_path，**不造空壳类**（会引入上游不存在的类型污染 API）；原设计以文件头文档保留，提供 `imageBitmapNotAvailable()` 使误引用立刻暴露 | 覆盖率报表中这 2 条标注为"死代码 ported"，不计入"功能等价"统计 | storage-db |
| **D-020** | `lib/image/Image1.kt` 是 16 个 JNI `external fun`（nativeDecode/nativeRender/nativeTexImage/nativeClahe/nativeGetDecoderDescription…） | 定义 `LibImageBridge` 接口由 **native-image** 通过 NAPI 注入（`Image1.setBridge()` / `Image.setTexImageBridge()`），**未注入时抛错**（不是空实现）。接口签名即 NAPI 契约（Stage C P5 已新增 `NativeLibImageBridge.ets` 并在 `AppWiring.ets` `⑥f` 完成真实注入，`libimage-bridge.test.ets` 26 断言验证） | native-image 需在 `libnative-lib.so` 暴露同名 16 个方法（已接入并单测验证） | storage-db ↔ native-image |

| **D-021** | `GalleryInfo.toCSV/fromCSV` 用 `,` 分隔，而 `simpleTags` 渲染成 `"[a, b]"` **本身含逗号** → 多标签条目两端都无法往返（`fromCSV` 字段数错位 → 数字解析失败 → 返回 null） | **按 1:1 保留上游缺陷**（`Arrays.toString` 的行为），在测试里显式断言 `csv 多标签往返失败(与上游一致)`。影响面：下载记录的 CSV 备份/恢复对多标签条目会丢数据 | 若 P6 验收发现用户实际依赖 CSV 备份，再评估是否修正（修正=偏离上游） | net-parse |

| **D-022** | `com.hippo.easyrecyclerview`（外部库 `EasyRecyclerView` / `FastScroller`）**不移植**，`ContentLayout` 改用原生 `Refresh` + `List` + `onReachEnd` | `ContentHelper` 的 7 态状态机 + 4 个 `GOTO_*` **按 1:1 保留**（只换渲染层）；快速滚动条不实现 | **影响**：1000+ 项的长列表（历史/收藏）没有拖拽快速定位，只能用滚动条或搜索。**回退条件**：P5 验收若判定"长列表没法用"（而非"不如原生"），补最小 FastScroller（约 200 行，只做拖拽 + 索引气泡） | ui-widget |

| **D-023** | `ui/annotation/{DrawerLifeCircle,ViewLifeCircle,WholeLifeCircle}` 三个 **FIELD 级注解**（`@Target(ElementType.FIELD)`，Java 侧靠注解处理器/反射识别字段并在生命周期结束点置 null） | 落地为**显式作用域持有者**：`ScopedDrawerField<T>` / `ScopedViewField<T>` / `ScopedWholeField<T>`（懒建 + `get()` + `reset()`）。`SceneFragment` 增加 `trackDrawerScope/trackViewScope/trackWholeScope` 三个注册点 + `resetScopes`，分别在 `onDrawerClosed()` / `onSceneViewDestroyed()` / `onSceneDestroyed()` 里统一 reset。**ArkTS 无注解体系，`instanceof` 也不能判 interface**，故用"基类持有列表 + 子类注册"（编译期可查错，不用反射/不用 try-catch） | 用法从 `@ViewLifeCircle private View mAccept;` 变为 `private mAccept = new ScopedViewField<Xxx>(() => new Xxx());` + `this.mAccept.get()`。语义等价（字段随生命周期失效），形态从"声明式标记"变"显式持有" | ui-scene |

| **D-025** | `GalleryListParser` 解析完成后调用 `GalleryListTagsSyncTask.execute()` 同步标签入库（副作用），该任务属 download-sync 的 `sync` 包 | net-parse 侧定义 `TagSyncHook` 接口 + **默认实现打 `console.warn` 后返回**（不静默），download-sync 实现并注入。**这是行为缺失而非等价**：标签同步链在注入前是断的 | **影响**：列表页解析后标签不会自动入库，需等 download-sync 接线；浏览功能本身不受影响（标签同步是后台优化）。**验收项**：P6 集成时必须确认 `TagSyncHook` 已注入 | net-parse ↔ download-sync |

| **D-026** | 上游 `GestureRecognizer` 直接委托 `android.view.GestureDetector` + `ScaleGestureDetector`；鸿蒙**没有等价物** | 自实现：单击/单击确认（tap 100ms、confirmed 300ms）、双击（300ms + slop）、长按（500ms）、fling（min 50dp/s、max 8000dp/s、min distance 50dp）、**双指 scale span 判定**（minSpan/spanSlop/quickScale）。常量按 **AOSP 原值硬编码** + `LayoutUtils.dp2pix` 换算，整表写进 MR | 验收口径："与上游同常量的行为对齐"，不是像素级。风险：`ScaleGestureDetector` 的 span 判定算法未公开全部细节，双指缩放的手感可能与此上游有细微差异 | gl-render |

| **D-027** | 上游 `Analytics` 三个方法全依赖 Firebase（`FirebaseAnalytics` / `FirebaseCrashlytics`），鸿蒙无 GMS，AGC Analytics 是另一套 SDK | 降级为本地实现：`recordException` → `hilog.error`（保住崩溃栈本地可查）；`start`/`onSceneView` 空实现保留签名（调用点零改写）；`isEnabled` 恒 `false` | **能力损失**：无远端埋点、无远端崩溃聚合。**不接 AGC 的理由**：需 appId + 隐私合规声明，且 `recordException` 在崩溃现场本身可能不可用 → 接了也不可靠 | core-runtime |
| **D-028** | 上游 `IoThreadPoolExecutor` 是 Kotlin `ThreadPoolExecutor`(3 core / 32 max / 1s) + 自定义队列（`allWorkingThreads < poolSize` 才排队）+ `PutRunnableBackHandler`（拒绝时 `queue.put` 阻塞） | ArkTS 无自建线程池 → 改为"最多 4 个并发 + 其余排队 + 永不拒绝"的异步任务队列（`execute(task: () => Promise<void>)`） | **保留**排队与回压语义（自定义队列的全部意义）；**丢掉** 32 线程。**使用约束**：task 必须是异步的，重 CPU 同步任务应交给 `taskpool`（真并行） | core-runtime |

| **D-029** | **死代码判定口径**（本条为规则，非单文件处置） | 死代码标 `na`、**不做空壳**（空壳会占 `ported` 行让覆盖率虚高） | **判据必须是「引用数 = 0」**，不是「我看到的文件内容」。已确认的死代码：`LongIdGenerator` / `Messenger`（0 引用）、`ImageBitmap` / `ImageDrawable`（整体注释）。**反例警示**：`CookieSet` 曾被误判为死代码（实际被 `CookieRepository`/`CookieDatabase` 引用 10 处，文件里的 `/* */` 只是 javadoc）—— 判定必须 `grep` 引用，不能靠肉眼扫描或过滤后的输出。最终验收：`(ported - 死代码) / (总数 - 死代码 - 平台删除)` | 全员 |

| **D-030** | 上游 `OkHttp` 的 `ResponseBody.byteStream()` 支持**流式**读（`byte[1024*4]` 循环写盘，峰值内存 4KB） | ArkTS 侧 `ResponseBody.ets` 内部是 `ArrayBuffer`（只有 `bytes()/string()`，**无 byteStream**）→ 响应体先在内存完整落地，再按 4KB 切片**回放**写完盘 | **进度粒度保住**（每 4KB 一次 `notifyProgress`，10MB ≈ 2500 次，进度条不跳变）；**代价是峰值内存 = 完整对象大小**（10MB 图 = 10MB buffer 常驻 + 写盘期间双份）。**影响面**：`SpiderDen` 下载大文件时的内存曲线与上游不同；大归档（>100MB）可能 OOM。**验收项**：P5 需实测 200MB 压缩包下载的峰值内存 | core-runtime ↔ storage-db |

| **D-032** | 上游 `android:padding`/`margin` 可来自 `style=` 的继承链（`styles.xml` → 父 style → 属性） | 布局转换脚本**不解析 `style=` 继承链**，只读元素自身的 `padding*`/`margin*` 属性 | **影响**：用 `style=` 承载间距的布局（本项目 25 个里有 10 个）转换后**无 padding/margin 输出**，需人工补。**为什么不自动解析**：需要递归展开 `styles.xml` 的 parent 链 + 区分 `android:` 命名空间属性，复杂度远高于收益（10 个布局，人工补一次即可） | ui-scene / native-image |

| **D-033** | 上游 21 个 Preference 类（`preference/*` 14 个 + `hippo/preference/*` 7 个，共约 1800 行）是 **Android 的 Preference UI 框架**（`extends Preference` 即自动获得标题/摘要/点击/对话框） | ArkTS 无 `Preference` 类体系 → **拆两层**：`preference/*` 的**纯逻辑**归 core-runtime（`getVersionName` / `signOut` / 清理算法 / 数据组装），**UI** 归 ui-widget 用 ArkUI 原生组件表达；`hippo/preference/*` 7 个框架类**整体划给 ui-widget**（S0445–S0451） | **验收口径**：设置页的**每一项功能可用 + 文案一致**；**不承诺**内部类结构一致。这是本项目里"平台无对应概念"的最大一处改写——**硬按类移植只会产出空壳或造一个假的 Preference 框架，那才真正违背 1:1** | core-runtime ↔ ui-widget |

| **D-036** | `com/hippo/text/Html.java`(969) 是 **`Spanned` 编解码器**（`fromHtml: String→Spanned` / `toHtml: Spanned→String`），`fromHtml` 内部用 **TagSoup 的 `Parser` + `HTMLSchema`**（外部 jar 的 schema 数据）；输出类型 `Spanned`、`ImageGetter` 的同步 `Drawable` 在鸿蒙**无对应物** | **只移植纯字符串部分**：`toHtml` / `escapeHtml` / `withinHtml` / `withinStyle` / `withinParagraph`（约 250 行，可 1:1 + 可运行时断言）；**`fromHtml` 不移植**，UI 层用 ArkUI 的 `RichText` / `StyledString` 直接渲染 HTML 字符串 | **失去**"HTML → Spanned 再回写"的往返；**保留**评论/简介的回写能力（那是 `toHtml` 的调用点）。**不在 ArkTS 重写 TagSoup**（等于重写 HTML 解析器 + 内置 300+ 条 schema，无测试基准）；**不造假的 `Spanned`** —— 那才是真正违背 1:1 | core-runtime ↔ ui-widget |

### 编号说明（补记跳号）

`D-010` / `D-011` / `D-024` / `D-031` / `D-034` / `D-035` 未单独成条：这些位置在讨论中被合并进相邻条目或转为非差异项（如 `onMemoryLevel` 精确映射后**不再是差异**，已从清单移除）。**编号不重排** —— 保持既有引用有效。

**当前有效差异：27 项**（`D-001~009` / `D-012~023` / `D-025~030` / `D-032~033` / `D-036`）。

| **D-037** | 上游 `gradle.properties`(48 行)：`android.useAndroidX` / `android.enableJetifier` / `org.gradle.jvmargs` / `android.nonTransitiveRClass` 等 | **不建等价文件，`status=na`** | 全部是 **Gradle 构建期开关**，hvigor 无对应配置项；硬造一个空 `gradle.properties` 是假实现。**语义等价物**：`harmony/build-profile.json5` 的 `buildOption` + `harmony/local.properties` 的 SDK 路径 | lead |
| **D-038** | 上游申请 `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` / `MANAGE_EXTERNAL_STORAGE` 直接读写 `/sdcard/EhViewer/` | **不申请**，改沙箱 + `DocumentViewPicker` | **影响**：下载目录固定在沙箱（`context.filesDir` 或 `Download` 目录）内；用户选择**外部目录**时通过 Picker 授权（单次/长期授权，非全局权限）。`MANAGE_EXTERNAL_STORAGE` 属高危权限且应用商店会拒。**验收项（P5）**：需验证"下载到用户选定的外部目录"这条路径 | lead |

| **D-042** | storage-db 的 review 认为 `GLRootView.requestLayoutContentPane:198` 在未初始化时"请求永久丢失"（建议加 `FLAG_NEED_LAYOUT_PENDING` 标记） | **不改**（上游 L221 逐字相同） | **证据**：① 上游 `mFlags` 初值即 `FLAG_NEED_LAYOUT` ② `onSurfaceCreated()` 之后会再请求一次 ③ 单测 `glrootlayout.test.ets` 证明初始化后仍可渲染。**"pending 标记"是有效改进**（会多触发一次 layout），但属于**行为增强而非缺陷修复**，按 D-039/D-041 先例不擅自改 | net-parse |

| **D-043** | `util/DataUtils.copy(Parcelable)` 是「用 `Parcel` 做**泛型深拷贝**」的封装（`writeParcelable` → `setDataPosition(0)` → `readParcelable`），唯一调用点是 `GalleryDetail.getNewGalleryDetail(index)` L143 | **`status=na`**（不实现） | **ArkTS 无 `Parcelable`、无反射 → 泛型深拷贝不可能**。**且它不需要实现**：唯一调用点只需 `GalleryDetail` 的**显式逐字段 copy**（字段已知），由 `GalleryDetail.copy()` + `getNewGalleryDetail(index)` 承担（net-parse 负责）。**不是"调用方各自 clone"** —— 只有一个调用方，且该方法是 `GalleryDetail` 自己的方法 | core-runtime / net-parse |

| **D-044** | 上游 `DownloadsScene.updateForLabel()` 里 **`filterByCategory()` 被注释禁用（L312）** | 12 个 `filter_by_category_*` 菜单项**保持未接线**（与上游一致） | **与上游保持一致**：`getUnhandledMenuIds()` 会列出它们但未接实际筛选逻辑（这 12 项点击无反应与上游行为一致） | storage-db |

| **D-045** | 缓存层（`DiskLruCache` / `SimpleDiskCache` / `Util`）47 处「三因一果」：`键不存在`（正常）/ `未初始化`（配置问题）/ `IO 失败`（真错误）**共用同一个 `boolean`/`null`** | **暂缓**（终版验收后做独立专项） | **不改三态**（上游就是 `boolean`，改了破坏 1:1 + 所有调用点都要改）；**但至少在 IO 失败分支补 `warn`**，让"真错误"与"没缓存"在日志里可分辨。预估 ~2h，塞进收尾会拖慢进度。**优先级低**（不影响功能，只影响可诊断性） | storage-db |

| **D-046** | `JumpDateSelector.init` 里 `monthOfYearSelected = calendar.get(Calendar.MONTH)`（**0 基，未 +1**），而 `onDateChanged` 里是 `monthOfYearSelected = monthOfYear + 1`（**1 基**）。⇒ **用户不碰日期、直接点"跳转"时，`seek=` 的月份比实际少 1**（10 月 → 发出 `seek=YYYY-9-DD`）；拨动一次日期后恢复正常 | **修**（`init` 里也 `+1`） | **属陷阱 63 的 D 类（结果错，非显示错）**：`seek=` 是**服务端参数**，错一个月意味着跳到错误的时间段 —— **不是显示错，是结果错**。且**默认操作路径就触发**（改一次日期就再也复现不了，测试掩护）。修复后两条路径结果一致，不影响任何 API 契约。**这是本项目第一处"主动修复上游 bug 并与上游不一致"的条目** | ui-widget |

| **D-048** | `NinePatchTexture.SmallCache.get` 在**前移 swap 之后** `return mValue[i]` —— 那时 `mValue[i]` 已是「被换位上来的邻居」，不是命中的值。**缓存命中时可能返回另一个尺寸的实例 → 用错尺寸绘制** | **修**（先取 `hit` 再 swap，最后 `return hit`） | **属陷阱 63 的 D 类（结果错）**：不是显示位置偏了，是**画出来的 nine-patch 尺寸错**。触发条件：`mCount > CACHE_SIZE/2(8)` 且命中项非第 0 项 —— 常见页面尺寸种类少，上游一直没暴露。**这是本项目第二处主动修复上游 bug**（第一处 D-046 `JumpDateSelector` 月份）。修复不改任何对外接口，仅调整 `get` 内部的取值时机 | net-parse |
| **D-049** | `glrenderer/GLES11Canvas.java`(904) —— OpenGL ES 1.1 固定管线画布（`glMatrixMode` / `glVertexPointer` / `glEnableClientState`） | **`status=na`（平台删除）** | **三条独立证据**：① 上游 `GLRootView` 只在 `mEGLContextClientVersion != 2` 时才 `new GLES11Canvas`（2013 年老硬件兜底，不是功能路径）② 鸿蒙侧 `GLRootViewController.ets:170` **无条件** `new GLES20Canvas()`，全仓零引用 `GLES11Canvas` ③ `GLNativeBridge.ets` 的命令集**没有** `glMatrixMode`/`glLoadMatrixf`/`glEnableClientState`/`glVertexPointer`，只有 ES2 用法 —— **即使逐字翻译 904 行也没有 API 能画出东西**。删除安全：`GLCanvas` 抽象类的唯一实现是 `GLES20Canvas`（已交付/已测/被 RootViewController 使用），所有渲染类只依赖接口，鸿蒙设备均支持 ES3.0。**落地为判定记录文件**（与 `network/TlsPlatform.ets` 同形态）：文件头写三条证据 + 影响评估 + 「若将来要恢复需要什么」，文件体只有 `GLES11_CANVAS_PLATFORM_DELETED = true` | net-parse |
| ~~**D-050**~~ | ~~`ImageView.setScaleOffset()` 的 `SCALE_FIT` 分支内层 `break`~~ | **已撤回（2026-10-25）** | **判断错误，上游无缺陷。** 我把「跳出 switch」误当成「跳过 switch 之后的代码」。上游 `ImageView.java:391-411` 的结构是 `switch (scaleMode) { case SCALE_FIT: ... else { ...; break; } break; }` —— **那个内层 `break` 绑定的是 switch，不是 else**；switch 之后的 L413-458（钳制 / 设 `mDst` / `adjustPosition()` / `mScaleOffsetDirty = false`）在两条分支上**都会执行**。最小复现：`switch(3){case 3:{if(a<b){…}else{…break;} break;}} dirty=false;` → 两条路结果相同。**是 `net-parse` 自己用变异测试发现并主动纠正的**（把 break 加回去测试仍全绿 → 原来两者行为本来就一样）。上游那个 `break` **原样保留**，注释写明「与后一个 break 语义等价、非缺陷」；单测同时钉住两条分支的可观测结果一致，防将来被当 bug 删掉。教训见陷阱 112 | net-parse（自纠） |
**D-033 补充裁决（2026-10-25，ui-widget 提出、Lead 核实后采纳）**

原裁决「14 个纯逻辑归 `PreferenceActions`，7 个框架类归 ui-widget」被误用成了「`Preference` 子类行整体归 core-runtime」。**逐一核对上游基类后更正**：

| id | 类 | 上游基类 | 性质 |
|---|---|---|---|
| S0165 | `ClearDownloadPathCachePreference` | `extends MessagePreference` | **UI** |
| S0166 | `DefaultCategoryPreference` | `extends DialogPreference` | **UI** |
| S0167 | `ExcludedTagNamespacesPreference` | `extends DialogPreference` | **UI** |
| S0168 | `ExportDataPreference` | `extends TaskPreference` | **UI** |
| S0170 | `ProxyPreference` | `extends DialogPreference implements OnClickListener` | **UI** |
| S0172 | `SignInRequiredActivityPreference` | `extends ActivityPreference` | **UI** |
| S0173 | `SignOutPreference` | `extends MessagePreference` | **UI** |

**7 个全是 UI 框架类的子类，没有一个是纯逻辑。** 那 7 个动作（清缓存 / 存 int / 导出 / 清 cookie）只是它们**覆写的方法体**，类本身是 Preference UI。

**正确形态是「两个文件」而不是「两个模块争一行」**：
```
preference/<Xxx>Preference.ets   ← UI（@Component，用已交付的 MessagePreference / DialogPreference
                                    / ActivityPreference / TaskPreference）+ 文案 / 确认框
PreferenceActions.<action>()     ← 动作逻辑（core-runtime 提供，是它的**依赖**，不是它的**替代**）
```

**已交付可复用的框架类**（4 个基类全在位）：
```
hippo/preference/MessagePreference.ets
hippo/preference/DialogPreference.ets
hippo/preference/ActivityPreference.ets
hippo/ehviewer/preference/TaskPreference.ets
```

**清单处置**：7 条 `status` 回退 `pending`、`owner` 改 `ui-widget`、`target_path` 指向 `preference/<Xxx>Preference.ets`。

**D-033 的正确读法**：
> **`Preference` 子类行 = UI 组件行。动作是它的依赖，不是它的替代。**
> 把"纯逻辑归 PreferenceActions"理解成"整条 inventory 行归 core-runtime"，会让 UI 组件从清单里消失。
| **D-051** | `ui/EhActivity.java`(97) —— `abstract class EhActivity extends AppCompatActivity` | **映射为「页面基类/生命周期助手」，不派生 `UIAbility`** | **验收**：上游 `EhActivity` 只做四件事，逐一带对应物：① `getThemeResId(theme)` + `setTheme()` → ArkUI Stage 模型**不支持页面级换主题**，映射成"读 `Settings.getTheme()` 供页面选资源"的纯函数（可断言）② `((EhApplication) getApplication()).registerActivity(this)` / `unregisterActivity(this)` → ArkUI 无 Application 级 Activity 列表，映射成**页面注册表**（静态 Set<页面 id>，用于"退出所有页面"，纯逻辑可断言）③ `FLAG_SECURE`（`Settings.getEnabledSecurity()` 时）→ **鸿蒙有直接对应** `window.setWindowPrivacyMode(true)` ④ `FirebaseAnalytics` → 已移除（D-006）<br>**为什么不派生 `UIAbility`**：Ability 是**应用级组件**（一个 Ability 承载一个 windowStage），而 `EhActivity` 的上游语义是"**每个页面**都继承的基类" —— 派生 Ability 会让 `SplashActivity`/`ToolbarActivity` 变成独立应用入口（每个都要 manifest 声明、都会开新窗口），与上游"同进程内页面切换"完全不同。<br>**正确对位**：页面 = `@Entry @Component`，由 `EntryAbility.onCreate` 的 `windowStage.loadContent('pages/Index')` 加载，页面间用 `Navigation`/`router` 切换。`EhActivity` 的四个能力拆进"页面基类 + 工具函数"。| gl-render |
| **D-057** | `ui/scene/gallery/detail/GetGalleryDetailListener.kt`(66) —— `EhCallback` 基类 | **依赖倒置成 `GalleryDetailCallbackHost`（4 个能力）** | 上游 `EhCallback` 提供 `connector/application/removeGlobalStuff/scene` 等一整套；本仓库 `ui/scene/EhCallback.ets` 已落地但**本监听器只用到 4 个协作能力**：`removeGlobalStuff(listener)` / `putGalleryDetailCache(gid, detail)` / `putHistoryInfo(detail)` / `startTagsSync(detail)`。因此声明为接口，`EhCallback` 落地后 `implements` 即接入。<br>**为什么不直接继承 `EhCallback`**：继承会把 `stageId/sceneTag/connector` 全部拉进来，而本类**一个都不用**；接口只钉"它真正调用的东西"，测试可用假宿主驱动五个副作用（缓存/历史/标签同步/通知/清理）而无需建整个 Stage。<br>**副作用顺序照搬**：`removeGlobalStuff` 必须是三条回调的**第一句**（含 cancel），且 `result == null` 的 return 在它**之后**。| native-image |
| **D-058** | `EhCallback.isInstance(SceneFragment)` —— 上游按**类**判断（`scene is HistoryScene`） | **改为按 scene tag 字符串比较** | ArkTS 无反射、无 `instanceof` 跨模块类判断（`SceneTypes.ets` 的 `SceneTransitionHelper.onTransition(transactor, exitTag, enterTag)` 同样只给 tag）→ `isInstance(sceneTag: string \| null): boolean`，目标 tag 作为构造参数可注入（默认 `'GalleryDetailScene'` / `'HistoryScene'`）。<br>**语义等价**：上游也是"是不是那个类"，这里"是不是那个 tag"，只是身份载体从 `Class<?>` 变成字符串（与既有 `LaunchMode`/`@Entry` 的 sceneName 身份方案一致）。 | native-image |
| **D-059** | Java `String + (可能为 null 的 String)` → 字面量 `"null"`（如 `gid + "-" + getSuitableTitle(gi)`） | **显式 `?? ''`，并在注释里写明理由** | 上游 `newPath()` 拼 `gid + "-" + title`。本仓库 `EhUtils.getSuitableTitle` 返回 `string \| null`，照搬拼接会得到形如 `123-null` 的**文件名**（用户可见）。<br>**判据**：移植 `+` 拼接时先确认每个操作数在 ArkTS 侧是否可能为 null；可能 → **显式决定** `?? ''` 还是 `?? 'null'` 并写注释。本例选 `?? ''`，因为 `title/titleJpn` 在上游是**非空字段**（null 分支不可达），且文件名含 `"null"` 比空串更糟。<br>**断言钉住**：`newPath` 的结果形态（`gid + '-'`）在 `test/ui-scene/batch1.test.ets` 里断言。 | native-image |
| **D-060** | `ui/scene/history/HistoryScene.java`(409) 与 `ui/scene/GalleryPreviewsScene.java`(487) —— `extends ToolbarScene` + `ContentLayout.ContentHelper` 同步 `LazyList` | **宿主能力接口化 + 显式四态** | ① 两页都需要 `ToolbarScene`（标题栏/返回/菜单）与 `ContentLayout.ContentHelper`（分页状态机）。`ToolbarScene` 未落地 → 声明 `HistorySceneHost`（9 个能力）与 `PreviewsSceneHost`（4 个能力）；`ContentHelper` **已落地**（`hippo/widget/ContentLayout.ets`，7 态齐全）→ 用 `PreviewHelperPort` 只钉本文件实际调用的 10 个方法，**不重写状态机**。<br>② 上游 `EhDB.getHistoryLazyList()` 是**同步** `LazyList`；本仓库是 `async` → 引入 `LOADING/READY/EMPTY/FAILURE` 四态。**视图决策仍与上游一致**：只有"有数据"显示 content(0)，其余三态显示 tip(1)（上游只有"空/非空"两态，因为它同步查询，不存在加载中/失败）。<br>③ 上游 `EventBus.postSticky(GalleryActivityEvent(page, info))` 传页码 → **改为 `openReader(gid, page)` 显式参数**（ArkTS 无 EventBus，且显式参数可测）。<br>④ `isInstance` / `Resizable` 等类判断同上（D-058）。 | native-image |

| **D-061** | `hippo/widget/ShadowLinearLayout.ets` —— 上游 `setElevation(dp2pix(2))` | **`.shadow({radius: 2vp, offsetY: 2vp})`** | **A 类视觉差异，未真机验证**（`hdc list targets` 为空，无设备）。两平台阴影扩散算法不同，像素级非严格等价。<br>**判据**：现代路径（API≥21）就是"elevation 2dp 的 LinearLayout"；nine-patch 分支是 API<21 兼容路径，鸿蒙无该缺陷路径可兜（陷阱 100 ②）。<br>**待验证项**：阴影模糊半径与偏移的观感对齐。 | ui-widget |
| **D-062** | `hippo/ehviewer/widget/GalleryGuideView.ets` —— 上游 5 个 TextView 按 `width/3` 硬切 layout | **百分比宽度 + Flex** | **A 类视觉差异，未真机验证**。上游按 1/3 硬切，窄屏时文字可能截断；改用百分比后换行位置不同。<br>**待验证项**：窄屏（≤360vp）下三步提示文字的换行与截断。 | ui-widget |
| **D-063** | `hippo/widget/FixedAspectImageView.ets` —— 上游自写 `onMeasure` 分支表 | **`.aspectRatio()` + `.constraintSize()`** | **A 类视觉差异，未真机验证**。测量由框架承担，宽高解析在"aspect 生效 + min/max 冲突"时可能与上游不同。<br>**判据**：完全重复 → 不手写 onMeasure（`resolveAdjustedSize` 三分支已逐式保留为可测数学）。<br>**待验证项**：`aspect` 生效且 `maxHeight` 受限时的实际尺寸。 | ui-widget |
| **D-064** | `getSpanCountForSuitableSize` **三处实现且两两不等价** | **各自照搬，不合并** | ① `SimpleGridAutoSpanLayout`（交叉相乘，精确）② `AutoGridLayoutManager`（相对偏差，**含 `total/span` 整数除法截断**）③ `AutoStaggeredGridLayoutManager`（与②逐字符相同）。<br>**实测**：9800 组样本中 ① vs ② 有 **1868 组结果不同（≈19%）**，首个反例 `total=22,single=4` → ① 得 6、② 得 5。<br>**为什么不合并**：三处分属不同层（组件 / GridLayoutManager / StaggeredGridLayoutManager），合并会跨模块耦合。<br>**验收影响**：同一个"按目标列宽自动列数"概念在上游有两套结果 ⇒ **P5 截图比对时这两类页面不能互相比对**，各自只与自己历史版本比。 | ui-widget |
| **D-065** | `hippo/widget/CheckTextView.ets` —— 上游 `AnimationUtils.FAST_SLOW_INTERPOLATOR` / `SLOW_FAST_IN` | **委托 core-runtime 的 `AnimationUtils` 同名常量** | **A 类视觉差异，未真机验证**。200ms 半径动画的曲线数值已与 core-runtime 对齐（`FAST_SLOW_IN=(0,0,0.2,1)`、`SLOW_FAST_IN=(0.4,0,1,1)`），但**遮罩圆的视觉扩散观感**需截图确认。<br>**已修过的一次错**：初版占位写成 `(0.4,0,0.2,1)`（那是 Material 标准曲线），比正确值快 2.5 倍的手感差 —— 由 Lead 核对后改为委托 core-runtime 常量（消除"两处各写一份曲线"的漂移风险）。 | ui-widget |
| **D-066** | `hippo/ehviewer/widget/AvatarImageView.ets` —— 上游每帧 `createBitmap` 三次（`drawableToBitmap`→`reSizeImage`→`createCircleImage`） | **渲染层裁剪 `.clipShape(Circle())` / `.borderRadius()`** | **A 类视觉差异，未真机验证；性能优于上游**。上游 96dp 下每头像每帧 ≈110KB（3 张中间位图），6 可见头像 60fps ≈ **40MB/s 分配**；ArkUI 渲染层裁剪 **0 次中间位图分配**。<br>**判据**：平台无 `createBitmap` 直接等价物（PixelMap 异步），且视觉输出一致 ⇒ 属"偏离实现但结果更好"的合法案例。<br>**待验证项**：圆形裁剪的边缘抗锯齿观感。 | ui-widget |
| **D-067** | `glrenderer/CanvasTexture.java` 的 `FontMetrics`（`TextPaint.getFontMetricsInt()` → `top/ascent/descent/bottom` 四字段） | **`top`/`bottom` 用 `ascent`/`descent` 近似** | **背景**：`FontMetricsLike` 需要 4 个字段，而鸿蒙 `@ohos.graphics.drawing` 的 `Font.getMetrics()` 只给 `ascent`/`descent`（+ 可选 `leading`），**没有独立的"字形最大包围盒"字段**。<br>**取值**：`top := ascent`、`bottom := descent`（`ascent` 负、`descent` 正，与 Android 同号约定）。<br>**后果**：Android 的 `top/bottom` 是极端字形包围盒，通常比 `ascent/descent` 更外扩 → 我们的**行高偏小 1–2px**、上下留白略少。**不会切掉字形**（切字只可能发生在"行高小于 ascent..descent 跨度"时，而这里行高恰等于该跨度）。<br>**触发条件**：`StringTexture`（错误文案单行）、`MultiLineTexture`（D-056 的多行纹理）的排版行高。视觉上是"行距略紧"。<br>**为什么允许**：① 要拿真实 `top/bottom` 必须换 `@ohos.graphics.text`（`Paragraph`），而那会引入 D-056 已经拒绝的第二套文字栈 ② 误差量级 1–2px，且方向单一（只会紧不会松）—— 若真机验收发现行距过紧，再单独提 D 编号换 `Paragraph`。<br>**与 D-031 的关系**：D-031 是"字体族不可指定"，本条是"字体度量字段不完整"，同属"鸿蒙文字栈能力面小于 Skia"，但**是不同的两个缺口**，故单列。 | gl-render |
| **D-068** | `drawing.Font`（`@ohos.graphics.drawing`）—— 上游 `TextPaint.setTypeface(Typeface.DEFAULT_BOLD)` / `setFakeBoldText` 的**粗体能力** | **平台删除：粗体不生效** | **SDK 20 事实**：`drawing.Font` 只有 `setSize` / `setScaleX` / `setSkewX` / `setEdging` / `measureText` / `getScaleX`；**没有 `setBold` / `setWeight` / `setTypeface`**，`FontDescriptor` 与 `drawing.FontWeight` 在 `@ohos.graphics.drawing.d.ts`（442KB）里**零命中**。<br>**处置**：`DrawingTextPaint.setBold(bool)` **只记录状态、不改变渲染**（保留调用点零改动 + 将来 SDK 支持时改一处）。<br>**为什么不"用 `setScaleX` 水平拉伸近似"**：`measureText` 会随之变化，而 `MultiLineTexture`（D-056）的断行依赖 `measureText` → 拉伸会让**断行位置错位**。宁可"粗体不生效"（阅读器错误文案里几乎不可见），也不要"断行错位"。<br>**触发条件**：任何调用 `setBold(true)` 的文字（当前项目内 0 处调用；`StringTexture.newInstanceLimited(..., isBold, ...)` 传 false）。<br>**升级路径**：若某处确实需要粗体，走"换字体族为天生粗的字体"（需 `@ohos.font` 注册 + `Font.setFamily` 若可用），而不是拉伸。 | gl-render |
| **D-069** | `ui/scene/download/DownloadLabelsScene.java`(394) —— `ToolbarScene` + `RecyclerViewDragDropManager` + `EditTextDialogBuilder` | **三个载体各自换形态，行为不变** | ① `ToolbarScene` 未落地 → `LabelsSceneHost`（11 个能力：列表/四种标签操作/默认名解析/删除文案格式化/返回）；② `EditTextDialogBuilder`（带 `show()` 的对象）→ 本仓 `EditTextDialogSpec`（**纯数据**，`setError` 等价于写 `error` 字段），"弹窗"由页面层执行；③ `RecyclerViewDragDropManager` → 只产出**拖拽判定**（`canStartDrag(onDragHandler)`）与**移动决策**（`onMoveItem`），实际拖拽交互由 ArkUI `List` 的 `onItemDrag*` 承担。<br>**照搬的行为差异**：`onMenuItemClick(action_add)` 上游 `break` 后落到 `return false`（**已处理也返回 false**，与 `HistoryScene` 的 `return true` 相反）。 | native-image |
| **D-070** | `ui/scene/download/part/DownloadBatchActions.kt`(362) —— 上游**自带 `Host` 接口** | **照搬该接口形状**，只替换 Android 特有类型 | 上游已用 `interface Host` 反向依赖下载页（`eHContext`/`activity2`/`recyclerView`/`list`/`downloadManager`/`positionInList`/`fabLayout`/…）。本实现保留同一形状，替换三处：① `recyclerView` 的选择集能力（`getCheckedItemPositions`/`checkAll`/`outOfCustomChoiceMode`）② `Intent + startService(ACTION_START_RANGE, KEY_GID_LIST)` → `startRangeDownload(gids: number[])`（上游 `LongList` 是为 JVM 优化的 long 容器，gid < 2^53 用 `number[]` 等价）③ `AsyncTask` → 宿主注入 `deleteFileAsync`/`deleteGalleryFilesAsync`（`taskpool` 实现），本文件只**决定调哪个**。<br>**绝不能合并的两个 API**：单条删除用 `SpiderDen.getExistingGalleryDownloadDir`（已存在目录，可能带 7z 标记），批量删除的 Task 用 `getGalleryDownloadDir`（按 gid 推目录）—— 上游是两个不同语义，合并会删错目录。 | native-image |
| **D-071** | 归档标签的 locale 取值（`ArchiverDownloadCompleter.archiverLabel()`） | **生产取值用 `i18n.System.getSystemLocale()`（含 script/region），不用 `getSystemLanguage()`；且裸 `zh`（无 region）→ `档案`** | **背景**：上游四份资源 `values/`→`Archiver`、`values-zh-rCN/`→`档案`、`values-zh-rHK/`→`歸檔器`、`values-zh-rTW/`→`歸檔器`。Android 的资源匹配里**裸 `zh` 匹配不到 `zh-rCN`**（后者要求 region=CN），会落到 `values/` 默认 = `Archiver`。<br>**我们**：① 生产取值必须用 `getSystemLocale()` —— `getSystemLanguage()` 只返回裸语言码（`'zh'`），带 script/region 的是 `getSystemLocale()`（`'zh-Hans-CN'`）；用前者会让 `zh-Hant`/`zh-HK`/`zh-TW` 分支**在生产路径上永远不可达**（R-11）。② 裸 `zh` 归到 `档案` 而非 `Archiver` —— 鸿蒙上仍可能拿到裸语言码，中文用户看到「档案」比看到英文更符合预期。<br>**后果**：使用裸 `zh` locale 的设备，归档标签是「档案」而不是「Archiver」。**不影响**导入旧 `.db` 的匹配（旧库标签只会是 `档案` 或 `歸檔器`）。<br>**为什么不算缺陷**：这是「输入域比上游更大」时的安全侧选择 —— 上游根本不产生裸 `zh` 这个输入，我们产生了，就必须给它一个合理映射，而不是落到英文默认。 | storage-db |
| **D-072** | `EhDB.importDB()` 的黑名单/画廊标签合并（上游 `EhDB.java:1054-1068`）—— `currentBlackList.contains(black)` / `currentGalleryTags.contains(tags)` | **按主键/业务键判存在**：`BlackList` 按 `badgayname` 单键（与上游 `inBlackList` 的 `where Badgayname=…` 一致）；`GalleryTags` 按主键 `gid`（`dao.load(gid)`） | **上游缺陷（D 类：结果错、我们修）**。两者都**没有重写 `equals`** → `ArrayList.contains` 退化为引用比较 → 恒 false。**同一根因、两种症状**：<br>① `BlackList`（DDL `_id … AUTOINCREMENT` + insert 时 `id=null`）→ **重复行**，用户可见且无唯一键可自动去重；<br>② `GalleryTags`（DDL `GID INTEGER PRIMARY KEY NOT NULL`，**不自增**）→ 带源库 gid 直接 insert，冲突策略 ABORT → **同一文件第二次导入必然抛约束错误** → `importDB` 返回 `cant_read_the_file` → **整条导入失败**（前面的表已写入=部分导入）。P3「能导入原 App 的 .db」验收会稳定复现。<br>**为什么不能靠"补 equals"**：两者内容都含跨库必然不同的时间字段（`add_time` / `create_time`+`update_time`）→ 比内容恒不等 → 照样冲突。必须按主键/业务键。<br>**Filter 除外**：上游 `Filter` **手写了 `equals`/`hashCode`**（mode+text），`contains` 本来就按值去重、是对的 —— 按"这两个也没 equals，一起改"的批量思路动它会把对的改错。<br>**代价**：与上游"导入两次=两倍 / 第二次失败"的表现不一致 —— 这正是要修的点。 | core-runtime |
| **D-073** | `FavoritesScene.kt` 的 `guideCollections()` —— 用第三方库 `ShowcaseView` 做"高亮控件 + 气泡"引导 | **删除**（功能由已移植的 `GalleryGuideView` 承担） | 三条理由：① `ShowcaseView` 是**第三方库**，不是上游自研 —— 我们没有"1:1 重写第三方库"的义务（同 Firebase 移除、自更新整模块删除）；② 功能等价物已存在：`GalleryGuideView`（S0561 已 ported，自绘引导页）；③ 自绘"高亮某控件 + 气泡定位"需 200+ 行，收益仅是"看起来和上游一样"。<br>**后果（用户可见）**：引导的**触发时机与展示形态**与上游不同 —— 我们的是全屏引导页，上游是控件高亮气泡。<br>**代码痕迹**：`FavoritesScene.BackHandler.onBackPressed` 保留 `guideVisible` 形参并注释"该分支在本仓库恒为假"（D-073 后无引导层）—— 保留是为了让**返回键四级顺序可测**，将来若引入引导层只需把 flag 置真。 | ui-widget |

---

## D-075｜141 个 `ui/drawable` 做成 `@Component struct`（形态错，非移植缺口）

**日期**：2026-10-27　**状态**：已记录，未重做　**影响**：141 条清单项的形态

### 事实

上游 `res/drawable/` 下 141 个资源（`<vector>` / `<shape>` / `<selector>`），
逐文件移植成了 `@Component struct`（`hippo/ui/drawable/*.ets`）。

前缀分布（实测）：
```
v_           74   矢量图标（vector）
ic_          34   图标（png/vector）
其它         25
big_          6   大插图（vector）
bg/selector   2   真背景（shape/selector）
```

### 为什么是形态错

ArkUI **没有"把组件当作背景或图像源"的 API**。上游这些资源靠
`android:background="@drawable/x"` 或 `ImageView src` 应用；做成 `@Component struct` 之后：

```
全仓 0 处实例化（check_orphan_exports 的 drawableAsComponent = 141）
```

**它们不是"无法实例化"，而是"实例化了也没法当背景用"** —— 这个区分很重要。

### 正确形态

| 上游类型 | ArkUI 对位 |
|---|---|
| `v_*` / `big_*`（vector） | `resources/base/media/*.svg` + `Image($r('app.media.x'))` |
| `ic_*` / `abc_*`（图标） | 同上（SVG 或 PNG） |
| `bg_*` / `selector_*`（shape） | `.backgroundColor()` / `.borderRadius()` / `.border()` / `Shape()` |

**已有正确先例**：`v_cookie_brown_x48` 已按这条路改成 `media/v_cookie_brown_x48.svg`
（`ui-scene` `7b6dab29`，判据是"先 `git show` 看根元素是不是 `<vector>`"）。

### 为什么保留 `ported` 而不改 `na`

```
na 的语义 = "上游没有对位"
这 141 条 = "有对位，只是移植形态选错" —— 不是 na
```

**而且改成 `na` 会把它们从分母摘掉**，百分比几乎不变（99.87% → 99.86%）
—— **那等于用重新贴标签代替诚实**。

**所以**：保持 `status=ported`，在 `notes` 逐条写明形态问题 + 本 D 编号。

### 后续（未排期）

```
① 需要某个图标时，按 v_cookie_brown_x48 的路子先转 SVG 到 media/
② 141 个 @Component 文件在"被替换"之前是 dead code
③ 批量重做的话：114 个（v_/ic_/big_）可机械转 SVG；27 个需人工判断用哪种 ArkUI 样式
```

### 判据（进库）

> **移植资源时先判"资源形态"，再决定 ArkTS 侧的载体。**
> 位图 → `media/*.png`；矢量 → `media/*.svg`；纯色 → `colors.json`；
> shape/selector → 控件的 `.backgroundColor/.border` 等链式属性；
> 九宫格 → `.resizable()` + `.9` 拆解。
> **`@Component` 只在"这东西本身是个可见元素"时才正确** ——
> 资源是"被应用"的，不是"被渲染"的。

---

## D-076｜移除 `ohos.permission.NOTIFICATION_CONTROLLER`（装不上真机，非设计缺陷）

### 断言

`module.json5` 的 `requestPermissions` **不含** `ohos.permission.NOTIFICATION_CONTROLLER`
（上游 Android 侧 `android.permission.POST_NOTIFICATIONS` 的语义对应项）。

### 理由

`NOTIFICATION_CONTROLLER` 的 `apl` 是 **`system_basic`**，高于我们签名档的 **`normal`**。
带该权限的 HAP **装不上真机**：

```
bm install -p <hap>  →  code:9568289
```

这是**权限等级与签名档的硬冲突**，不是代码问题，也不是可以用代码绕过的。
要保留该权限，必须换成 `system_basic` 及以上级别的签名档（需要华为的企业/系统级证书），
与本项目的 debug profile 方案不相容。

### 记录

- 首次修复提交：`94327790` — `fix(manifest): 移除 NOTIFICATION_CONTROLLER —— 它让 App 装不上真机（code:9568289）`
- 连带影响：`requestPermissions` 从 9 条降到 8 条
- 消费方：`scripts/acceptance/check_manifest_permissions.ps1` 的「⓿ 已裁决不申请」表（`record` 字段指向本编号）

### 代价（诚实记录）

**通知栏相关功能在真机上不可用**（下载完成通知、新版本提示等）。
上游有、我们没有 —— 属**已知功能缺口**，不是"已等价实现"。
若将来拿到 `system_basic` 及以上签名档，本 D 编号应被撤销并恢复该权限。

### 判据（进库）

> **白名单/豁免名单是闸门系统里唯一能把"红"合法变成"绿"的地方，所以每一条都必须带记录位置。**
> 三字段：`entry`（确切断言）/ `reason`（为什么不做）/ `record`（D 编号、文档路径或提交哈希）。
> `record` 留空 = 消音器，不是豁免 —— 半年后没人能分辨"认真论证过不做"和"当时红了顺手加的"。
>
> 配套要求：命中豁免时必须**打印 `SKIP` + 原因 + 记录位置**，不许静默剔除 ——
> 否则"故意不做"和"忘了做"在输出上无法区分。
>
> **本条 D-076 的出现方式值得记**：它是闸门 `-Strict` 变红后**倒逼**出来的 ——
> 代码早就改了（`94327790`），但**没有任何书面记录**。
> ⇒ **凡是"为了让真机能装/能跑"而做的删减，当场就要落 D 编号**，否则它会在几周后以"闸门报缺口"的形式重新出现。


---

## D-077｜`themes.json` 内联颜色（97 条字面量 / 仅 4 条引用）—— 双份真值

### 断言（数字我复核过，与 `ui-scene` 独立得出的结果一致）

```
base/element/themes.json（17262 B，30 个 theme）
  属性|#AARRGGBB 字面量   97 条
  属性|@color/xxx 引用     4 条
  属性|@style/xxx          9 条
  其它（布尔/枚举/字符串）  76 条
  其中 **70 条字面量与 colors.json 里的同名颜色同值**（本该引用却内联）

dark/element/themes.json（269 B）
  属性|#hex                 2 条   ← FullscreenContainer 的 night 变体，正确

上游 values/themes.xml：凡涉及颜色的 item **清一色 `@color/xxx` 引用**
```

### 理由（为什么这是偏离，不是翻译风格）

**它使 `themes.json` 从「属性 → 颜色 的映射表」变成「第二份配色表」。**
改 `colors.json` 的 `colorPrimary`，`themes.json` 里 `BaseTheme.colorPrimary=#FF009688` **不会跟着变**。
两份真值的后果是漂移不可检：深色/黑色主题（`BaseTheme_Dark` / `BaseTheme_Black`）
里的内联值若与 `colors.json` 分叉，只能靠人眼看出来。

### 已核实的反例（避免误判）

- `dark/` 只有 269 字节**不是缺口** —— 上游 `values-night/` 就只有一个 style，
  深色主题靠**独立 style 名**（`BaseTheme_Dark`）而非 night 覆盖，我们结构一致
- `base` 与 `dark` 的 `FullscreenContainer` 四个颜色**逐项与上游一致**（见下），未错位：
```
上游 values/         light_blue_600 #FF039BE5 / light_blue_A200 #FF40C4FF
上游 values-night/   light_blue_900 #FF01579B / light_blue_A400 #FF00B0FF
我们 base                                   #FF039BE5 / #FF40C4FF        ✓
我们 dark                                   #FF01579B / #FF00B0FF        ✓
```

### 处置（按性价比，当前只做前两项）

```
① 记录（本 D 编号）+ 加闸门 warn：属性|#hex 且 colors.json 有同值 → 报"本该引用却内联"
   注意：colors.json 里**无同值的不报**（可能是页面特有颜色），否则 27 条噪声会让闸门被关掉
② **暂不改 97 条** —— 前置事实未确认：ArkUI `strarray` 的值能否写 `$r('app.color.X')`
   在事实未确认时动 17 KB 资源 = 拿"未知"换"已知风险"
③ 待确认后再决定是否把内联改回引用
```

### 判据（进库）

> **"占位用的魔数"最危险的地方不是它不准，而是它看起来像个真值。**
> 凡注释里出现「上游 `<标识>` = `<值>`」这类断言，必须同一行或相邻行给出
> ① 验证命令 或 ② 上游文件:行号。否则视为未验证，**不得作为移植依据**。
>
> 同族：本次审计中 `single_max_width = 560` 就是这类魔数 —— 上游是 **两档 260dp / 480dp**，
> 而 560 既不是 260 也不是 480，是凭感觉写的，还被注释成"上游量级"。
> **注释里没跑过命令的"上游 X"就是伪证**，而它污染的是后来人的信任：读者会以为有人查过，于是不再去查。

---

## D-078｜自定义控件折叠为 `@BuilderParam` 时丢失内部子节点（用户见空白，闸门见完整）

### 断言

上游若干自定义控件**内部自带子节点 XML**；`convert_layout.ps1` 按「自定义控件 → `@BuilderParam` 槽位」的策略
把整棵子树折叠成一个槽，**未保留其内部子节点**。受影响：

```
item_filter.xml              <com.hippo.widget.ShadowLinearLayout> 内有 ImageView(48dp) + …
item_quick_search.xml        同上
subscripition_list_item.xml  同上
```
我们的对应布局 `build()` 里 `Image`/`Text` 出现次数：**各 1 次** ⇒ 空壳。

### 为什么闸门看不见

各道闸门都按「元素是否已生成」量，而**被折叠的子树在槽位里"占了位"** ⇒ 算已生成。
所以 `check_layout_zero_weight` 报「元素整段未生成 = 42 处（其中 26 是它自己的假阳性）」，
却**从不包含这三个文件**。`check_probe_coverage` 报 840 个 ported 文件全覆盖，同样看不见。

⇒ **这是「量具口径比现实窄」的第三个实例**（另两个：inventory 说 ported 而元素级 42 处不在；
13/13 全绿而 28 个脚本最严模式下 9 个红）。

### 影响面与用户视角

```
item_filter 的条目      → 空行（宿主 FilterActivity.ets 已用内联渲染等价实现，标 na）
item_quick_search       → 滑动区空白（缺 QuickSearchSceneView，见 W-026）
subscripition_list_item → 缺 ArkUI 条目视图（上游 adapter 是纯数据，无渲染层）
```

### 修法（**不在设备期前做**）

修在转换器策略，不在某个布局：折叠自定义控件时是否应**递归保留其子节点**。
但修改会重生成布局且需要全量 UI 回归，暂保持按需内联宿主渲染实现。
**因此记录、不修。**

### 判据（进库）

> **任何"完整 / 全绿 / 0 缺口"的结论，都要先回答「我的量具看不见什么」。**
> 量具看不见的东西不会因为它被合法处理而消失 —— 它只是不出现在数字里。
>
> 具体到本次：**被转换策略"合法折叠"的子树，在按元素比对的口径里是完整的，在用户眼里是空白。**
> 报告缺口时必须说清"它在我这个口径里是什么"，而不只是"它是什么" —— **口径差异本身就是结论的一部分。**

---

## D-079｜归档格式策略：ZIP 随机按页解压（Z2）与暂不支持 RAR（R1）

### 决策来源与实现口径（Stage C Track P5 用户确认）

1. **ZIP / CBZ（Z2 策略）**：
   - 主路径在 `harmony/entry/src/main/cpp/napi/napi_zip.c` 基于 NDK 内置 `zlib`（`-lz`）解析 EOCD + Central Directory，支持 STORE 与 DEFLATE 条目按页随机流式解压并接入 `NativeA7ZipBridge`（不预解包整卷，单页上限 64MB）；
   - 遇到 ZIP64、多卷或非标准结构时，自动在 `ArchiveGalleryProvider.ets` 回退到 `@kit.BasicServicesKit` `zlib.decompressFile`（对外置 `file://docs/` URI 先按只读 fd 暂存再解包，条目按自然序排序，`stop()` 时清理临时目录）。
2. **RAR / CBR（R1 策略，已知能力缺口）**：
   - `harmony/entry/src/main/module.json5` 的 `skills.uris` 只声明 `general.zip-archive` 与 `org.7-zip.7-zip-archive`，**暂不声明 `com.rarlab.rar-archive`**（避免系统向用户呈现打开入口后无法解压）；
   - 代码底层通过 `ArchiveFormatSniffer.ets` 识别 RAR 魔数（`52 61 72 21 1A 07`，覆盖 RAR4/RAR5）并在 `ArchiveGalleryProvider` / `NativeA7ZipBridge` 返回明确的 11 语系错误提示（`$string:error_rar_unsupported`），防止被误当成损坏文件静默失败。
   - **撤销条件**：后续引入 unrar C 源码或系统提供原生 RAR 解压能力时，可解除 `R1` 并补回 `com.rarlab.rar-archive`。

---

## D-080｜`ShortcutsActivity` 在 OpenHarmony API 20 / `apl ≤ normal` 下的等价适配（S1）

### 上游行为与鸿蒙平台约束

- **上游**：独立无界面透明 `ShortcutsActivity` 在 `onCreate()` 取 Intent `action`（`start_all` / `stop_all`）→ `startService(DownloadService)` → 立即 `finish()`（用户停留在桌面，不拉起主界面）。
- **鸿蒙约束**：单 UIAbility 架构（`EntryAbility`）下在桌面长按快捷方式冷启动若调用 `terminateSelf()` 会造成“冷启动闪退”观感，且 `shortcuts_config.json`（API 20 schema）的 `wants[]` 仅允许 `bundleName`/`moduleName`/`abilityName`/`parameters`（不支持 `action` 字段，故参数改走 `parameters.shortcut_action`）。

### S1 等价适配方案（已实现）

- `ShortcutsActivity.ets` 优先读取 `want.parameters.shortcut_action`（保留对旧版 `want.action` 兼容）；
- **冷启动**（`EntryAbility.onCreate`）：等 `AppWiring.whenReady()` 就绪后执行 `ShortcutsActivity.handleWant()` 分发下载动作，经门 1（若已设置应用锁）后由 `Index.ets` 直达 `DownloadsScene` 并弹出对应 Toast，**不调用 `terminateSelf()`**；
- **热启动**（`EntryAbility.onNewWant`）：执行下载动作并保持当前所在页面不打断阅读/浏览，仅弹出确认 Toast。
