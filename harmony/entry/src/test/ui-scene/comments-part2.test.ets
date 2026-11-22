/*
 * download-sync 接手批单测：GalleryCommentsScene Part 2（S0249）的判据层
 *
 * 钉住的语义（都是"写错也能编译、但投票/评论行为会错"）：
 *   ① 上游**不是乐观更新**：请求前不改 UI；失败只提示 `vote_failed`，不回滚
 *   ② 投票结果的**互斥**：赞时清踩、踩时清赞（漏掉会"赞踩同时亮"）
 *   ③ 成功提示四分支：期望方向 × 是否取消（`vote != 0`）
 *   ④ 长按菜单五分支：voteUpAble / voteDownAble / voteState（**可投 ≠ 已投**）
 *   ⑤ `showAllComments` 初值 = `列表非空 && !hasMore`（已全量时不该显示 More）
 *   ⑥ 刷新失败只刷**最后一行**（loading 行在末尾），空表不刷
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import { GalleryCommentsScene } from '../../main/ets/hippo/ehviewer/ui/scene/GalleryCommentsScene';
import { GalleryComment } from '../../main/ets/hippo/ehviewer/client/data/GalleryComment';
import { GalleryCommentList } from '../../main/ets/hippo/ehviewer/client/data/GalleryCommentList';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}  (want true)`);
  }
}

function comment(id: number, score: number): GalleryComment {
  const c: GalleryComment = new GalleryComment();
  c.id = id;
  c.score = score;
  c.voteUpAble = true;
  c.voteDownAble = true;
  c.voteState = '';
  return c;
}

// ---------------------------------------------------------------- 投票结果应用（互斥）

function testApplyVoteResult(): void {
  // ① 赞（vote=1）→ voteUpEd=true 且 **踩被清掉**
  const c1: GalleryComment = comment(1, 5);
  c1.voteDownEd = true;   // 之前踩过
  GalleryCommentsScene.applyVoteResult(c1, 6, 1, 1);
  eq('赞：score 用服务端值', c1.score, 6);
  eq('赞：voteUpEd=true', c1.voteUpEd, true);
  eq('赞：**踩被清掉**（互斥）', c1.voteDownEd, false);

  // ② 取消赞（vote=0）→ voteUpEd=false，踩仍清
  const c2: GalleryComment = comment(2, 7);
  c2.voteUpEd = true;
  c2.voteDownEd = true;
  GalleryCommentsScene.applyVoteResult(c2, 6, 1, 0);
  eq('取消赞：voteUpEd=false', c2.voteUpEd, false);
  eq('取消赞：踩仍为 false', c2.voteDownEd, false);

  // ③ 踩（expectVote=-1, vote=1）→ voteDownEd=true 且 **赞被清掉**
  const c3: GalleryComment = comment(3, 5);
  c3.voteUpEd = true;
  GalleryCommentsScene.applyVoteResult(c3, 4, -1, 1);
  eq('踩：voteDownEd=true', c3.voteDownEd, true);
  eq('踩：**赞被清掉**（互斥）', c3.voteUpEd, false);

  // ④ 取消踩
  const c4: GalleryComment = comment(4, 4);
  c4.voteDownEd = true;
  GalleryCommentsScene.applyVoteResult(c4, 5, -1, 0);
  eq('取消踩：voteDownEd=false', c4.voteDownEd, false);
  eq('取消踩：赞也是 false', c4.voteUpEd, false);

  // ⑤ expectVote 的判据是 "> 0"，不是 "== 1"
  const c5: GalleryComment = comment(5, 0);
  GalleryCommentsScene.applyVoteResult(c5, 1, 2, 1);
  eq('expectVote=2 也当赞（判据是 >0）', c5.voteUpEd, true);
  eq('expectVote=2 时踩为 false', c5.voteDownEd, false);
}

// ---------------------------------------------------------------- 成功提示四分支

function testVoteToast(): void {
  eq('赞成功', GalleryCommentsScene.voteToastOf(1, 1), 'vote_up_successfully');
  eq('取消赞成功', GalleryCommentsScene.voteToastOf(1, 0), 'cancel_vote_up_successfully');
  eq('踩成功', GalleryCommentsScene.voteToastOf(-1, 1), 'vote_down_successfully');
  eq('取消踩成功', GalleryCommentsScene.voteToastOf(-1, 0), 'cancel_vote_down_successfully');
  // vote 只看是否为 0，不看正负
  eq('vote=5 也算"已投"', GalleryCommentsScene.voteToastOf(1, 5), 'vote_up_successfully');
  eq('vote=-1 也算"已投"', GalleryCommentsScene.voteToastOf(-1, -1), 'vote_down_successfully');
  eq('失败文案唯一', GalleryCommentsScene.VOTE_FAILED_RES, 'vote_failed');
}

// ---------------------------------------------------------------- 长按菜单五分支

function testVoteMenu(): void {
  // ① 两个都能投、都没投过、无状态 → 两项
  const a: GalleryComment = comment(1, 0);
  eq('可投未投 → 投票/投踩', GalleryCommentsScene.voteMenuOf(a), ['vote_up', 'vote_down']);

  // ② 已投赞 → 文案变"取消赞"
  const b: GalleryComment = comment(2, 1);
  b.voteUpEd = true;
  eq('已投赞 → 取消赞', GalleryCommentsScene.voteMenuOf(b), ['cancel_vote_up', 'vote_down']);

  // ③ 已投踩 → 文案变"取消踩"
  const c: GalleryComment = comment(3, 1);
  c.voteDownEd = true;
  eq('已投踩 → 取消踩', GalleryCommentsScene.voteMenuOf(c), ['vote_up', 'cancel_vote_down']);

  // ④ 上传者评论（id=0）：Able 都是 false → 菜单为空
  const uploader: GalleryComment = new GalleryComment();
  uploader.id = 0;
  uploader.voteUpAble = false;
  uploader.voteDownAble = false;
  eq('上传者评论 → 空菜单', GalleryCommentsScene.voteMenuOf(uploader), []);

  // ⑤ 有 voteState → 追加"查看投票状态"
  const d: GalleryComment = comment(4, 2);
  d.voteState = '1,2,3';
  eq('有投票状态 → 追加第三项', GalleryCommentsScene.voteMenuOf(d),
    ['vote_up', 'vote_down', 'check_vote_status']);

  // ⑥ 只有踩可投
  const e: GalleryComment = comment(5, 0);
  e.voteUpAble = false;
  eq('只有踩可投 → 只有一项', GalleryCommentsScene.voteMenuOf(e), ['vote_down']);

  // ⑦ voteState 为空串 → 不追加
  const f: GalleryComment = comment(6, 0);
  f.voteState = '';
  eq('voteState 空串 → 不追加', GalleryCommentsScene.voteMenuOf(f), ['vote_up', 'vote_down']);
}

// ---------------------------------------------------------------- showAll 初值

function testInitialShowAll(): void {
  eq('null 列表 → false', GalleryCommentsScene.initialShowAll(null), false);

  const withMore: GalleryCommentList = new GalleryCommentList([comment(1, 0)], true);
  eq('hasMore=true → false（要显示 More）', GalleryCommentsScene.initialShowAll(withMore), false);

  const full: GalleryCommentList = new GalleryCommentList([comment(1, 0)], false);
  eq('hasMore=false → true（已全量，不显示 More）', GalleryCommentsScene.initialShowAll(full), true);

  const empty: GalleryCommentList = new GalleryCommentList([], false);
  eq('空表且 hasMore=false → true', GalleryCommentsScene.initialShowAll(empty), true);
}

// ---------------------------------------------------------------- 刷新失败的行

function testRefreshFailureRow(): void {
  eq('10 行 → 刷第 10 行（下标 9）', GalleryCommentsScene.refreshFailureRow(10), 9);
  eq('1 行 → 刷第 1 行（下标 0）', GalleryCommentsScene.refreshFailureRow(1), 0);
  eq('0 行 → 不刷（-1）', GalleryCommentsScene.refreshFailureRow(0), -1);
  eq('负行数 → 不刷', GalleryCommentsScene.refreshFailureRow(-3), -1);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testApplyVoteResult();
  testVoteToast();
  testVoteMenu();
  testInitialShowAll();
  testRefreshFailureRow();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync comments part2 test failed');
  }
  console.log(`✓ download-sync 评论 Part2 批: ${pass} 条断言全部通过`);
}

main();
