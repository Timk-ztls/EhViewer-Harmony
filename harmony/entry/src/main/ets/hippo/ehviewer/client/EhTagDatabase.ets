/*
 * Copyright 2016 Hippo Seven
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhTagDatabase.java
 * （inventory S0078，460 行）
 *
 * 标签翻译库。二进制格式（**字节级照搬**）：
 *   [4 字节大端 int] = totalBytes
 *   [totalBytes 字节] = UTF-8 文本，行之间用 '\n' 分隔
 *   每行：`english\rBase64(chinese)`；english 里的 `x:` 前缀按 PREFIX_TO_NAMESPACE 还原成 namespace
 *
 * 两个查询通道：
 *   1. `getTranslation(tag)` —— 在**原始字节数组**上做二分查找（靠 '\n' 找行首、'\r' 找中缝），
 *      这是上游为省内存刻意做的，不是普通字符串搜索
 *   2. `suggest(keyword)` —— 在解析好的 tagList 上线性扫描，**最多 40 条**，
 *      命中条件是 `english.contains || chinese.contains`
 *
 * 二分查找的边界必须逐字节照搬（byte 与原子上游都是 signed→`& 0xff`）。
 *
 * update()/getInstance() 依赖 Android 的文件与资源系统 → 抽成 `TagUpdateIo` / `TagMetadataSource`，
 * 目录与下载逻辑保留在 `update()` 里，IO 由调用方注入。
 */
export class EhTagDatabase {
  /** namespace → 短前缀（含冒号；misc 是空串）。逐条照搬。 */
  static readonly NAMESPACE_TO_PREFIX: Map<string, string> = new Map<string, string>([
    ['rows', 'n:'], ['artist', 'a:'], ['cosplayer', 'cos:'], ['character', 'c:'],
    ['female', 'f:'], ['group', 'g:'], ['language', 'l:'], ['location', 'loc:'],
    ['male', 'm:'], ['misc', ''], ['mixed', 'x:'], ['other', 'o:'],
    ['parody', 'p:'], ['reclass', 'r:']
  ]);

  /** 短前缀 → namespace。逐条照搬（注意 `""` → misc）。 */
  static readonly PREFIX_TO_NAMESPACE: Map<string, string> = new Map<string, string>([
    ['n:', 'rows'], ['a:', 'artist'], ['cos:', 'cosplayer'], ['c:', 'character'],
    ['f:', 'female'], ['g:', 'group'], ['l:', 'language'], ['loc:', 'location'],
    ['m:', 'male'], ['', 'misc'], ['x:', 'mixed'], ['o:', 'other'],
    ['p:', 'parody'], ['r:', 'reclass']
  ]);

  private readonly _name: string;
  private readonly _tags: Uint8Array;
  private readonly _tagList: TagEntry[];

  /**
   * 对齐 `EhTagDatabase(String name, BufferedSource source)`。
   * 输入是完整字节（前 4 字节大端长度 + 正文），由调用方读文件得到。
   */
  constructor(name: string, data: ArrayBuffer) {
    this._name = name;
    const u8: Uint8Array = new Uint8Array(data);
    if (u8.length < 4) {
      throw new Error('tag database too short');
    }
    const totalBytes: number = ((u8[0] << 24) | (u8[1] << 16) | (u8[2] << 8) | u8[3]) >>> 0;
    if (totalBytes > u8.length - 4) {
      throw new Error('tag database length mismatch');
    }
    this._tags = u8.slice(4, 4 + totalBytes);
    this._tagList = EhTagDatabase.initTagList(EhTagDatabase.decodeUtf8(this._tags));
  }

  getName(): string {
    return this._name;
  }

  getTagList(): TagEntry[] {
    return this._tagList;
  }

  /** 对齐 `getTranslation(String tag)`：字节级二分查找，找不到返回 null。 */
  getTranslation(tag: string): string | null {
    return EhTagDatabase.search(this._tags, EhTagDatabase.encodeUtf8(tag));
  }

  /** 对齐 `suggest(String keyword)`：最多 40 条，返回 [chinese, english]。 */
  suggest(keyword: string): TagSuggestion[] {
    const list: TagSuggestion[] = [];
    let total: number = 0;
    for (let i = 0; i < this._tagList.length; i++) {
      if (total >= 40) {
        break;
      }
      const tag: TagEntry = this._tagList[i];
      if (tag.involve(keyword)) {
        const s: TagSuggestion = new TagSuggestion();
        s.chinese = tag.chinese;
        s.english = tag.english;
        list.push(s);
        total++;
      }
    }
    return list;
  }

  // ==================================================================================
  // 单例入口（审计 L-08）：上游 getInstance(Context) / isPossible(Context)
  // ==================================================================================

  /**
   * 对齐 `isPossible(Context)`：**标签库在这台设备上是否可用**（元数据存在）。
   *
   * 上游读 `R.array.tag_translation_metadata`（4 项：sha1 名 / sha1 地址 / 数据名 / 数据地址），
   * ArkTS 侧没有该资源数组，改成由调用方注入 `TagDatabaseIo`（读 AppConfig 里的同名配置）。
   *
   * **必须先有这个** —— UI 靠它决定「翻译入口显不显示」：
   * 缺了它只有两条错路（恒显示但点了没用 / 恒不显示），两种都与上游不同。
   */
  static isPossible(io: TagDatabaseIo): boolean {
    const metadata: string[] | null = io.getMetadata();
    return metadata !== null && metadata.length === 4;
  }

