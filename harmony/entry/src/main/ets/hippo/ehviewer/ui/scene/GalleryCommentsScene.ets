/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/GalleryCommentsScene.java（991 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/GalleryCommentsScene.ets（inventory S0249）
 *
 * Part 1（本批）：场景身份/参数、评论列表数据链路、分页（hasMore）、投票动作（带三段式日志）。
 * Part 2 待补：评论项渲染（头像/时间/楼层/引文）、回复面板、发送评论、投票乐观更新回滚。
 *
 * 已核实（grep export class）：
 *   GalleryComment{ id, score, voteUpAble, voteUpEd, voteDownAble, voteDownEd, voteState }
 *   GalleryCommentList{ comments: GalleryComment[], hasMore: boolean }（扁平，非树）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../../scene/SceneTypes';
import { SceneFragment } from '../../../scene/SceneFragment';
import { SceneDataSource } from '../../../ui/SceneDataSource';
import { GalleryComment } from '../../client/data/GalleryComment';
import { GalleryCommentList } from '../../client/data/GalleryCommentList';

/** 评论请求接口（EhClient 未交付，契约先行；同 GalleryListScene 模式） */
export interface CommentClientLike {
  getGalleryCommentList(apiUrl: string, showAll: boolean): Promise<GalleryCommentList | null>;
  postComment(apiUrl: string, content: string, replyToId: number): Promise<boolean>;
  voteComment(apiUrl: string, commentId: number, up: boolean): Promise<number>;
}

export class UnavailableCommentClient implements CommentClientLike {
  async getGalleryCommentList(apiUrl: string, showAll: boolean): Promise<GalleryCommentList | null> {
    hilog.warn(0x0000, 'GalleryCommentsScene', 'EhClient 未接线: getGalleryCommentList(showAll=%{public}s)', String(showAll));
    return null;
  }
  async postComment(apiUrl: string, content: string, replyToId: number): Promise<boolean> {
    hilog.warn(0x0000, 'GalleryCommentsScene', 'EhClient 未接线: postComment(replyTo=%{public}d)', replyToId);
    return false;
  }

  async voteComment(apiUrl: string, commentId: number, up: boolean): Promise<number> {
    hilog.warn(0x0000, 'GalleryCommentsScene', 'EhClient 未接线: voteComment(id=%{public}d)', commentId);
    return -1;
  }
}

export abstract class GalleryCommentsScene extends SceneFragment {
  static readonly KEY_API_URL: string = 'api_url';
  static readonly KEY_GID: string = 'gid';
  static readonly KEY_TOKEN: string = 'token';
  static readonly KEY_API_UID: string = 'api_uid';
  static readonly KEY_API_KEY: string = 'api_key';
  static readonly KEY_COMMENTS: string = 'comments';

  protected apiUrl: string = '';
  protected gid: number = -1;
  protected token: string = '';
  protected apiUid: number = -1;
  protected apiKey: string | null = null;
  protected client: CommentClientLike = new UnavailableCommentClient();
  protected dataSource: SceneDataSource<GalleryComment> = new SceneDataSource<GalleryComment>();
  protected loading: boolean = false;
  protected hasMore: boolean = false;
  protected errorMessage: string = '';
  /** 上游没有分页：一个布尔 mShowAllComments，URL 带 hc=1 一次拿全部 */
  protected showAllComments: boolean = false;
  private onStateChangedListener: (() => void) | null = null;

  getSceneName(): string {
    return 'GalleryCommentsScene';
  }

  setCommentClient(client: CommentClientLike): void {
    this.client = client;
  }

  setOnStateChangedListener(fn: (() => void) | null): void {
    this.onStateChangedListener = fn;
  }

  protected notifyStateChanged(): void {
    const fn: (() => void) | null = this.onStateChangedListener;
    if (fn !== null) {
      fn();
    }
  }

  getApiUrl(): string {
    return this.apiUrl;
  }

  getGid(): number {
    return this.gid;
  }

  getToken(): string {
    return this.token;
  }

  getApiUid(): number {
    return this.apiUid;
  }

  getApiKey(): string | null {
    return this.apiKey;
  }

  getErrorMessage(): string {
    return this.errorMessage;
  }

  isShowAllComments(): boolean {
    return this.showAllComments;
  }

  onNewArguments(args: SceneArgs): void {
    const u: Object | undefined = args.get(GalleryCommentsScene.KEY_API_URL);
    if (u !== undefined && typeof u === 'string') {
      this.apiUrl = u as string;
    }
    const g: Object | undefined = args.get(GalleryCommentsScene.KEY_GID);
    if (g !== undefined && typeof g === 'number') {
      this.gid = g as number;
    }
    const t: Object | undefined = args.get(GalleryCommentsScene.KEY_TOKEN);
    if (t !== undefined && typeof t === 'string') {
      this.token = t as string;
    }
    const uid: Object | undefined = args.get(GalleryCommentsScene.KEY_API_UID);
    if (uid !== undefined && typeof uid === 'number') {
      this.apiUid = uid as number;
    }
    const ak: Object | undefined = args.get(GalleryCommentsScene.KEY_API_KEY);
    if (ak !== undefined && typeof ak === 'string') {
      this.apiKey = ak as string;
    }
    const initial: Object | undefined = args.get(GalleryCommentsScene.KEY_COMMENTS);
    if (initial !== undefined && initial !== null && initial instanceof GalleryCommentList) {
      const listObj: GalleryCommentList = initial as GalleryCommentList;
      this.dataSource.setAll(listObj.comments);
      this.hasMore = listObj.hasMore;
      this.showAllComments = GalleryCommentsScene.initialShowAll(listObj);
      this.notifyStateChanged();
      return;
    }
    if (this.apiUrl.length > 0 && this.dataSource.totalCount() === 0) {
      this.refreshComments();
    }
  }

