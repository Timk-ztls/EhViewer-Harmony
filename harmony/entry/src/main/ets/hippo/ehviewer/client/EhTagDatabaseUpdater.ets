import fs from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EhTagDatabase, TagDatabaseIo, TagSuggestion } from './EhTagDatabase';

const DOMAIN: number = 0x0000;
const TAG: string = 'EhTagDatabaseUpdater';

export type TagBytesFetcher = (url: string) => Promise<ArrayBuffer | null>;
export type TagDbUpdateListener = () => void;

export class EhTagSourcePair {
  readonly sha1Name: string;
  readonly sha1Url: string;
  readonly dataName: string;
  readonly dataUrl: string;

  constructor(sha1Name: string, sha1Url: string, dataName: string, dataUrl: string) {
    this.sha1Name = sha1Name;
    this.sha1Url = sha1Url;
    this.dataName = dataName;
    this.dataUrl = dataUrl;
  }
}

export class EhTagUpdaterConfig {
  readonly io: TagDatabaseIo;
  readonly getDir: () => string | null;
  readonly isEnabled: () => boolean;
  readonly fetchBytes: TagBytesFetcher;

  constructor(
    io: TagDatabaseIo,
    getDir: () => string | null,
    isEnabled: () => boolean,
    fetchBytes: TagBytesFetcher
  ) {
    this.io = io;
    this.getDir = getDir;
    this.isEnabled = isEnabled;
    this.fetchBytes = fetchBytes;
  }
}

class Sha1FetchHit {
  readonly hex: string;
  readonly raw: ArrayBuffer;
  readonly sourceIndex: number;

  constructor(hex: string, raw: ArrayBuffer, sourceIndex: number) {
    this.hex = hex;
    this.raw = raw;
    this.sourceIndex = sourceIndex;
  }
}

const NAMESPACE_ZH_FALLBACK: Map<string, string> = new Map<string, string>([
  ['rows', '行数'],
  ['artist', '画师'],
  ['cosplayer', 'Coser'],
  ['character', '角色'],
  ['female', '女性'],
  ['group', '社团'],
  ['language', '语言'],
  ['location', '地点'],
  ['male', '男性'],
  ['misc', '其他'],
  ['mixed', '混合'],
  ['other', '其他'],
  ['parody', '原作'],
  ['reclass', '重新分类']
]);

/**
 * Manages asynchronous download, SHA-1 verification, atomic persistence,
 * and lifecycle notifications for `EhTagDatabase` (aligned with upstream `EhTagDatabase.java:update()`).
 */
export class EhTagDatabaseUpdater {
  static readonly SHA1_NAME: string = 'tag-translations-zh-rCN.sha1';
  static readonly DATA_NAME: string = 'tag-translations-zh-rCN';

  static readonly SOURCES: EhTagSourcePair[] = [
    new EhTagSourcePair(
      'tag-translations-zh-rCN.sha1',
      'https://raw.githubusercontent.com/xiaojieonly/EhTagTranslation/main/tag-translations/tag-translations-zh-rCN.json.sha1',
      'tag-translations-zh-rCN',
      'https://raw.githubusercontent.com/xiaojieonly/EhTagTranslation/main/tag-translations/tag-translations-zh-rCN.json'
    ),
    new EhTagSourcePair(
      'tag-translations-zh-rCN.sha1',
      'https://cdn.jsdelivr.net/gh/xiaojieonly/EhTagTranslation@main/tag-translations/tag-translations-zh-rCN.json.sha1',
      'tag-translations-zh-rCN',
      'https://cdn.jsdelivr.net/gh/xiaojieonly/EhTagTranslation@main/tag-translations/tag-translations-zh-rCN.json'
    ),
    new EhTagSourcePair(
      'tag-translations-zh-rCN.sha1',
      'https://raw.githubusercontent.com/Mapaler/EhViewer/tag-translations/tag-translations/tag-translations-zh-rCN.sha1',
      'tag-translations-zh-rCN',
      'https://raw.githubusercontent.com/Mapaler/EhViewer/tag-translations/tag-translations/tag-translations-zh-rCN'
    ),
    new EhTagSourcePair(
      'tag-translations-zh-rCN.sha1',
      'https://cdn.jsdelivr.net/gh/Mapaler/EhViewer@tag-translations/tag-translations/tag-translations-zh-rCN.sha1',
      'tag-translations-zh-rCN',
      'https://cdn.jsdelivr.net/gh/Mapaler/EhViewer@tag-translations/tag-translations/tag-translations-zh-rCN'
    )
  ];

