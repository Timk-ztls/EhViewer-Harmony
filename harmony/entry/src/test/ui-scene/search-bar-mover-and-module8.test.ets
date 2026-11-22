/*
 * Module 8 regression tests:
 *   - SearchBarMoverState (showSearchBar, applyScrollDelta clamp, resolveTargetShow clauses, returnSearchBarPosition, onOffsetChanged)
 *   - QuickSearch + ListUrlBuilder.copyFromQuickSearch + QuickSearchScene
 *   - DownloadsSceneShell KEY_LABEL arguments + ListCheckBoxDialogSpec
 *
 * Run: pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter search-bar-mover
 */

import { SearchBarMoverState, SearchBarMoverHelperImpl } from '../../main/ets/hippo/widget/SearchBarMover';
import { QuickSearch } from '../../main/ets/hippo/ehviewer/dao/QuickSearch';
import { ListUrlBuilder } from '../../main/ets/hippo/ehviewer/client/data/ListUrlBuilder';
import {
  QuickSearchItem,
  QuickSearchScene,
  QuickSearchView,
  NoopQuickSearchStore
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/QuickSearchScene';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';
import { DownloadsSceneShell } from '../../main/ets/hippo/ehviewer/ui/scene/download/DownloadsSceneShell';
import { DownloadsSceneAction, DownloadManagerLike } from '../../main/ets/hippo/ehviewer/ui/scene/download/DownloadsScene';
import { ListCheckBoxDialogSpec, OnItemClickListener } from '../../main/ets/hippo/app/DialogSpecs';
import { SceneArgs } from '../../main/ets/hippo/scene/SceneTypes';
import {
  SearchHistoryKvStore,
  SearchHistoryPrefsStore,
  SearchTagQueryHelper
} from '../../main/ets/hippo/ehviewer/widget/SearchDatabase';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
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
    fails.push(`${name}\n    expected true`);
  }
}

class FakeDownloadManager implements DownloadManagerLike {
  getDownloadInfoList(): DownloadInfo[] { return []; }
  getDefaultDownloadInfoList(): DownloadInfo[] { return []; }
  getLabelDownloadInfoList(label: string): DownloadInfo[] | null {
    if (label === 'favs') {
      const info: DownloadInfo = new DownloadInfo();
      info.gid = 42;
      info.label = 'favs';
      return [info];
    }
    return null;
  }
}

class QuickEntryAdapter implements QuickSearchItem {
  readonly name: string;
  constructor(name: string) { this.name = name; }
}

class CaptureClickListener implements OnItemClickListener {
  clickedPos: number = -1;
  onItemClick(position: number): void {
    this.clickedPos = position;
  }
}

function testSearchBarMoverState(): void {
  const mover: SearchBarMoverState = new SearchBarMoverState();
  eq('height=0 early delta=0', mover.applyScrollDelta(20), 0);
  eq('height=0 resolveTargetShow stays true', mover.resolveTargetShow(), true);

  let forceShow: boolean = false;
  let validId: number = 0;
  let shown: boolean = true;
  let canScroll: boolean = true;

  mover.helper = new SearchBarMoverHelperImpl(
    (id: number): boolean => id === 0,
    (): number => validId,
    (): boolean => forceShow
  );
  mover.isViewShown = (): boolean => shown;
  mover.canScrollUp = (): boolean => canScroll;
  mover.setMetrics(140, 0, 140);

  const step1: number = mover.applyScrollDelta(40);
  eq('scroll up 40 moves -40', step1, -40);
  eq('translationY=-40', mover.translationY, -40);
  eq('still shown under half', mover.isShown(), true);

  const step2: number = mover.applyScrollDelta(40);
  eq('scroll up +40 moves -40 -> -80', step2, -40);
  eq('translationY=-80', mover.translationY, -80);
  eq('hidden past half', mover.isShown(), false);

  const step3: number = mover.applyScrollDelta(200);
  eq('clamped at -140', mover.translationY, -140);
  ok('step3 moved remaining -60', step3 === -60);

  eq('returnSearchBarPosition snaps to hidden', mover.returnSearchBarPosition(true), false);
  eq('snapped translationY=-140', mover.translationY, -140);
  eq('isAnimating after return', mover.isAnimating(), true);
  mover.cancelAnimation();
  eq('cancelAnimation clears flag', mover.isAnimating(), false);

  forceShow = true;
  eq('forceShow overrides hidden', mover.returnSearchBarPosition(true), true);
  eq('forced translationY=0', mover.translationY, 0);
  forceShow = false;

  mover.applyScrollDelta(90);
  shown = false;
  eq('view hidden forces hide', mover.resolveTargetShow(), false);
  shown = true;

  canScroll = false;
  eq('cannot scroll up forces show', mover.resolveTargetShow(), true);
  canScroll = true;

  mover.showSearchBar(false);
  eq('showSearchBar resets translationY=0', mover.translationY, 0);
  eq('showSearchBar sets shown=true', mover.isShown(), true);

  eq('onOffsetChanged first event baseline', mover.onOffsetChanged(100), 0);
  eq('onOffsetChanged +50 scrolls -50', mover.onOffsetChanged(150), -50);
  eq('onOffsetChanged idle returns show=true (50 <= 70)', mover.onScrollIdle(), true);
}

