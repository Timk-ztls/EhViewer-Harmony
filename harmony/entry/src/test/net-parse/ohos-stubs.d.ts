// 测试脚手架的 @ohos.* 模块桩（只在 tsc 编译期用，不参与运行时）
// 目的：被测代码可能 import 平台模块；node 环境下这些调用不会被执行，
// 故只需让类型系统满意。

declare module '@ohos.util' {
  const util: any;
  export default util;
}

// @ohos.file.fs：既要当**值**用（fileIo.openSync），也要当**类型命名空间**用（fileIo.File）。
// 用 `export =` + namespace 合并才能两者都满足；纯 `const fileIo: any` 会让 `fileIo.File` 报 TS2503。
declare module '@ohos.file.fs' {
  namespace fileIo {
    interface File {
      fd: number;
      path: string;
      name: string;
    }
    interface Stat {
      size: number;
      mtime: number;
      isDirectory(): boolean;
      isFile(): boolean;
    }
    interface OpenModeType {
      READ_ONLY: number;
      WRITE_ONLY: number;
      READ_WRITE: number;
      CREATE: number;
      TRUNC: number;
      APPEND: number;
    }
    const OpenMode: OpenModeType;
    const AccessModeType: { READ: number; WRITE: number; EXECUTE: number };
    enum WhenceType { SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2 }
    function statSync(path: string | number): Stat;
    function accessSync(path: string, mode?: number): boolean;
    function openSync(path: string, mode: number): File;
    function closeSync(file: File | number): void;
    function readSync(fd: number, buf: ArrayBuffer, opts?: { offset?: number; length?: number }): number;
    function writeSync(fd: number, buf: ArrayBuffer | string, opts?: { offset?: number; length?: number }): number;
    function lseek(fd: number, offset: number, whence?: WhenceType): number;
    function lseekSync(fd: number, offset: number, whence: number): number;
    function fsyncSync(fd: number): void;
    function unlinkSync(path: string): void;
    function renameSync(oldPath: string, newPath: string): void;
    function listFileSync(path: string, opts?: { recursion?: boolean }): string[];
    function rmdirSync(path: string): void;
    function truncateSync(path: string, len: number): void;
    function mkdirSync(path: string, recursion?: boolean): void;
    function readTextSync(path: string, opts?: { offset?: number; length?: number }): string;
    function copyFileSync(src: string, dst: string): void;
    function access(path: string): Promise<boolean>;
    function mkdir(path: string, recursion?: boolean): Promise<void>;
    function stat(path: string): Promise<Stat>;
    function open(path: string, mode: number): Promise<File>;
    function close(file: File): Promise<void>;
    function read(fd: number, buf: ArrayBuffer, opts?: { offset?: number; length?: number }): Promise<number>;
    function write(fd: number, buf: ArrayBuffer | string, opts?: { offset?: number; length?: number }): Promise<number>;
    function unlink(path: string): Promise<void>;
    function rename(oldPath: string, newPath: string): Promise<void>;
    function listFile(path: string): Promise<string[]>;
  }
  export = fileIo;
}

declare module '@ohos.net.http' {
  namespace http {
    interface HttpProxy {
      host: string;
      port: number;
      username?: string;
      password?: string;
      exclusionList: Array<string>;
    }
    type RemoteValidation = 'system' | 'skip';
    interface HttpRequestOptions {
      method?: RequestMethod | string;
      header?: Record<string, string> | Object;
      extraData?: string | ArrayBuffer | Object;
      connectTimeout?: number;
      readTimeout?: number;
      expectDataType?: HttpDataType | number;
      usingCache?: boolean;
      usingProxy?: boolean | HttpProxy;
      maxLimit?: number;
      remoteValidation?: RemoteValidation;
    }
    interface PerformanceTiming {
      redirectTiming?: number;
      dnsTiming?: number;
      tcpTiming?: number;
      tlsTiming?: number;
      totalFinishTiming?: number;
    }
    interface HttpResponse {
      result: string | ArrayBuffer | Object;
      responseCode: number;
      header: Record<string, string> | Object;
      resultType: HttpDataType | number;
      performanceTiming?: PerformanceTiming;
    }
    interface DataReceiveProgressInfo {
      receiveSize: number;
      totalSize: number;
    }
    interface HttpRequest {
      request(url: string, options?: HttpRequestOptions): Promise<HttpResponse>;
      destroy(): void;
      on(type: 'dataReceiveProgress', cb: (info: DataReceiveProgressInfo) => void): void;
      on(type: 'headersReceive', cb: (data: Object) => void): void;
      on(type: string, cb: Function): void;
      off(type: 'dataReceiveProgress', cb?: (info: DataReceiveProgressInfo) => void): void;
      off(type: 'headersReceive', cb?: (data: Object) => void): void;
      off(type: string, cb?: Function): void;
    }
    enum HttpDataType { STRING = 0, OBJECT = 1, ARRAY_BUFFER = 2 }
    enum RequestMethod { OPTIONS = 'OPTIONS', GET = 'GET', HEAD = 'HEAD', POST = 'POST', PUT = 'PUT', DELETE = 'DELETE', TRACE = 'TRACE', CONNECT = 'CONNECT' }
    function createHttp(): HttpRequest;
  }
  export default http;
}

