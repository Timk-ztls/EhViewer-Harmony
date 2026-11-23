/**
 * 「把某个 URL 的字节写进 sink」的最小契约。
 *
 * ## 为什么放在 `streampipe/` 而不是 `spider/SpiderQueen.ets`
 *
 * 这个接口的三方关系是：
 * ```
 * 消费方  spider/SpiderQueen.ets（storage-db）  —— 需要"有人帮我把这张图下下来"
 * 实现方  okhttp/PageImageDownloaderImpl.ets（net-parse）—— 用 okhttp 栈实现
 * 依赖物  streampipe/OutputStreamPipe.ets 的 `ByteSink`
 * ```
 * 若接口留在 `SpiderQueen.ets`，实现方 `implements` 它就得 **net-parse 反向依赖 storage-db** —— 层级倒置。
 * 若不用 `implements` 而靠结构等价 + `as` 转型，`arkts-no-structural-typing` 会拒绝
 * （本项目今天已因此踩坑 4 次：同形状 interface 各声明一份、字面量赋 class 类型、union 成员字面量、`X | undefined` vs `X | null`）。
 *
 * 所以接口放在 **`ByteSink` 的同一层**（`streampipe/`），两边都向下依赖它，无环。
 *
 * ## 与上游的关系
 *
 * 上游没有这个接口 —— `SpiderQueen.downloadPage` 直接持有 `mOkHttpHelper`（`EhApplication.getImageOkHttpClient()`）。
 * ArkTS 侧 HTTP 栈是另一套，塞进 `EhEngineLike` 会让接口面膨胀且与 net-parse 无关，
 * 所以抽成这个注入点（见 `SpiderQueen.setPageImageDownloader()`）。
 *
 * **未注入时**：该页显式失败并记错误（不静默、不写假下载），且**下载泵必须继续跑**。
 */
import { ByteSink } from './OutputStreamPipe';
import { DownloadResult } from '../okhttp/ChunkedSinkWriter';

export { DownloadResult };

export type PageDownloadProgressCallback =
  (contentLength: number, receivedSize: number, bytesRead: number) => void;

export interface PageImageDownloader {
  /**
   * 下载 `url` 的字节，逐块写进 `sink`（C-18 可选传 `referer`）。
   *
   * @returns `true` 表示完整写入；`false` 表示失败（调用方据此把该页标为失败并按上游语义重试）。
   *          **不要**用 `false` 表示"部分成功" —— 部分成功也要算失败（否则会写下半张图）。
   */
  download(url: string, sink: ByteSink, referer?: string): Promise<boolean>;

  /**
   * 带状态码的下载（C-18）：暴露 HTTP 状态码与实际接收字节数，用于 509 限流与空图检测。
   */
  downloadWithStatus(url: string, sink: ByteSink, referer?: string,
    onProgress?: PageDownloadProgressCallback): Promise<DownloadResult>;

  /**
   * 探测重定向目标 URL（不跟随重定向、不拉取响应体），用于 `/fullimg` 原图跳转或配额检测。
   */
  resolveRedirectUrl?(url: string, referer?: string): Promise<string | null>;
}
