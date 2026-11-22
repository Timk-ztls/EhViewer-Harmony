/*
 * download-sync 接手批单测：GalleryListSceneDialog（S0243）+ QuickSearchScene（S0244）
 *
 * 钉住的语义（都是"写错也能编译、但菜单/排序会错"）：
 *   ① 标签定义用 **冒号后 temp**，过滤/订阅用 **全串 tagName**
 *   ② 按钮组两套，且"复制"的**槽位随登录状态变化**（negative ↔ neutral）
 *   ③ 订阅 body 两字段**互斥**（tagWatchNew / tagHiddenNew 只写一个）
 *   ④ onMoveItem：from==to **不落库不换实例**；先落库后改内存
 *   ⑤ 删除：先删库再删内存；越界返回原数组
 *   ⑥ updateView：null 与空数组都算空态
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  GalleryListSceneDialog, TagMenuItem, DialogButton, TagLongPressPlan, TagFilterSpec, TagPushBody
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/GalleryListSceneDialog';
import {
  QuickSearchScene, QuickSearchView, QuickSearchItem, NoopQuickSearchStore
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/QuickSearchScene';

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

function item(name: string): QuickSearchItem {
  return { name: name };
}

function namesOf(items: QuickSearchItem[]): string[] {
  return items.map((i: QuickSearchItem): string => i.name);
}

// ---------------------------------------------------------------- ① 冒号后 vs 全串

function testTagNameSplit(): void {
  eq('带命名空间 → 取冒号后', GalleryListSceneDialog.definitionTagOf('female:swimsuit'), 'swimsuit');
  eq('无冒号 → 原样', GalleryListSceneDialog.definitionTagOf('swimsuit'), 'swimsuit');
  eq('冒号在末尾 → 空串', GalleryListSceneDialog.definitionTagOf('ns:'), '');
  eq('多个冒号 → 只切第一个之后',
    GalleryListSceneDialog.definitionTagOf('a:b:c'), 'b:c');

  // 计划里两个字段不同：definitionTag 是冒号后，filterTag 是全串
  const plan: TagLongPressPlan =
    GalleryListSceneDialog.planOf('female:swimsuit', false, '', true);
  eq('定义页用冒号后', plan.definitionTag, 'swimsuit');
  eq('过滤用全串', plan.filterTag, 'female:swimsuit');
}

// ---------------------------------------------------------------- ② 标题

function testTitle(): void {
  eq('不显示翻译 → 纯 tagName',
    GalleryListSceneDialog.titleOf('female:swimsuit', false, '女性:泳装'), 'female:swimsuit');
  eq('显示翻译 → 中文(tagName)',
    GalleryListSceneDialog.titleOf('female:swimsuit', true, '女性:泳装'), '女性:泳装(female:swimsuit)');
}

// ---------------------------------------------------------------- ③ 按钮组两套

function testButtons(): void {
  const anon: DialogButton[] = GalleryListSceneDialog.buttonsFor(false);
  eq('未登录只有 1 个按钮', anon.length, 1);
  eq('未登录：复制在 negative', anon[0].slot, 'negative');
  eq('未登录：文案 copy_tag', anon[0].textRes, 'copy_tag');

  const logged: DialogButton[] = GalleryListSceneDialog.buttonsFor(true);
  eq('已登录 3 个按钮', logged.length, 3);
  eq('已登录：复制移到 neutral', logged[0].slot, 'neutral');
  eq('已登录：复制文案不变', logged[0].textRes, 'copy_tag');
  eq('已登录：negative 是关注', logged[1].slot, 'negative');
  eq('已登录：关注文案', logged[1].textRes, 'subscription_watched');
  eq('已登录：positive 是隐藏', logged[2].slot, 'positive');
  eq('已登录：隐藏文案', logged[2].textRes, 'subscription_hidden');

  // 关键差异断言：复制槽位在两种状态下不同
  ok('复制的槽位随登录状态变化（negative ≠ neutral）', anon[0].slot !== logged[0].slot);
}

// ---------------------------------------------------------------- ④ 过滤 / 订阅 body

function testFilterAndPush(): void {
  const spec: TagFilterSpec = GalleryListSceneDialog.filterSpecOf('female:swimsuit');
  eq('过滤 mode = MODE_TAG', spec.mode, 'MODE_TAG');
  eq('过滤 text = 全串', spec.text, 'female:swimsuit');

  const watch: TagPushBody = GalleryListSceneDialog.pushBodyOf('female:swimsuit', true);
  eq('关注：tagNameNew', watch.tagNameNew, 'female:swimsuit');
  eq('关注：tagWatchNew=on', watch.tagWatchNew, 'on');
  eq('关注：tagHiddenNew **为空**（互斥）', watch.tagHiddenNew, '');

  const hide: TagPushBody = GalleryListSceneDialog.pushBodyOf('female:swimsuit', false);
  eq('隐藏：tagWatchNew **为空**（互斥）', hide.tagWatchNew, '');
  eq('隐藏：tagHiddenNew=on', hide.tagHiddenNew, 'on');
  eq('两种 body 不会同时有两个 on',
    (watch.tagWatchNew === 'on' ? 1 : 0) + (watch.tagHiddenNew === 'on' ? 1 : 0), 1);

  eq('关注的状态名', GalleryListSceneDialog.subscriptionStateRes(true), 'subscription_watched');
  eq('隐藏的状态名', GalleryListSceneDialog.subscriptionStateRes(false), 'subscription_hidden');
  eq('成功文案资源', GalleryListSceneDialog.SUBSCRIPTION_SUCCESS_RES, 'subscription_success');

  // 菜单项索引
  eq('菜单项 0 = 打开定义', TagMenuItem.OPEN_TAG_DEFINITION, 0);
  eq('菜单项 1 = 加入过滤', TagMenuItem.FILTER_TAG, 1);
}

// ---------------------------------------------------------------- ⑤ 空态

function testQuickSearchView(): void {
  eq('null → 空态', QuickSearchScene.viewFor(null), QuickSearchView.EMPTY);
  eq('空数组 → 空态', QuickSearchScene.viewFor([]), QuickSearchView.EMPTY);
  eq('非空 → 列表', QuickSearchScene.viewFor([item('a')]), QuickSearchView.LIST);
  eq('删除确认标题资源', QuickSearchScene.DELETE_TITLE_RES, 'delete_quick_search_title');
  eq('删除确认正文资源', QuickSearchScene.DELETE_MESSAGE_RES, 'delete_quick_search_message');
  eq('确认正文参数是名称', QuickSearchScene.deleteMessageArgOf(item('blue archive')), 'blue archive');
}

// ---------------------------------------------------------------- ⑥ 删除

function testDelete(): void {
  const store: NoopQuickSearchStore = new NoopQuickSearchStore();
  const items: QuickSearchItem[] = [item('a'), item('b'), item('c')];

  const after: QuickSearchItem[] = QuickSearchScene.applyDelete(items, 1, store);
  eq('删除第 2 项 → 剩 2 项', after.length, 2);
  eq('剩下 a,c', namesOf(after), ['a', 'c']);
  eq('落库删的是 b', store.deleted, ['b']);
  eq('原数组未被修改（不可变返回）', namesOf(items), ['a', 'b', 'c']);

  // 越界 → 原数组
  const store2: NoopQuickSearchStore = new NoopQuickSearchStore();
  eq('越界（-1）→ 原数组', QuickSearchScene.applyDelete(items, -1, store2) === items, true);
  eq('越界（3）→ 原数组', QuickSearchScene.applyDelete(items, 3, store2) === items, true);
  eq('越界不落库', store2.deleted, []);

  // 删到空 → 视图变空态
  const one: QuickSearchItem[] = [item('only')];
  const empty: QuickSearchItem[] = QuickSearchScene.applyDelete(one, 0, new NoopQuickSearchStore());
  eq('删完 → 空态', QuickSearchScene.viewFor(empty), QuickSearchView.EMPTY);
}

// ---------------------------------------------------------------- ⑦ 拖拽排序

function testMove(): void {
  const items: QuickSearchItem[] = [item('a'), item('b'), item('c')];

  // 0 → 2：a 移到末尾
  const s1: NoopQuickSearchStore = new NoopQuickSearchStore();
  const m1: QuickSearchItem[] = QuickSearchScene.applyMove(items, 0, 2, s1);
  eq('0→2 结果 b,c,a', namesOf(m1), ['b', 'c', 'a']);
  eq('0→2 落库一次', s1.moved, ['0->2']);

  // 2 → 0：c 移到开头
  const s2: NoopQuickSearchStore = new NoopQuickSearchStore();
  eq('2→0 结果 c,a,b', namesOf(QuickSearchScene.applyMove(items, 2, 0, s2)), ['c', 'a', 'b']);
  eq('2→0 落库一次', s2.moved, ['2->0']);

  // from == to：**不落库、返回同一个数组实例**
  const s3: NoopQuickSearchStore = new NoopQuickSearchStore();
  const same: QuickSearchItem[] = QuickSearchScene.applyMove(items, 1, 1, s3);
  eq('from==to 返回同一实例', same === items, true);
  eq('from==to **不落库**', s3.moved, []);

  // 越界：不落库
  const s4: NoopQuickSearchStore = new NoopQuickSearchStore();
  eq('from 越界 → 原实例', QuickSearchScene.applyMove(items, 5, 0, s4) === items, true);
  eq('to 越界 → 原实例', QuickSearchScene.applyMove(items, 0, 5, s4) === items, true);
  eq('越界不落库', s4.moved, []);

  // 拖拽恒允许
  eq('canDrop 恒 true（无论位置）', QuickSearchScene.canDrop(0, 9), true);
  eq('canDrop 同位置也 true', QuickSearchScene.canDrop(3, 3), true);

  // 原数组不被改
  eq('原数组保持 a,b,c', namesOf(items), ['a', 'b', 'c']);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testTagNameSplit();
  testTitle();
  testButtons();
  testFilterAndPush();
  testQuickSearchView();
  testDelete();
  testMove();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync list-dialog/quick-search test failed');
  }
  console.log(`✓ download-sync 标签菜单+快速搜索批: ${pass} 条断言全部通过`);
}

main();