  private static config: EhTagUpdaterConfig | null = null;
  private static updating: boolean = false;
  private static readonly listeners: Set<TagDbUpdateListener> = new Set<TagDbUpdateListener>();

  static configure(config: EhTagUpdaterConfig): void {
    EhTagDatabaseUpdater.config = config;
  }

  static isConfigured(): boolean {
    return EhTagDatabaseUpdater.config !== null;
  }

  static isUpdating(): boolean {
    return EhTagDatabaseUpdater.updating;
  }

  static addUpdateListener(listener: TagDbUpdateListener): void {
    EhTagDatabaseUpdater.listeners.add(listener);
  }

  static removeUpdateListener(listener: TagDbUpdateListener): void {
    EhTagDatabaseUpdater.listeners.delete(listener);
  }

  private static notifyListeners(): void {
    EhTagDatabaseUpdater.listeners.forEach((listener: TagDbUpdateListener): void => {
      try {
        listener();
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'listener failed: %{public}s', msg);
      }
    });
  }

  static isTranslationEnabled(): boolean {
    const cfg: EhTagUpdaterConfig | null = EhTagDatabaseUpdater.config;
    if (cfg === null) {
      return false;
    }
    return cfg.isEnabled();
  }

  static getDatabase(): EhTagDatabase | null {
    const cfg: EhTagUpdaterConfig | null = EhTagDatabaseUpdater.config;
    if (cfg === null) {
      return null;
    }
    return EhTagDatabase.getInstance(cfg.io);
  }

  static isDatabaseReady(): boolean {
    return EhTagDatabaseUpdater.getDatabase() !== null;
  }

  static translateKey(key: string): string | null {
    const cfg: EhTagUpdaterConfig | null = EhTagDatabaseUpdater.config;
    if (cfg === null || !cfg.isEnabled()) {
      return null;
    }
    const db: EhTagDatabase | null = EhTagDatabase.getInstance(cfg.io);
    if (db !== null) {
      const hit: string | null = db.getTranslation(key);
      if (hit !== null && hit.length > 0 && hit !== 'null') {
        return hit;
      }
    }
    if (key.startsWith('n:')) {
      const ns: string = key.substring(2);
      const fallback: string | undefined = NAMESPACE_ZH_FALLBACK.get(ns);
      if (fallback !== undefined) {
        return fallback;
      }
    }
    return null;
  }

  static suggest(keyword: string): TagSuggestion[] {
    const trimmed: string = keyword.trim();
    if (trimmed.length === 0) {
      return [];
    }
    const db: EhTagDatabase | null = EhTagDatabaseUpdater.getDatabase();
    if (db === null) {
      return [];
    }
    return db.suggest(trimmed);
  }

  static async update(_force: boolean = false): Promise<boolean> {
    const cfg: EhTagUpdaterConfig | null = EhTagDatabaseUpdater.config;
    if (cfg === null) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'update skipped: updater not configured');
      return false;
    }
    if (EhTagDatabaseUpdater.updating) {
      return false;
    }
    const dir: string | null = cfg.getDir();
    if (dir === null || dir.length === 0) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'update skipped: tag-translations dir unavailable');
      return false;
    }

    EhTagDatabaseUpdater.updating = true;
    try {
      const metadata: string[] | null = cfg.io.getMetadata();
      const sha1Name: string = (metadata !== null && metadata.length === 4)
        ? metadata[0] : EhTagDatabaseUpdater.SHA1_NAME;
      const dataName: string = (metadata !== null && metadata.length === 4)
        ? metadata[2] : EhTagDatabaseUpdater.DATA_NAME;
      const sha1Path: string = `${dir}/${sha1Name}`;
      const dataPath: string = `${dir}/${dataName}`;

      // Verify existing local database before remote check; discard corrupted local files.
      let localDataValid: boolean = false;
      const localSha1Bytes: ArrayBuffer | null = EhTagDatabaseUpdater.readFileBytes(sha1Path);
      const localDataBytes: ArrayBuffer | null = EhTagDatabaseUpdater.readFileBytes(dataPath);
      const localExpectedSha1: string | null = localSha1Bytes !== null
        ? EhTagDatabaseUpdater.parseSha1Hex(localSha1Bytes)
        : null;
      if (localExpectedSha1 !== null && localDataBytes !== null) {
        const actualSha1: string = EhTagDatabaseUpdater.sha1HexOfBytes(new Uint8Array(localDataBytes));
        if (actualSha1 === localExpectedSha1 && EhTagDatabaseUpdater.canParseDatabase(dataName, localDataBytes)) {
          localDataValid = true;
          if (EhTagDatabase.getInstance(cfg.io) !== null) {
            EhTagDatabaseUpdater.notifyListeners();
          }
        } else {
          hilog.warn(DOMAIN, TAG, 'local tag database checksum/parse invalid, clearing');
          EhTagDatabaseUpdater.unlinkQuietly(sha1Path);
          EhTagDatabaseUpdater.unlinkQuietly(dataPath);
        }
      }

      // Fetch remote SHA-1 (primary GitHub Raw -> jsDelivr mirror).
      const remoteSha1: Sha1FetchHit | null = await EhTagDatabaseUpdater.fetchRemoteSha1(
        cfg.fetchBytes, metadata);
      if (remoteSha1 === null) {
        hilog.warn(DOMAIN, TAG, 'failed to fetch remote tag-translations sha1');
        return false;
      }

      if (localDataValid && localDataBytes !== null) {
        const localDigest: string = EhTagDatabaseUpdater.sha1HexOfBytes(new Uint8Array(localDataBytes));
        if (localDigest === remoteSha1.hex) {
          hilog.info(DOMAIN, TAG, 'tag-translations already up to date (sha1=%{public}s)', remoteSha1.hex);
          return true;
        }
      }

      // Fetch new data payload (prefer mirror that served SHA-1, then fallback).
      const remoteData: ArrayBuffer | null = await EhTagDatabaseUpdater.fetchRemoteData(
        cfg.fetchBytes, metadata, remoteSha1.sourceIndex);
      if (remoteData === null || remoteData.byteLength < 4) {
        hilog.warn(DOMAIN, TAG, 'failed to fetch remote tag-translations payload');
        return false;
      }

      const downloadedSha1: string = EhTagDatabaseUpdater.sha1HexOfBytes(new Uint8Array(remoteData));
      if (downloadedSha1 !== remoteSha1.hex) {
        hilog.warn(DOMAIN, TAG, 'tag-translations sha1 mismatch: got %{public}s expected %{public}s',
          downloadedSha1, remoteSha1.hex);
        return false;
      }

      if (!EhTagDatabaseUpdater.canParseDatabase(dataName, remoteData)) {
        hilog.warn(DOMAIN, TAG, 'downloaded tag-translations payload failed parser check');
        return false;
      }

      // Atomic persist to .tmp then rename.
      const wroteData: boolean = EhTagDatabaseUpdater.writeAtomic(dataPath, remoteData);
      const wroteSha1: boolean = EhTagDatabaseUpdater.writeAtomic(sha1Path, remoteSha1.raw);
      if (!wroteData || !wroteSha1) {
        hilog.warn(DOMAIN, TAG, 'failed to persist tag-translations to %{public}s', dir);
        return false;
      }

      EhTagDatabase.clearInstance();
      const loaded: EhTagDatabase | null = EhTagDatabase.getInstance(cfg.io);
      if (loaded === null) {
        hilog.warn(DOMAIN, TAG, 'reloaded tag database is null after write');
        return false;
      }
      hilog.info(DOMAIN, TAG, 'tag-translations updated successfully: %{public}d tags (sha1=%{public}s)',
        loaded.getTagList().length, remoteSha1.hex);
      EhTagDatabaseUpdater.notifyListeners();
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'update failed: %{public}s', msg);
      return false;
    } finally {
      EhTagDatabaseUpdater.updating = false;
    }
  }

  private static async fetchRemoteSha1(
    fetchBytes: TagBytesFetcher,
    metadata: string[] | null
  ): Promise<Sha1FetchHit | null> {
    const urls: string[] = [];
    if (metadata !== null && metadata.length === 4 && metadata[1].length > 0) {
      urls.push(metadata[1]);
    }
    for (let i = 0; i < EhTagDatabaseUpdater.SOURCES.length; i++) {
      const u: string = EhTagDatabaseUpdater.SOURCES[i].sha1Url;
      if (urls.indexOf(u) < 0) {
        urls.push(u);
      }
    }
    for (let i = 0; i < urls.length; i++) {
      try {
        const buf: ArrayBuffer | null = await fetchBytes(urls[i]);
        if (buf !== null) {
          const hex: string | null = EhTagDatabaseUpdater.parseSha1Hex(buf);
          if (hex !== null) {
            return new Sha1FetchHit(hex, buf, i);
          }
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'sha1 fetch error from %{public}s: %{public}s', urls[i], msg);
      }
    }
    return null;
  }

  private static async fetchRemoteData(
    fetchBytes: TagBytesFetcher,
    metadata: string[] | null,
    preferredIndex: number
  ): Promise<ArrayBuffer | null> {
    const urls: string[] = [];
    if (metadata !== null && metadata.length === 4 && metadata[3].length > 0) {
      urls.push(metadata[3]);
    }
    for (let i = 0; i < EhTagDatabaseUpdater.SOURCES.length; i++) {
      const u: string = EhTagDatabaseUpdater.SOURCES[i].dataUrl;
      if (urls.indexOf(u) < 0) {
        urls.push(u);
      }
    }
    // Try the matching mirror index first, then fallback URLs in order.
    const ordered: string[] = [];
    if (preferredIndex >= 0 && preferredIndex < urls.length) {
      ordered.push(urls[preferredIndex]);
    }
    for (let i = 0; i < urls.length; i++) {
      if (ordered.indexOf(urls[i]) < 0) {
        ordered.push(urls[i]);
      }
    }
    for (let i = 0; i < ordered.length; i++) {
      try {
        const buf: ArrayBuffer | null = await fetchBytes(ordered[i]);
        if (buf !== null && buf.byteLength >= 4) {
          return buf;
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'data fetch error from %{public}s: %{public}s', ordered[i], msg);
      }
    }
    return null;
  }

  private static canParseDatabase(name: string, buf: ArrayBuffer): boolean {
    try {
      const db: EhTagDatabase = new EhTagDatabase(name, buf);
      return db.getTagList().length > 0;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'tag database parse check failed: %{public}s', msg);
      return false;
    }
  }

  private static readFileBytes(path: string): ArrayBuffer | null {
    let file: fs.File | null = null;
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      const stat: fs.Stat = fs.statSync(path);
      if (stat.size <= 0) {
        return null;
      }
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const read: number = fs.readSync(file.fd, buf);
      if (read !== stat.size) {
        return buf.slice(0, Math.max(0, read));
      }
      return buf;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'readFileBytes failed for %{public}s: %{public}s', path, msg);
      return null;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
          hilog.warn(DOMAIN, TAG, 'closeSync failed: %{public}s', msg);
        }
      }
    }
  }

  private static writeAtomic(targetPath: string, data: ArrayBuffer): boolean {
    const tmpPath: string = `${targetPath}.tmp`;
    let file: fs.File | null = null;
    try {
      EhTagDatabaseUpdater.unlinkQuietly(tmpPath);
      file = fs.openSync(tmpPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const bytes: Uint8Array = new Uint8Array(data);
      let written: number = 0;
      while (written < bytes.length) {
        const chunk: ArrayBuffer = written === 0 ? data : data.slice(written);
        const n: number = fs.writeSync(file.fd, chunk);
        if (n <= 0) {
          throw new Error('short write');
        }
        written += n;
      }
      fs.closeSync(file);
      file = null;
      EhTagDatabaseUpdater.unlinkQuietly(targetPath);
      fs.renameSync(tmpPath, targetPath);
      return true;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'writeAtomic failed for %{public}s: %{public}s', targetPath, msg);
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          const cm: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
          hilog.warn(DOMAIN, TAG, 'closeSync cleanup failed: %{public}s', cm);
        }
      }
      EhTagDatabaseUpdater.unlinkQuietly(tmpPath);
      return false;
    }
  }

  private static unlinkQuietly(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'unlinkQuietly failed for %{public}s: %{public}s', path, msg);
    }
  }

  /**
   * Parses either a 20-byte raw SHA-1 digest or an ASCII 40-char hex string.
   */
  static parseSha1Hex(buf: ArrayBuffer): string | null {
    const bytes: Uint8Array = new Uint8Array(buf);
    if (bytes.length === 20) {
      let hex: string = '';
      for (let i = 0; i < 20; i++) {
        hex += EhTagDatabaseUpdater.toHexByte(bytes[i]);
      }
      return hex;
    }
    let text: string = '';
    const limit: number = Math.min(bytes.length, 256);
    for (let i = 0; i < limit; i++) {
      text += String.fromCharCode(bytes[i]);
    }
    const token: string = text.trim().split(/\s+/)[0];
    if (/^[0-9a-fA-F]{40}$/.test(token)) {
      return token.toLowerCase();
    }
    return null;
  }

  /**
   * Computes lowercase 40-char hex SHA-1 digest in pure TypeScript (FIPS 180-4).
   */
  static sha1HexOfBytes(data: Uint8Array): string {
    const bitLenHi: number = Math.floor(data.length / 0x20000000);
    const bitLenLo: number = (data.length << 3) >>> 0;
    const padLen: number = ((56 - ((data.length + 1) % 64)) + 64) % 64;
    const totalLen: number = data.length + 1 + padLen + 8;
    const padded: Uint8Array = new Uint8Array(totalLen);
    padded.set(data, 0);
    padded[data.length] = 0x80;
    padded[totalLen - 8] = (bitLenHi >>> 24) & 0xff;
    padded[totalLen - 7] = (bitLenHi >>> 16) & 0xff;
    padded[totalLen - 6] = (bitLenHi >>> 8) & 0xff;
    padded[totalLen - 5] = bitLenHi & 0xff;
    padded[totalLen - 4] = (bitLenLo >>> 24) & 0xff;
    padded[totalLen - 3] = (bitLenLo >>> 16) & 0xff;
    padded[totalLen - 2] = (bitLenLo >>> 8) & 0xff;
    padded[totalLen - 1] = bitLenLo & 0xff;

    let h0: number = 0x67452301;
    let h1: number = 0xefcdab89;
    let h2: number = 0x98badcfe;
    let h3: number = 0x10325476;
    let h4: number = 0xc3d2e1f0;
    const w: Int32Array = new Int32Array(80);

    for (let offset = 0; offset < totalLen; offset += 64) {
      for (let i = 0; i < 16; i++) {
        const j: number = offset + i * 4;
        w[i] = ((padded[j] << 24) | (padded[j + 1] << 16) | (padded[j + 2] << 8) | padded[j + 3]) | 0;
      }
      for (let i = 16; i < 80; i++) {
        const x: number = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
        w[i] = (x << 1) | (x >>> 31);
      }

      let a: number = h0;
      let b: number = h1;
      let c: number = h2;
      let d: number = h3;
      let e: number = h4;

      for (let i = 0; i < 80; i++) {
        let f: number = 0;
        let k: number = 0;
        if (i < 20) {
          f = (b & c) | ((~b) & d);
          k = 0x5a827999;
        } else if (i < 40) {
          f = b ^ c ^ d;
          k = 0x6ed9eba1;
        } else if (i < 60) {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8f1bbcdc | 0;
        } else {
          f = b ^ c ^ d;
          k = 0xca62c1d6 | 0;
        }
        const temp: number = (((a << 5) | (a >>> 27)) + f + e + k + w[i]) | 0;
        e = d;
        d = c;
        c = (b << 30) | (b >>> 2);
        b = a;
        a = temp;
      }

      h0 = (h0 + a) | 0;
      h1 = (h1 + b) | 0;
      h2 = (h2 + c) | 0;
      h3 = (h3 + d) | 0;
      h4 = (h4 + e) | 0;
    }

    return EhTagDatabaseUpdater.toHexWord(h0) +
      EhTagDatabaseUpdater.toHexWord(h1) +
      EhTagDatabaseUpdater.toHexWord(h2) +
      EhTagDatabaseUpdater.toHexWord(h3) +
      EhTagDatabaseUpdater.toHexWord(h4);
  }

  private static toHexByte(b: number): string {
    const v: number = b & 0xff;
    return (v < 16 ? '0' : '') + v.toString(16);
  }

  private static toHexWord(w: number): string {
    const u: number = w >>> 0;
    let s: string = u.toString(16);
    while (s.length < 8) {
      s = '0' + s;
    }
    return s;
  }
}
