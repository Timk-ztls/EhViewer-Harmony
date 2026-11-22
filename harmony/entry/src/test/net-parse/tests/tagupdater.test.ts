// Tests for EhTagDatabaseUpdater & case-insensitive EhTagDatabase.suggest

import fs from '@ohos.file.fs';
import { EhTagDatabase, TagDatabaseIo, TagSuggestion } from '../EhTagDatabase';
import { EhTagDatabaseUpdater, EhTagUpdaterConfig } from '../EhTagDatabaseUpdater';

declare const process: { env: Record<string, string | undefined>; pid: number };

let pass: number = 0;
let fail: number = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a: string = JSON.stringify(actual);
  const e: string = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function b64(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i += 3) {
    const c1 = s.charCodeAt(i);
    const c2 = i + 1 < s.length ? s.charCodeAt(i + 1) : NaN;
    const c3 = i + 2 < s.length ? s.charCodeAt(i + 2) : NaN;
    const n = (c1 << 16) | ((isNaN(c2) ? 0 : c2) << 8) | (isNaN(c3) ? 0 : c3);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63];
    out += isNaN(c2) ? '=' : B64[(n >> 6) & 63];
    out += isNaN(c3) ? '=' : B64[n & 63];
  }
  return out;
}

function utf8Bytes(s: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}

function buildTagDb(lines: string[]): ArrayBuffer {
  const text: string = lines.join('\n');
  const body: Uint8Array = utf8Bytes(text);
  const out: Uint8Array = new Uint8Array(4 + body.length);
  const len: number = body.length;
  out[0] = (len >>> 24) & 0xff;
  out[1] = (len >>> 16) & 0xff;
  out[2] = (len >>> 8) & 0xff;
  out[3] = len & 0xff;
  out.set(body, 4);
  return out.buffer as ArrayBuffer;
}

function hexToBytes(hex: string): ArrayBuffer {
  const out: Uint8Array = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return out.buffer as ArrayBuffer;
}

class LocalTestIo implements TagDatabaseIo {
  private readonly dir: string;
  constructor(dir: string) {
    this.dir = dir;
  }
  getMetadata(): string[] {
    return [
      EhTagDatabaseUpdater.SHA1_NAME,
      EhTagDatabaseUpdater.SOURCES[0].sha1Url,
      EhTagDatabaseUpdater.DATA_NAME,
      EhTagDatabaseUpdater.SOURCES[0].dataUrl
    ];
  }
  readData(dataName: string): ArrayBuffer | null {
    const path: string = `${this.dir}/${dataName}`;
    if (!fs.accessSync(path)) {
      return null;
    }
    const st: fs.Stat = fs.statSync(path);
    const buf: ArrayBuffer = new ArrayBuffer(st.size);
    const f: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      fs.readSync(f.fd, buf);
      return buf;
    } finally {
      fs.closeSync(f);
    }
  }
}

async function runTests(): Promise<void> {
  // 0. Default primary source points to upstream xiaojieonly/EhTagTranslation
  ok('SOURCES[0] uses upstream xiaojieonly/EhTagTranslation',
    EhTagDatabaseUpdater.SOURCES[0].dataUrl.indexOf('xiaojieonly/EhTagTranslation') >= 0 &&
    EhTagDatabaseUpdater.SOURCES[0].dataUrl.endsWith('tag-translations-zh-rCN.json'));

  // 1. Standard SHA-1 FIPS 180-4 test vectors + parseSha1Hex (20-byte & 40-char hex)
  eq('sha1("")', EhTagDatabaseUpdater.sha1HexOfBytes(new Uint8Array(0)), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
  eq('sha1("abc")', EhTagDatabaseUpdater.sha1HexOfBytes(utf8Bytes('abc')), 'a9993e364706816aba3e25717850c26c9cd0d89d');

  const sampleHex = 'A9993E364706816ABA3E25717850C26C9CD0D89D';
  eq('parseSha1Hex(40-char hex)', EhTagDatabaseUpdater.parseSha1Hex(utf8Bytes(sampleHex + '\n').buffer as ArrayBuffer), sampleHex.toLowerCase());
  eq('parseSha1Hex(20-byte raw)', EhTagDatabaseUpdater.parseSha1Hex(hexToBytes(sampleHex)), sampleHex.toLowerCase());
  eq('parseSha1Hex(invalid)', EhTagDatabaseUpdater.parseSha1Hex(utf8Bytes('not-a-sha1').buffer as ArrayBuffer), null);

  // 2. End-to-end updater flow: primary failure -> jsDelivr mirror fallback -> persist -> translate & suggest
  const tmpDir: string = (process.env.TEMP || process.env.TMP || '/tmp') + '/eh-tag-upd-' + process.pid;
  try {
    fs.rmdirSync(tmpDir);
  } catch (_e) {
    // ignore cleanup miss
  }
  fs.mkdirSync(tmpDir, true);

  const payload: ArrayBuffer = buildTagDb([
    `f:swimsuit\r${b64('swimsuit-cn')}`,
    `p:touhou project\r${b64('touhou-cn')}`
  ]);
  const expectedSha1: string = EhTagDatabaseUpdater.sha1HexOfBytes(new Uint8Array(payload));
  const requestedUrls: string[] = [];
  let listenerCalls: number = 0;
  let enabled: boolean = true;

  EhTagDatabase.clearInstance();
  EhTagDatabaseUpdater.addUpdateListener((): void => {
    listenerCalls++;
  });
  EhTagDatabaseUpdater.configure(new EhTagUpdaterConfig(
    new LocalTestIo(tmpDir),
    (): string => tmpDir,
    (): boolean => enabled,
    async (url: string): Promise<ArrayBuffer | null> => {
      requestedUrls.push(url);
      // Fail primary GitHub URLs to verify jsDelivr mirror fallback.
      if (url.indexOf('raw.githubusercontent.com') >= 0) {
        return null;
      }
      if (url.endsWith('.sha1')) {
        return utf8Bytes(expectedSha1 + '\n').buffer as ArrayBuffer;
      }
      return payload;
    }
  ));

  const updated: boolean = await EhTagDatabaseUpdater.update(false);
  ok('update succeeded via mirror fallback', updated);
  ok('listener fired on update', listenerCalls >= 1);
  ok('primary + mirror URLs tried', requestedUrls.some((u: string): boolean => u.indexOf('cdn.jsdelivr.net') >= 0));
  eq('translateKey tag hit', EhTagDatabaseUpdater.translateKey('f:swimsuit'), 'swimsuit-cn');
  eq('translateKey namespace n: fallback', EhTagDatabaseUpdater.translateKey('n:female'), '女性');

  // Case-insensitive English suggest
  const hints: TagSuggestion[] = EhTagDatabaseUpdater.suggest('SWIM');
  eq('suggest case-insensitive count', hints.length, 1);
  eq('suggest english', hints[0].english, 'female:swimsuit');
  eq('suggest chinese', hints[0].chinese, 'swimsuit-cn');

  // Toggle disabled stops translateKey while keeping suggest active (upstream SearchBar behavior)
  enabled = false;
  eq('translateKey returns null when disabled', EhTagDatabaseUpdater.translateKey('f:swimsuit'), null);
  eq('suggest stays available when translation disabled', EhTagDatabaseUpdater.suggest('swim').length, 1);

  // Clean up temp test dir
  try {
    fs.rmdirSync(tmpDir);
  } catch (_e) {
    // ignore cleanup miss
  }

  console.log(`\n=== tagupdater results: ${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('tagupdater assertions failed: ' + fail);
  }
}

void runTests();