  /**
   * 对齐 `getInstance(Context)`：
   *   - **不可能**（没元数据）→ 清空缓存并返回 null
   *   - **可能** → 首次调用时按元数据里的 `dataName` 懒加载，之后返回缓存
   *
   * 上游的懒加载发生在 `update()` 的后台线程里；这里不引入线程，把「读字节」交给
   * `io.readData(dataName)`，由调用方决定同步/异步与缓存策略。
   */
  static getInstance(io: TagDatabaseIo): EhTagDatabase | null {
    if (!EhTagDatabase.isPossible(io)) {
      EhTagDatabase._instance = null;
      return null;
    }
    const cached: EhTagDatabase | null = EhTagDatabase._instance;
    if (cached !== null) {
      return cached;
    }
    const metadata: string[] = io.getMetadata() as string[];
    const dataName: string = metadata[2];
    const data: ArrayBuffer | null = io.readData(dataName);
    if (data === null) {
      return null;
    }
    let db: EhTagDatabase;
    try {
      db = new EhTagDatabase(dataName, data);
    } catch (e) {
      // 数据损坏：与上游一致，删掉缓存（这里只清内存态，文件由 io 侧清理）
      EhTagDatabase._instance = null;
      console.warn('[EhTagDatabase] 标签库数据损坏，已清除缓存：' + (e as Error).message);
      return null;
    }
    EhTagDatabase._instance = db;
    return db;
  }

  /** 测试/重置用：清空单例缓存（上游在元数据缺失或 dataName 变化时也会清）。 */
  static clearInstance(): void {
    EhTagDatabase._instance = null;
  }

  /** 单例缓存（对齐上游 ``private static volatile EhTagDatabase instance``）。 */
  private static _instance: EhTagDatabase | null = null;
  /** 对齐 `namespaceToPrefix`：既接受 namespace 也接受已带冒号的前缀。 */
  static namespaceToPrefix(namespace: string): string | null {
    const prefix: string | undefined = EhTagDatabase.NAMESPACE_TO_PREFIX.get(namespace);
    if (prefix !== undefined) {
      return prefix;
    }
    if (EhTagDatabase.PREFIX_TO_NAMESPACE.has(namespace + ':')) {
      return namespace;
    }
    return null;
  }

  static prefixToNamespace(prefix: string): string | null {
    const ns: string | undefined = EhTagDatabase.PREFIX_TO_NAMESPACE.get(prefix);
    return ns === undefined ? null : ns;
  }

  /**
   * 对齐 `private String search(byte[] tags, byte[] tag)` —— **逐字节照搬**：
   *   start 先回退到行首（'\n'）再 +1
   *   middle 从 start+1 扫到 '\r'
   *   end 从 middle+1 扫到 '\n'
   *   比较 english 段与目标 tag 的字节；相等则 Base64 解 start+middle+1 .. start+end
   */
  private static search(tags: Uint8Array, tag: Uint8Array): string | null {
    let low: number = 0;
    let high: number = tags.length;
    while (low < high) {
      let start: number = Math.floor((low + high) / 2);
      // 找行首 '\n'
      while (start > -1 && tags[start] !== 0x0a) {
        start--;
      }
      start++;
      // 找中缝 '\r'
      let middle: number = 1;
      while (start + middle < tags.length && tags[start + middle] !== 0x0d) {
        middle++;
      }
      // 找行尾 '\n'
      let end: number = middle + 1;
      while (start + end < tags.length && tags[start + end] !== 0x0a) {
        end++;
      }
      let compare: number = 0;
      let tagIndex: number = 0;
      let curIndex: number = start;
      for (; ; ) {
        const tagByte: number = tag[tagIndex] & 0xff;
        const curByte: number = tags[curIndex] & 0xff;
        compare = tagByte - curByte;
        if (compare !== 0) {
          break;
        }
        tagIndex++;
        curIndex++;
        if (tagIndex === tag.length && curIndex === start + middle) {
          break;
        }
        if (tagIndex === tag.length) {
          compare = -1;
          break;
        }
        if (curIndex === start + middle) {
          compare = 1;
          break;
        }
      }
      if (compare < 0) {
        high = start - 1;
      } else if (compare > 0) {
        low = start + end + 1;
      } else {
        return EhTagDatabase.decodeUtf8(
          EhTagDatabase.base64Decode(tags, start + middle + 1, end - middle - 1));
      }
    }
    return null;
  }

  /** 对齐 `initTagList(String)`。 */
  private static initTagList(sourceString: string): TagEntry[] {
    const lines: string[] = sourceString.split('\n');
    const list: TagEntry[] = [];
    for (let i = 0; i < lines.length; i++) {
      list.push(EhTagDatabase.parseTag(lines[i]));
    }
    return list;
  }