  getDataSource(): SceneDataSource<GalleryComment> {
    return this.dataSource;
  }

  isLoading(): boolean {
    return this.loading;
  }

  isHasMore(): boolean {
    return this.hasMore;
  }

  /** 首屏 / 刷新：整段替换（上游无分页，一次拿全部） */
  refreshComments(): void {
    if (this.loading) {
      return;
    }
    this.loadComments(true);
  }

  /** 上游「More」：置 showAll=true 后重新请求一次，拿回全部评论（不是翻页） */
  showMoreComments(): void {
    if (this.showAllComments || this.loading) {
      return;
    }
    this.showAllComments = true;
    this.loadComments(true);
  }

  /** 上游没有"滚动到底加载下一页"，底部只有 More 按钮 → 转到 showMoreComments */
  onReachEnd(): void {
    if (this.loading || !this.hasMore) {
      return;
    }
    this.showMoreComments();
  }

  protected loadComments(refresh: boolean): void {
    this.loading = true;
    this.client.getGalleryCommentList(this.apiUrl, this.showAllComments).then((list: GalleryCommentList | null) => {
      this.loading = false;
      if (list === null) {
        this.hasMore = false;
        return;
      }
      if (refresh) {
        this.dataSource.setAll(list.comments);
      } else {
        this.dataSource.addAll(list.comments);
      }
      this.hasMore = list.hasMore;
      this.onCommentsLoaded(refresh);
    }).catch((e: Error) => {
      this.loading = false;
      hilog.error(0x0000, 'GalleryCommentsScene', 'getGalleryCommentList failed: url=%{public}s showAll=%{public}s err=%{public}s; 后果：评论停在当前内容',
        this.apiUrl, String(this.showAllComments), this.errorToString(e));
    });
  }

  // 注：投票实现见 Part 2 的 `voteComment`（Part 1 这里曾有一份"只改 score"的简版，
  // 与 Part 2 重复定义；已删除，保留本注释说明去处）。

  /** Part 2：评论到位后的渲染钩子 */
  protected onCommentsLoaded(refresh: boolean): void {
  }

  private errorToString(e: Error): string {
    return e.message !== undefined && e.message !== null ? e.message : String(e);
  }

  // ---------------- Part 2：评论项绑定 / 回复面板 / 发送 / 投票乐观回滚 ----------------

  /** 回复面板状态（上游 onReplyComment：记录被回复的评论 id 与作者） */
  protected replyTargetId: number = -1;
  protected replyTargetAuthor: string = '';

  isReplyPanelOpen(): boolean {
    return this.replyTargetId >= 0;
  }

  getReplyTargetId(): number {
    return this.replyTargetId;
  }

  /** 上游回复某条评论：id==0（上传者）也可回复，只是不可投票 */
  openReplyPanel(index: number): void {
    const c: GalleryComment | null = this.dataSource.getData(index);
    if (c === null) {
      return;
    }
    this.replyTargetId = c.id;
    this.replyTargetAuthor = c.user;
  }

  closeReplyPanel(): void {
    this.replyTargetId = -1;
    this.replyTargetAuthor = '';
  }

  /** 发送评论：成功后清空面板并整段刷新（上游发送后 reload 首页） */
  sendComment(content: string): void {
    const text: string = content.trim();
    if (text.length === 0) {
      return;
    }
    this.client.postComment(this.apiUrl, text, this.replyTargetId).then((ok: boolean) => {
      if (!ok) {
        hilog.warn(0x0000, 'GalleryCommentsScene', 'postComment rejected: gid=%{public}d; 后果：评论未发表，输入内容保留', this.gid);
        return;
      }
      this.closeReplyPanel();
      this.refreshComments();
    }).catch((e: Error) => {
      hilog.error(0x0000, 'GalleryCommentsScene', 'postComment failed: gid=%{public}d err=%{public}s; 后果：评论未发表，输入内容保留',
        this.gid, this.errorToString(e));
    });
  }

