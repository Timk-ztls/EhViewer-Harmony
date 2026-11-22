/*
 * 对位上游：`GalleryProvider2` 三个子类里**重复出现**的那段「请求栈 + 单消费者解码」逻辑
 * （`DirGalleryProvider.run()` 的 while 循环 / `ArchiveGalleryProvider` 的同构循环）。
 *
 * 为什么单独抽出来（不是重构癖）：
 *   1. 上游这段逻辑写在 `run()` 里，靠 `Thread` + `wait()/notify()` 驱动，**无法单测**
 *   2. 鸿蒙侧改成异步泵（D-024：上游多线程模型 → 单线程异步泵），泵本身必须是纯的、可测的，
 *      否则"取消请求""后进先出""去重"这些语义只能靠真机看图片验证
 *   3. 三个 provider 结构同构，抽一份 = 一份测试覆盖三个
 *
 * 语义与上游 `Stack<Integer> mRequests` + `AtomicInteger mDecodingIndex` 逐条对应：
 *   - **后进先出**：上游 `mRequests.pop()` 取栈顶 → 本类 `pop()` 同
 *   - **去重**：上游 `if (!mRequests.contains(index) && index != mDecodingIndex.get())`
 *     → `push()` 返回是否真的入栈
 *   - **取消**：上游 `mRequests.remove(Integer.valueOf(index))` → `cancel()`
 *   - **单消费者**：上游只有一个 run() 线程 → `drain()` 里 `mPumping` 守卫
 *   - **中断**：上游 `Thread.interrupt()` → `stop()`
 *
 * 本文件**不 import 任何 SDK / glgallery**（保持可在 Node 里直接跑），
 * 空值哨兵用 `NO_REQUEST`，其值必须恒等于 `GalleryPageView.INVALID_INDEX`（= -1）；
 * 这个等式由 `DirGalleryProvider` 的静态自检在运行时兜（见该文件 `assertNoRequestMatches`）。
 */

/** 无请求哨兵。**必须**等于 `GalleryPageView.INVALID_INDEX`（-1）。 */
export const NO_REQUEST: number = -1;

export class RequestPump {
  /** 请求栈：倒数第一个是下一个要处理的（后进先出，与上游 Stack 一致）。 */
  private mStack: number[] = [];
  /** 正在解码的页（上游 mDecodingIndex）。 */
  private mCurrent: number = NO_REQUEST;
  /** 泵是否在跑（保证同一时刻只有一个消费者）。 */
  private mPumping: boolean = false;
  /** 已停止（上游 Thread 被 interrupt）。 */
  private mStopped: boolean = false;

  /**
   * 入栈（对位上游 `onRequest` 里的入栈条件）。
   * @returns true = 真的入栈；false = 已在栈内或正在解码该页（被忽略）
   */
  push(index: number): boolean {
    if (index === this.mCurrent) {
      return false;
    }
    if (this.mStack.indexOf(index) >= 0) {
      return false;
    }
    this.mStack.push(index);
    return true;
  }

  /** 取消一个待处理请求（对位上游 `onCancelRequest`）。已在解码的那一页不会被取消（上游同）。 */
  cancel(index: number): boolean {
    const at: number = this.mStack.indexOf(index);
    if (at >= 0) {
      this.mStack.splice(at, 1);
      return true;
    }
    return false;
  }

  /** 取下一个待处理页（后进先出）；空返回 `NO_REQUEST`。 */
  pop(): number {
    const index: number | undefined = this.mStack.pop();
    return index !== undefined ? index : NO_REQUEST;
  }

  /** 当前正在处理的页（上游 `mDecodingIndex.get()`）。 */
  getCurrent(): number {
    return this.mCurrent;
  }

  /** 由 drain 内部设置；外部只需读。 */
  setCurrent(index: number): void {
    this.mCurrent = index;
  }

  /** 待处理请求数。 */
  pendingCount(): number {
    return this.mStack.length;
  }

  /** 是否还有待处理请求。 */
  hasPending(): boolean {
    return this.mStack.length > 0;
  }

  isPumping(): boolean {
    return this.mPumping;
  }

  isStopped(): boolean {
    return this.mStopped;
  }

  /** 停止泵并清空队列（对位上游 `interrupt()` + `mFileList.lazySet(null)` 的队列部分）。 */
  stop(): void {
    this.mStopped = true;
    this.mStack = [];
    this.mCurrent = NO_REQUEST;
  }

  /** 允许重新开始（对应 `stop()` 之后再次 `start()`）。 */
  reset(): void {
    this.mStopped = false;
    this.mPumping = false;
    this.mCurrent = NO_REQUEST;
  }

  /**
   * 单消费者异步泵：把栈里的页逐个交给 `handler`，直到栈空或 stop()。
   *
   * 关键点（与上游 run() 的 while 循环等价）：
   *   - 已被占用时**直接返回**（不排队第二个泵）—— 上游也只有一个线程
   *   - 每次 `pop()` 后立刻 `setCurrent(index)`，处理完复位 `NO_REQUEST`
   *   - `handler` 抛错**不会**中断泵（上游解码异常也是 continue），错误由 handler 自己转成
   *     `notifyPageFailed`
   */
  async drain(handler: (index: number) => Promise<void>): Promise<void> {
    if (this.mPumping || this.mStopped) {
      return;
    }
    this.mPumping = true;
    try {
      while (!this.mStopped) {
        const index: number = this.pop();
        if (index === NO_REQUEST) {
          break;
        }
        this.mCurrent = index;
        try {
          await handler(index);
        } catch (e) {
          // 与上游一致：单页失败不影响后续页
        }
        this.mCurrent = NO_REQUEST;
      }
    } finally {
      this.mPumping = false;
      this.mCurrent = NO_REQUEST;
    }
  }
}