  /** 对齐 `parseTag(String source)`：`english\rbase64(chinese)`。 */
  private static parseTag(source: string): TagEntry {
    const cArray: string[] = source.split('\r');
    if (cArray.length === 2) {
      const chinese: string = EhTagDatabase.decodeUtf8(EhTagDatabase.base64DecodeString(cArray[1]));
      const eArray: string[] = cArray[0].split(':');
      let english: string;
      if (eArray.length === 2) {
        const key: string = eArray[0] + ':';
        const ns: string | undefined = EhTagDatabase.PREFIX_TO_NAMESPACE.get(key);
        english = (ns !== undefined ? ns : cArray[0]) + ':' + eArray[1];
      } else {
        english = cArray[0];
      }
      return new TagEntry(english, chinese);
    }
    return new TagEntry(source, 'null');
  }

  // ---- 编解码辅助 ----

  private static encodeUtf8(s: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < s.length; i++) {
      let c: number = s.charCodeAt(i);
      if (c < 0x80) {
        out.push(c);
      } else if (c < 0x800) {
        out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
      } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
        const next: number = s.charCodeAt(i + 1);
        const cp: number = 0x10000 + ((c - 0xd800) << 10) + (next - 0xdc00);
        out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f),
          0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
        i++;
      } else {
        out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
    }
    const u8: Uint8Array = new Uint8Array(out.length);
    for (let i = 0; i < out.length; i++) {
      u8[i] = out[i];
    }
    return u8;
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    let out: string = '';
    let i: number = 0;
    while (i < bytes.length) {
      const b: number = bytes[i];
      if (b < 0x80) {
        out += String.fromCharCode(b);
        i++;
      } else if (b >= 0xf0) {
        const cp: number = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) |
          ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f);
        out += String.fromCharCode(0xd800 + ((cp - 0x10000) >> 10), 0xdc00 + ((cp - 0x10000) & 0x3ff));
        i += 4;
      } else if (b >= 0xe0) {
        out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f));
        i += 3;
      } else {
        out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
        i += 2;
      }
    }
    return out;
  }

  private static readonly B64_CHARS: string =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  /** Base64 解码切片（对齐 `Base64.decode(bytes, offset, len, DEFAULT)`）。 */
  private static base64Decode(bytes: Uint8Array, offset: number, len: number): Uint8Array {
    const out: number[] = [];
    let buffer: number = 0;
    let bits: number = 0;
    for (let i = offset; i < offset + len; i++) {
      const ch: string = String.fromCharCode(bytes[i]);
      if (ch === '=') {
        break;
      }
      const v: number = EhTagDatabase.B64_CHARS.indexOf(ch);
      if (v < 0) {
        continue; // 忽略空白/换行
      }
      buffer = (buffer << 6) | v;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out.push((buffer >> bits) & 0xff);
      }
    }
    const u8: Uint8Array = new Uint8Array(out.length);
    for (let i = 0; i < out.length; i++) {
      u8[i] = out[i];
    }
    return u8;
  }

  private static base64DecodeString(s: string): Uint8Array {
    const u8: Uint8Array = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) {
      u8[i] = s.charCodeAt(i) & 0xff;
    }
    return EhTagDatabase.base64Decode(u8, 0, u8.length);
  }
}

/** 对齐 `com.hippo.ehviewer.client.data.Tag`（本层叫 TagEntry 以免与 Tag 位标志混淆）。 */
export class TagEntry {
  english: string = '';
  chinese: string = '';

  constructor(english?: string, chinese?: string) {
    if (english !== undefined) {
      this.english = english;
    }
    if (chinese !== undefined) {
      this.chinese = chinese;
    }
  }

  /** 对齐 `involve(String chars)`：english 或 chinese 包含即命中（英文大小写不敏感）。 */
  involve(chars: string): boolean {
    if (chars.length === 0) {
      return false;
    }
    const lower: string = chars.toLowerCase();
    return this.english.toLowerCase().indexOf(lower) >= 0 ||
      this.chinese.indexOf(chars) >= 0 ||
      this.chinese.toLowerCase().indexOf(lower) >= 0;
  }
}

/** 对齐 upstream 的 `Pair<String,String>`（chinese, english）。 */
export class TagSuggestion {
  chinese: string = '';
  english: string = '';
}
/**
 * 标签库的 IO 边界（审计 L-08 的注入点）。
 *
 * 上游从 `R.array.tag_translation_metadata` 取 4 项元数据、从 `AppConfig.getFilesDir("tag-translations")`
 * 读数据文件。ArkTS 侧这两件事都属于宿主（设置页/AppConfig），用本接口注入，
 * 让 `EhTagDatabase` 只负责「字节 → 结构 → 查询」。
 */
export interface TagDatabaseIo {
  /** 4 项元数据 `[sha1Name, sha1Url, dataName, dataUrl]`；不可用时返回 null。 */
  getMetadata(): string[] | null;

  /** 读 `dataName` 对应的完整字节（前 4 字节大端长度 + 正文）；不存在返回 null。 */
  readData(dataName: string): ArrayBuffer | null;
}