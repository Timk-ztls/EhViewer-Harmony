/*
 * download-sync 接手批单测：WiFi 传书发送/接收两条（S0276 / S0275）的纯逻辑
 *
 * 定位：这两条上游是 Activity（535 + 413 行），UI 部分在 ArkUI 侧重写；
 * 但**协议编排**是可断言的：分页公式、"总页数写进 pageSize 字段"、目录键、
 * 按钮文本四分支、AP IPv4 选取、ack 后推进队列 —— 这些写错的后果都是"传一半卡住"或
 * "对端只收到一页"，肉眼极难发现。
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  WiFiServerActivity, WiFiServerMenu, WiFiServerAction, NetworkInterfaceLike, StatusButtonState
} from '../../main/ets/hippo/ehviewer/ui/wifi/WiFiServerActivity';

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
    fails.push(`${name}  (want true)`);
  }
}

// ---------------------------------------------------------------- totalPage

function testTotalPage(): void {
  // 向上取整（上游 `totalPage`）：不足一页也要算一页
  eq('1 条 → 1 页', WiFiServerActivity.totalPage(1, 10), 1);
  eq('恰好一页 10 → 1', WiFiServerActivity.totalPage(10, 10), 1);
  eq('11 条 → 2 页（**向上取整**，不是 1）', WiFiServerActivity.totalPage(11, 10), 2);
  eq('20 条 → 2 页', WiFiServerActivity.totalPage(20, 10), 2);
  eq('21 条 → 3 页', WiFiServerActivity.totalPage(21, 10), 3);
  // 零条 → 零页（上游 a=0,b=0 → 返回 0）—— 零页意味着一帧都不发，不能算成 1 页
  eq('0 条 → 0 页（**不是 1**）', WiFiServerActivity.totalPage(0, 10), 0);
  // pageSize <= 0 防御（上游会除零崩，这里显式返回 0）
  eq('pageSize=0 → 0（防除零）', WiFiServerActivity.totalPage(5, 0), 0);
}

// ---------------------------------------------------------------- dirKey

function testDirKey(): void {
  eq('目录键 = gid:dirname', WiFiServerActivity.dirKey(123, 'dirA'), '123:dirA');
  eq('不同 gid 同 dirname 不撞键',
    WiFiServerActivity.dirKey(1, 'x') === WiFiServerActivity.dirKey(2, 'x'), false);
}

// ---------------------------------------------------------------- planStatusChange

function testPlanStatusChange(): void {
  // 顺序关键：sending 优先于队列
  eq('发送中（队列非空）→ STOP（不是 SEND_NEXT）',
    WiFiServerActivity.planStatusChange(true, false, WiFiServerMenu.FAVORITE), WiFiServerAction.STOP);
  eq('发送中（队列空）→ 仍 STOP',
    WiFiServerActivity.planStatusChange(true, true, WiFiServerMenu.FAVORITE), WiFiServerAction.STOP);
  eq('未发送 + 队列非空 → SEND_NEXT（继续发，不重建数据）',
    WiFiServerActivity.planStatusChange(false, false, WiFiServerMenu.FAVORITE), WiFiServerAction.SEND_NEXT);
  // 队列空 + 未发送 → 按菜单造数据
  eq('menu 0 → 书签',
    WiFiServerActivity.planStatusChange(false, true, WiFiServerMenu.BOOKMARK), WiFiServerAction.BUILD_BOOKMARK);
  eq('menu 1 → 收藏',
    WiFiServerActivity.planStatusChange(false, true, WiFiServerMenu.FAVORITE), WiFiServerAction.BUILD_FAVORITE);
  eq('menu 2 → 下载',
    WiFiServerActivity.planStatusChange(false, true, WiFiServerMenu.DOWNLOAD), WiFiServerAction.BUILD_DOWNLOAD);
  eq('menu 3 → 下载目录',
    WiFiServerActivity.planStatusChange(false, true, WiFiServerMenu.DOWNLOAD_DIR), WiFiServerAction.BUILD_DOWNLOAD_DIR);
  // 未选中（onNothingSelected 写的 999）→ 不造数据
  eq('menu 999（未选中）→ NONE',
    WiFiServerActivity.planStatusChange(false, true, WiFiServerActivity.SELECT_INDEX_NONE), WiFiServerAction.NONE);
}

// ---------------------------------------------------------------- statusButtonState

function testStatusButtonState(): void {
  const idle: StatusButtonState = WiFiServerActivity.statusButtonState(false, 0);
  eq('空闲 + 空队列 → 开始（无后缀）', [idle.resKey, idle.suffix], ['wifi_send_start', '']);

  const idleQueued: StatusButtonState = WiFiServerActivity.statusButtonState(false, 3);
  eq('空闲 + 队列 3 → 开始(3)', [idleQueued.resKey, idleQueued.suffix], ['wifi_send_start', '(3)']);

  const sending: StatusButtonState = WiFiServerActivity.statusButtonState(true, 0);
  eq('发送中 + 空队列 → 停止（无后缀）', [sending.resKey, sending.suffix], ['wifi_send_stop', '']);

  const sendingQueued: StatusButtonState = WiFiServerActivity.statusButtonState(true, 7);
  eq('发送中 + 队列 7 → 停止(7)', [sendingQueued.resKey, sendingQueued.suffix], ['wifi_send_stop', '(7)']);
}

// ---------------------------------------------------------------- pickWlanIpv4

function testPickWlanIpv4(): void {
  // 只认 wlan* 网卡
  eq('非 wlan 网卡被跳过',
    WiFiServerActivity.pickWlanIpv4([
      new NetworkInterfaceLike('eth0', ['192.168.1.5'], [true])
    ]), null);

  eq('wlan0 的 IPv4 被选中',
    WiFiServerActivity.pickWlanIpv4([
      new NetworkInterfaceLike('wlan0', ['192.168.43.1'], [true])
    ]), '192.168.43.1');

  // 回环必须排除（上游 `!inetAddress.isLoopbackAddress()`）
  eq('wlan0 上的回环被排除',
    WiFiServerActivity.pickWlanIpv4([
      new NetworkInterfaceLike('wlan0', ['127.0.0.1', '10.0.0.7'], [true, true])
    ]), '10.0.0.7');

  // IPv6 不算（上游 getAddress().length == 4）
  eq('IPv6 被跳过，取后面的 IPv4',
    WiFiServerActivity.pickWlanIpv4([
      new NetworkInterfaceLike('wlan0', ['fe80::1', '10.0.0.8'], [false, true])
    ]), '10.0.0.8');

  eq('全平台无 wlan → null',
    WiFiServerActivity.pickWlanIpv4([]), null);
}

// ---------------------------------------------------------------- 权限与状态机

function testPermissionAndState(): void {
  eq('已授权 → 不需申请', WiFiServerActivity.isPermissionRequired(true), false);
  eq('未授权 → 需申请', WiFiServerActivity.isPermissionRequired(false), true);

  const server: WiFiServerActivity = new WiFiServerActivity();
  eq('初始不在发送', server.isSending(), false);
  eq('初始队列 0', server.queueSize(), 0);
  eq('初始按钮=开始', server.statusButton().resKey, 'wifi_send_start');

  // Spinner 选中 → 按下按钮 → 应该去造对应数据，并把 sending 置真
  server.onItemSelected(WiFiServerMenu.DOWNLOAD_DIR);
  eq('选中 menu 3', server.currentSelectIndex(), WiFiServerMenu.DOWNLOAD_DIR);
  eq('按下 → BUILD_DOWNLOAD_DIR', server.onStatusChange(), WiFiServerAction.BUILD_DOWNLOAD_DIR);
  eq('按下后进入发送态', server.isSending(), true);

  // 再按一次 → STOP 并清队列
  eq('再按 → STOP', server.onStatusChange(), WiFiServerAction.STOP);
  eq('停止后不在发送', server.isSending(), false);
  eq('停止后队列空', server.queueSize(), 0);

  // onNothingSelected → 999 → 按按钮不造数据
  server.onNothingSelected();
  eq('未选中 → 999', server.currentSelectIndex(), WiFiServerActivity.SELECT_INDEX_NONE);
  eq('未选中按按钮 → NONE', server.onStatusChange(), WiFiServerAction.NONE);
  eq('NONE 不置 sending', server.isSending(), false);
}

// ---------------------------------------------------------------- 无连接时的发送语义

function testSendWithoutTransport(): void {
  const server: WiFiServerActivity = new WiFiServerActivity();
  server.onItemSelected(WiFiServerMenu.BOOKMARK);
  server.onStatusChange();   // 进入发送态（此时队列仍空）
  eq('队列空时 sendNextPage → NONE', server.sendNextPage(), WiFiServerAction.NONE);
  eq('队列空 → 发送态结束（上游 sending=false）', server.isSending(), false);

  // 有帧但无连接：上游 sending=false 并提示 connect_unable
  server.onItemSelected(WiFiServerMenu.BOOKMARK);
  server.onStatusChange();
  const frames: number = server.buildBookmarkFrames([]);
  eq('空列表 → 0 页 → 0 帧', frames, 0);
  eq('build 后队列仍 0', server.queueSize(), 0);

  // onSendSuccess：**发送中 + 队列空 → true**（上游要提示 wifi_send_done）
  eq('发送中 + 队列空 → onSendSuccess 需要提示完成', server.onSendSuccess(), true);
  eq('提示完成后发送态结束', server.isSending(), false);

  // 未在发送 → false（不提示完成）
  const idle: WiFiServerActivity = new WiFiServerActivity();
  eq('未发送时 onSendSuccess → false', idle.onSendSuccess(), false);
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testTotalPage();
  testDirKey();
  testPlanStatusChange();
  testStatusButtonState();
  testPickWlanIpv4();
  testPermissionAndState();
  testSendWithoutTransport();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync wifi test failed');
  }
  console.log(`✓ download-sync WiFi 批: ${pass} 条断言全部通过`);
}

main();