declare module '@ohos.net.socket' {
  namespace socket {
    interface NetAddress {
      address: string;
      family?: number;
      port?: number;
    }
    enum ProxyTypes {
      NONE = 0,
      SOCKS5 = 1
    }
    interface ProxyOptions {
      type: ProxyTypes;
      address: NetAddress;
      username?: string;
      password?: string;
    }
    interface TCPConnectOptions {
      address: NetAddress;
      timeout?: number;
      proxy?: ProxyOptions;
    }
    interface TCPSendOptions {
      data: string | ArrayBuffer;
      encoding?: string;
    }
    interface TLSSecureOptions {
      ca?: string | string[];
      cert?: string;
      key?: string;
      passwd?: string;
    }
    interface TLSConnectOptions {
      address: NetAddress;
      secureOptions: TLSSecureOptions;
      ALPNProtocols?: Array<string>;
      skipRemoteValidation?: boolean;
      proxy?: ProxyOptions;
    }
    interface SocketMessageInfo {
      message: ArrayBuffer;
      remoteInfo?: Object;
    }
    interface TCPSocket {
      connect(options: TCPConnectOptions): Promise<void>;
      send(options: TCPSendOptions): Promise<void>;
      close(): Promise<void>;
      on(type: 'message', cb: (value: SocketMessageInfo) => void): void;
      on(type: 'close' | 'connect', cb: () => void): void;
      on(type: 'error', cb: (err: Object) => void): void;
      off(type: string, cb?: Function): void;
    }
    interface TLSSocket {
      connect(options: TLSConnectOptions): Promise<void>;
      send(data: string | ArrayBuffer): Promise<void>;
      close(): Promise<void>;
      on(type: 'message', cb: (value: SocketMessageInfo) => void): void;
      on(type: 'close' | 'connect', cb: () => void): void;
      on(type: 'error', cb: (err: Object) => void): void;
      off(type: string, cb?: Function): void;
    }
    function constructTCPSocketInstance(): TCPSocket;
    function constructTLSSocketInstance(tcpSocket?: TCPSocket): TLSSocket;
  }
  export default socket;
}

declare module '@ohos.net.connection' {
  namespace connection {
    interface NetAddress {
      address: string;
      family?: number;
      port?: number;
    }
    interface HttpProxy {
      host: string;
      port: number;
      username?: string;
      password?: string;
      exclusionList: Array<string>;
    }
    enum NetBearType {
      BEARER_CELLULAR = 0,
      BEARER_WIFI = 1,
      BEARER_BLUETOOTH = 2,
      BEARER_ETHERNET = 3,
      BEARER_VPN = 4
    }
    interface NetHandle {
      netId: number;
    }
    interface NetCapabilities {
      bearerTypes: Array<NetBearType>;
    }
    interface NetCapabilityInfo {
      netHandle: NetHandle;
      netCap: NetCapabilities;
    }
    interface NetConnectionPropertyInfo {
      netHandle: NetHandle;
      connectionProperties: Object;
    }
    interface NetConnection {
      on(type: 'netAvailable', cb: (handle: NetHandle) => void): void;
      on(type: 'netCapabilitiesChange', cb: (info: NetCapabilityInfo) => void): void;
      on(type: 'netConnectionPropertiesChange', cb: (info: NetConnectionPropertyInfo) => void): void;
      on(type: 'netLost', cb: (handle: NetHandle) => void): void;
      register(cb: (err: Object) => void): void;
      unregister(cb: (err: Object) => void): void;
    }
    function getAddressesByName(host: string): Promise<NetAddress[]>;
    function getAddressesByNameSync(host: string): NetAddress[];
    function getDefaultHttpProxy(): Promise<HttpProxy>;
    function getDefaultNetSync(): NetHandle;
    function getAllNetsSync(): Array<NetHandle>;
    function getNetCapabilitiesSync(handle: NetHandle): NetCapabilities;
    function createNetConnection(): NetConnection;
  }
  export default connection;
}

declare module '@ohos.data.preferences' {
  const preferences: any;
  export default preferences;
}

declare module '@ohos.data.relationalStore' {
  const relationalStore: any;
  export default relationalStore;
}

declare module '@ohos.app.ability.UIAbility' {
  const x: any;
  export default x;
}

// hilog：EhClient 用它记录任务失败（上游 Android 用 Log.e）。
// 形状按实际调用点给：hilog.error(domain, tag, format, ...args)
declare module '@kit.PerformanceAnalysisKit' {
  export const hilog: {
    debug(domain: number, tag: string, format: string, ...args: unknown[]): void;
    info(domain: number, tag: string, format: string, ...args: unknown[]): void;
    warn(domain: number, tag: string, format: string, ...args: unknown[]): void;
    error(domain: number, tag: string, format: string, ...args: unknown[]): void;
  };
}

declare module '@ohos.file.fileuri' {
  namespace fileUri {
    function getUriFromPath(path: string): string;
  }
  export default fileUri;
}

declare module '@ohos.hilog' {
  namespace hilog {
    function debug(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function info(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function warn(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function error(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
  }
  export default hilog;
}