  /**
   * 投票（**上游不是乐观更新**）。
   *
   * 逐行核过 `GalleryCommentsScene.java`：
   *   - `voteComment(id, vote)` 只发请求，**请求前不改任何 UI**；
   *   - `VoteCommentListener.onSuccess` → 弹 tip（四种文案，见 `voteToastOf`）+ `onVoteCommentSuccess(result)`；
   *   - `onVoteCommentSuccess` → 按 id 找位置 → 改 score + **互斥**改 voteUpEd/voteDownEd → 只刷那一行 → setResult 回传整表；
   *   - `VoteCommentListener.onFailure` → **只弹 `vote_failed`，不回滚**（因为压根没提前改）。
   *
   * ⚠️ 本文件上一版这里写的是"乐观更新 + 失败回滚"——那是**新增行为**，上游没有。
   * 已按 1:1 改回"成功后应用；失败只提示"。
   * 保留这条注释，避免后人再次"顺手加个乐观更新"：加它要同时改成功后互斥逻辑，
   * 否则会出现"先 +1 再被互斥清掉"的跳变。
   */
  voteComment(index: number, up: boolean): void {
    const c: GalleryComment | null = this.dataSource.getData(index);
    if (c === null || c.id === 0) {
      // 上游：id == 0 是上传者评论，不可投票
      return;
    }
    this.client.voteComment(this.apiUrl, c.id, up).then((score: number) => {
      if (score < 0) {
        hilog.warn(0x0000, 'GalleryCommentsScene',
          'voteComment rejected: commentId=%{public}d; 后果：界面未变（上游无乐观更新）', c.id);
        return;
      }
      GalleryCommentsScene.applyVoteResult(c, score, up ? 1 : -1, score);
      this.dataSource.setAt(index, c);
    }).catch((e: Error) => {
      hilog.error(0x0000, 'GalleryCommentsScene',
        'voteComment failed: commentId=%{public}d err=%{public}s; 后果：界面未变（上游无乐观更新）',
        c.id, this.errorToString(e));
    });
  }

  /**
   * 应用一次投票结果（上游 `onVoteCommentSuccess` 里那段字段变换）。
   *
   * **互斥是关键**：`expectVote > 0` 时 `voteUpEd = (vote != 0)` 且 **`voteDownEd = false`**；
   * 反之亦然。漏掉"清另一侧"会出现"赞和踩同时亮"。
   *
   * @param expectVote 期望方向（`>0` 表示赞，否则踩）—— 来自发起投票时的方向
   * @param vote       服务端回来的该方向票数（**0 表示这次是取消**）
   */
  static applyVoteResult(comment: GalleryComment, score: number, expectVote: number,
    vote: number): void {
    comment.score = score;
    if (expectVote > 0) {
      comment.voteUpEd = 0 !== vote;
      comment.voteDownEd = false;
    } else {
      comment.voteDownEd = 0 !== vote;
      comment.voteUpEd = false;
    }
  }

  /**
   * 投票成功的提示文案（上游 `VoteCommentListener.onSuccess` 的四分支）。
   *
   * 判据是**两个布尔**：期望方向（赞/踩）× 这次是投票还是取消（`vote != 0`）。
   */
  static voteToastOf(expectVote: number, vote: number): string {
    if (expectVote > 0) {
      return 0 !== vote ? 'vote_up_successfully' : 'cancel_vote_up_successfully';
    }
    return 0 !== vote ? 'vote_down_successfully' : 'cancel_vote_down_successfully';
  }

  /** 投票失败的提示文案（上游 `onFailure` 唯一文案）。 */
  static readonly VOTE_FAILED_RES: string = 'vote_failed';

  /**
   * 长按评论弹出的菜单项（上游 `onLongClick` 的五分支，顺序照搬）。
   *
   * 依次是：赞/取消赞（`voteUpAble`）→ 踩/取消踩（`voteDownAble`）→ 查看投票状态（`voteState` 非空）。
   * 注意"可投票"与"已投过"是**不同布尔**：`voteUpAble` 决定是否显示，`voteUpEd` 决定文案是"取消"还是"投票"。
   */
  static voteMenuOf(comment: GalleryComment): string[] {
    const items: string[] = [];
    if (comment.voteUpAble) {
      items.push(comment.voteUpEd ? 'cancel_vote_up' : 'vote_up');
    }
    if (comment.voteDownAble) {
      items.push(comment.voteDownEd ? 'cancel_vote_down' : 'vote_down');
    }
    if (comment.voteState !== null && comment.voteState.length > 0) {
      items.push('check_vote_status');
    }
    return items;
  }

  /**
   * `showAllComments` 的初值（上游 `handleArgs`/`onRestore` 两处同一表达式）。
   *
   * `commentList !== null && !commentList.hasMore` —— 即"拿到的列表已经是全量"时，
   * More 按钮从一开始就不该出现。**Part 1 里初始写死 false 是个缺口**：那会让已全量的场景
   * 仍然显示 More，点一下再请求一次同样的数据。
   */
  static initialShowAll(commentList: GalleryCommentList | null): boolean {
    return commentList !== null && !commentList.hasMore;
  }

  /**
   * 刷新失败后要刷新的行（上游 `onRefreshGalleryFailure`）。
   *
   * 上游只刷**最后一行**（`getItemCount() - 1`），因为 loading/error 行在末尾；
   * 空表（position < 0）则不刷。
   */
  static refreshFailureRow(itemCount: number): number {
    const position: number = itemCount - 1;
    return position >= 0 ? position : -1;
  }
}