function testQuickSearchAndUrlBuilder(): void {
  const qs: QuickSearch = new QuickSearch();
  qs.setName('CG preset');
  qs.setMode(ListUrlBuilder.MODE_NORMAL);
  qs.setKeyword('artist:example');
  qs.setCategory(0);

  const ub: ListUrlBuilder = new ListUrlBuilder();
  ub.copyFromQuickSearch(qs);
  const built: string = ub.build();
  ok('quicksearch url contains keyword', built.indexOf('artist') >= 0 && built.indexOf('example') >= 0);

  const store: NoopQuickSearchStore = new NoopQuickSearchStore();
  const entries: QuickSearchItem[] = [new QuickEntryAdapter('A'), new QuickEntryAdapter('B')];
  eq('viewFor non-empty = LIST', QuickSearchScene.viewFor(entries), QuickSearchView.LIST);
  const moved: QuickSearchItem[] = QuickSearchScene.applyMove(entries, 0, 1, store);
  eq('applyMove first element', moved[0].name, 'B');
  const deleted: QuickSearchItem[] = QuickSearchScene.applyDelete(moved, 0, store);
  eq('applyDelete remaining count', deleted.length, 1);
  eq('viewFor empty = EMPTY', QuickSearchScene.viewFor([]), QuickSearchView.EMPTY);
}

function testDownloadsLabelAndListCheckBoxSpec(): void {
  const shell: DownloadsSceneShell = new DownloadsSceneShell(new FakeDownloadManager());
  const args: SceneArgs = new Map<string, Object>();
  args.set(DownloadsSceneAction.KEY_LABEL, 'favs');
  shell.setArguments(args);
  ok('handleArguments KEY_LABEL returns true', shell.getLogic().handleArguments(shell.getArguments()));
  eq('label set to favs', shell.getLogic().getLabel(), 'favs');
  eq('filtered downloads count = 1', shell.getLogic().getList().length, 1);

  const spec: ListCheckBoxDialogSpec = new ListCheckBoxDialogSpec(['Local', 'Slot 0'], 'Remember', false);
  spec.markReady();
  spec.checked = true;
  const listener: CaptureClickListener = new CaptureClickListener();
  ok('onItemClick valid pos = true', spec.onItemClick(1, listener));
  eq('listener receives position 1', listener.clickedPos, 1);
  eq('checked preserves selection', spec.isChecked(), true);
}

class MemoryTestKvStore implements SearchHistoryKvStore {
  private readonly map: Map<string, string> = new Map<string, string>();
  getString(key: string, defValue: string): string {
    const v: string | undefined = this.map.get(key);
    return v !== undefined ? v : defValue;
  }
  putString(key: string, value: string): void {
    this.map.set(key, value);
  }
}

function testSearchHistoryAndTagQueryHelpers(): void {
  const kv: MemoryTestKvStore = new MemoryTestKvStore();
  SearchHistoryPrefsStore.configureStore(kv);
  SearchHistoryPrefsStore.clearQuery();

  SearchHistoryPrefsStore.addQuery('touhou', 100);
  SearchHistoryPrefsStore.addQuery('Touhou Project', 200);
  SearchHistoryPrefsStore.addQuery('blue archive', 300);
  SearchHistoryPrefsStore.addQuery('touhou', 400); // dedupes & promotes MRU

  const all: string[] = SearchHistoryPrefsStore.getSuggestions('', 10);
  eq('history MRU promoted after dedupe', all, ['touhou', 'blue archive', 'Touhou Project']);

  const pref: string[] = SearchHistoryPrefsStore.getSuggestions('To', 10);
  eq('history prefix match case-insensitive', pref, ['touhou', 'Touhou Project']);

  const exclExact: string[] = SearchHistoryPrefsStore.getSuggestions('touhou', 10);
  eq('history excludes exact query equality', exclExact, ['Touhou Project']);

  SearchHistoryPrefsStore.deleteQuery('Touhou Project');
  eq('history deleteQuery removes only exact match', SearchHistoryPrefsStore.getSuggestions('', 10), ['touhou', 'blue archive']);

  // Upstream SearchBar multi-tag token extraction & replacement
  eq('extractTagKeyword simple', SearchTagQueryHelper.extractTagKeyword('swim'), 'swim');
  eq('extractTagKeyword after structured token', SearchTagQueryHelper.extractTagKeyword('l:"chinese$" f:"fox" bunny girl'), 'bunny girl');
  eq('extractTagKeyword none when structured only', SearchTagQueryHelper.extractTagKeyword('f:"maid$"'), '');

  const prefixMap = (ns: string): string | null => ns === 'female' ? 'f:' : (ns === 'misc' ? '' : null);
  eq('formatTagToken mapped ns', SearchTagQueryHelper.formatTagToken('female:fox girl', prefixMap), 'f:"fox girl$"');
  eq('formatTagToken misc empty prefix', SearchTagQueryHelper.formatTagToken('misc:full color', prefixMap), '"full color$"');

  eq('replaceTrailingKeyword single', SearchTagQueryHelper.replaceTrailingKeyword('fox', 'f:"fox girl$"'), 'f:"fox girl$"');
  eq('replaceTrailingKeyword preserves earlier tags',
    SearchTagQueryHelper.replaceTrailingKeyword('l:"chinese$" fox girl', 'f:"fox girl$"'),
    'l:"chinese$" f:"fox girl$"');
}

function main(): void {
  testSearchBarMoverState();
  testQuickSearchAndUrlBuilder();
  testDownloadsLabelAndListCheckBoxSpec();
  testSearchHistoryAndTagQueryHelpers();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('search-bar-mover-and-module8 test failed');
  }
  console.log(`✓ Module 8 search-bar-mover-and-module8 批: ${pass} 条断言全部通过`);
}

main();
