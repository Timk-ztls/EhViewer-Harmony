/*
 * EhClient.signIn 单测（账号密码登录）
 *
 * 上游对位（EhEngine.java:170-205 + SignInParser.java）：
 *   POST https://forums.e-hentai.org/index.php?act=Login&CODE=01
 *   body: UserName/PassWord/submit=Log me in/CookieDate=1/temporary_https=off
 *   成功判据：HTML 里 `<p>You are now logged in as: (.+?)<`（**不是**看 cookie）
 *   失败判据：`<h4>The error returned was:</h4> <p>…</p>` 或 `<span class="postcolor">…</span>`
 *
 * 本文件钉的是 **EhClient 这一层的调度与错误分类**（URL/body 由 EhEngine 单测覆盖）：
 *   ① 成功 → success=true、displayName=解析出的名字、avatar 从 profile 取
 *   ② 头像取不到 **不影响登录成功**
 *   ③ 至少两种 errorCode：账号密码错 (-4) / HTTP 状态码 (>0) / 解析失败 (-3) / 其它 (-2)
 */

import { EhClient, MethodDispatcher, TaskInterface } from '../../../ehviewer/client/EhClient';
import { EhSignInResult } from '../../../ehviewer/client/EhSignInResult';
import { EhException } from '../../../ehviewer/client/exception/EhException';
import { ParseException } from '../../../ehviewer/client/exception/ParseException';
import { StatusCodeException } from '../../../network/StatusCodeException';

declare const process: { exitCode: number };

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}

/** 可编排的假 dispatcher：记录 method/args，按 method 返回或抛错。 */
class FakeDispatcher implements MethodDispatcher {
  calls: string[] = [];
  signInResult: Object = '';
  signInError: Error | null = null;
  profileAvatar: string | null = 'https://example/avatar.png';
  profileError: Error | null = null;

  async invoke(task: TaskInterface, method: number, args: Object[]): Promise<Object> {
    this.calls.push(`${method}:${args.length}`);
    if (method === EhClient.METHOD_SIGN_IN) {
      if (this.signInError !== null) {
        throw this.signInError;
      }
      return this.signInResult;
    }
    if (method === EhClient.METHOD_GET_PROFILE) {
      if (this.profileError !== null) {
        throw this.profileError;
      }
      return { displayName: 'x', avatar: this.profileAvatar } as Object;
    }
    throw new Error('unexpected method ' + method);
  }
}

async function main(): Promise<void> {
  // ---------------------------------------------------------------- ① 成功
  {
    const d = new FakeDispatcher();
    d.signInResult = 'CoolUser' as Object;
    const client = new EhClient(d);
    const r: EhSignInResult = await client.signIn('u', 'p');
    eq('成功 → success', r.success, true);
    eq('成功 → errorCode 0', r.errorCode, EhSignInResult.OK);
    eq('成功 → displayName 来自 signIn 返回值', r.displayName, 'CoolUser');
    eq('成功 → avatar 来自 profile', r.avatar, 'https://example/avatar.png');
    eq('成功 → 先 SIGN_IN 再 GET_PROFILE', d.calls,
      [`${EhClient.METHOD_SIGN_IN}:2`, `${EhClient.METHOD_GET_PROFILE}:0`]);
  }

  // ---------------------------------------------------------------- ② 头像取不到不影响成功
  {
    const d = new FakeDispatcher();
    d.signInResult = 'NoAvatar' as Object;
    d.profileError = new Error('profile boom');
    const r = await new EhClient(d).signIn('u', 'p');
    eq('profile 抛错 → 仍然 success', r.success, true);
    eq('profile 抛错 → avatar 为空串（不是 null）', r.avatar, '');
    eq('displayName 不受影响', r.displayName, 'NoAvatar');
  }

  // ---------------------------------------------------------------- ③ 账号密码错误 → -4
  {
    const d = new FakeDispatcher();
    d.signInError = new EhException('The entered email address or password is incorrect');
    const r = await new EhClient(d).signIn('u', 'wrong');
    eq('凭据错误 → success=false', r.success, false);
    eq('凭据错误 → errorCode = ERR_CREDENTIAL(-4)', r.errorCode, EhSignInResult.ERR_CREDENTIAL);
    ok('凭据错误 → errorMessage 保留上游文案',
      r.errorMessage.indexOf('incorrect') >= 0);
    eq('凭据错误 → 不再去取 profile', d.calls.length, 1);
  }

  // ---------------------------------------------------------------- ③ HTTP 状态码原值透传
  {
    const d = new FakeDispatcher();
    d.signInError = new StatusCodeException(509, '509');
    const r = await new EhClient(d).signIn('u', 'p');
    eq('509 → errorCode 原值透传', r.errorCode, 509);
    eq('509 → success=false', r.success, false);

    const d2 = new FakeDispatcher();
    d2.signInError = new StatusCodeException(503, '503');
    const r2 = await new EhClient(d2).signIn('u', 'p');
    eq('503 → 原值透传（不重编号）', r2.errorCode, 503);
  }

  // ---------------------------------------------------------------- ③ 解析失败 → -3（且优先于 -4）
  {
    const d = new FakeDispatcher();
    d.signInError = new ParseException("Can't parse sign in", '<html></html>');
    const r = await new EhClient(d).signIn('u', 'p');
    eq('ParseException → ERR_PARSE(-3)', r.errorCode, EhSignInResult.ERR_PARSE);
    ok('ParseException 不能被误判成凭据错误（子类顺序）',
      r.errorCode !== EhSignInResult.ERR_CREDENTIAL);
  }

  // ---------------------------------------------------------------- ④ mapSignInError 辅助与 EhEngine 转换语义
  {
    const directParse = EhClient.mapSignInError(new ParseException("Can't parse sign in", '<html></html>'));
    eq('mapSignInError 直接收到 ParseException → ERR_PARSE(-3)',
      directParse.errorCode, EhSignInResult.ERR_PARSE);
    const wrappedEh = EhClient.mapSignInError(new EhException('Parse error'));
    eq('mapSignInError 收到 EhEngine.doThrowException 转出的 EhException → ERR_CREDENTIAL(-4)',
      wrappedEh.errorCode, EhSignInResult.ERR_CREDENTIAL);
  }

  // ---------------------------------------------------------------- ③ 其它异常 → -2
  {
    const d = new FakeDispatcher();
    d.signInError = new Error('socket timeout');
    const r = await new EhClient(d).signIn('u', 'p');
    eq('普通 Error → ERR_OTHER(-2)', r.errorCode, EhSignInResult.ERR_OTHER);
    ok('普通 Error → errorMessage 带原始信息', r.errorMessage.indexOf('timeout') >= 0);
  }

  // ---------------------------------------------------------------- 结果类的工厂与常量
  {
    const okR = EhSignInResult.ok('n', 'a');
    eq('ok() → success/errorCode', [okR.success, okR.errorCode], [true, 0]);
    eq('ok() → errorMessage 为空串（不是 null）', okR.errorMessage, '');
    const badR = EhSignInResult.fail(-4, 'msg');
    eq('fail() → displayName/avatar 都是空串', [badR.displayName, badR.avatar], ['', '']);
    eq('码表常量稳定', [EhSignInResult.OK, EhSignInResult.ERR_UNAVAILABLE,
      EhSignInResult.ERR_OTHER, EhSignInResult.ERR_PARSE, EhSignInResult.ERR_CREDENTIAL],
      [0, -1, -2, -3, -4]);
  }
}

main().then((): void => {
  printResult();
}).catch((e: Error): void => {
  console.log('harness error: ' + e.message);
  process.exitCode = 1;
});

function printResult(): void {
  console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
  if (fails.length > 0) {
    for (const f of fails) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhClient.signIn 断言失败：' + fails.length);
  }
}
