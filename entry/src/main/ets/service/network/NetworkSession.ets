import { rcp } from '@kit.RemoteCommunicationKit';
import { CharsetDecoder } from '../../utils/charset/CharsetDecoder';
import { UrlUtil } from '../../utils/net/UrlUtil';
import { CookieContainer } from './CookieContainer';
import { Log } from '../../utils/Log';

/**
 * rcp 封装（替代 Dart dio）。
 *
 * 尖兵结论（2026-09-05，SDK d.ts 证实）：
 * - @ohos.net.http 默认自动跟随 30x；maxRedirects:0 时 reject 2300047，拿不到 302 的 Location；
 * - rcp 的 TransferConfiguration.autoRedirect=false 可将 302 作为正常 Response 返回（statusCode/headers.location 可读）；
 * 因此选 rcp 作为网络层，手动重定向与 Dart 端 dio(followRedirects=false) 行为对齐。
 *
 * Cookie：rcp 不提供跨请求持久 Cookie 管理，全部由 CookieContainer 手动注入/回收。
 */
export class SessionResponse {
  statusCode: number = 0;
  finalUrl: string = '';
  location: string = '';
  bodyBytes: ArrayBuffer | null = null;
  bodyText: string = '';
  isRedirect: boolean = false;
  /** 原始 Set-Cookie 列表（wlsy/wgyreport 等需手工拼 Cookie 串的平台使用）。 */
  setCookies: string[] = [];
  /** 常规响应头（每名取首值；wgyreport 的 session_id/cookie 头等使用）。 */
  headers: Map<string, string> = new Map();
}

export class SessionOptions {
  headers: Map<string, string> = new Map();
  body: string = '';
  hasBody: boolean = false;
  contentType: string = '';
  charset: string = CharsetDecoder.UTF8;
  /** >0 时手动跟随重定向（301/302/303 转 GET；307/308 保方法），0 = 原样返回 3xx */
  maxHops: number = 0;
  connectTimeoutMs: number = 10000;
  transferTimeoutMs: number = 30000;
}

export class NetworkSession {
  private static readonly USER_AGENT: string =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 XDYou/2.0.0';
  private static readonly HARD_HOPS_LIMIT: number = 10;

  readonly storeName: string;
  readonly cookies: CookieContainer;
  private session: rcp.Session;

  constructor(storeName: string) {
    this.storeName = storeName;
    this.cookies = new CookieContainer();
    const sessionConfig: rcp.SessionConfiguration = {
      headers: { 'user-agent': NetworkSession.USER_AGENT },
      requestConfiguration: {
        transfer: {
          autoRedirect: false,
          timeout: { connectMs: 10000, transferMs: 30000 }
        }
      }
    };
    this.session = rcp.createSession(sessionConfig);
  }

  /**
   * x-www-form-urlencoded 编码（对应 Dart dio form 表单默认行为）。
   */
  static formEncode(fields: Map<string, string>): string {
    return UrlUtil.formEncode(fields);
  }

  private static headerValue(headers: rcp.ResponseHeaders, name: string): string {
    const value: string | string[] | undefined = headers[name];
    if (value === undefined) {
      return '';
    }
    if (typeof value === 'string') {
      return value;
    }
    return value.join(', ');
  }

  private static setCookieList(headers: rcp.ResponseHeaders): string[] {
    const value: string | string[] | undefined = headers['set-cookie'];
    if (value === undefined) {
      return [];
    }
    if (typeof value === 'string') {
      return [value];
    }
    return value;
  }

  private buildHeaders(options: SessionOptions, method: string, targetUrl: string): rcp.RequestHeaders {
    const headers: rcp.RequestHeaders = {};
    headers['user-agent'] = NetworkSession.USER_AGENT;
    if (options.contentType.length > 0) {
      headers['content-type'] = options.contentType;
    }
    const cookieLine: string = this.cookies.cookieHeader(targetUrl);
    const extraCookie: string = options.headers.get('cookie') !== undefined ? options.headers.get('cookie') as string : '';
    const mergedCookie: string = extraCookie.length > 0
      ? (cookieLine.length > 0 ? `${cookieLine}; ${extraCookie}` : extraCookie)
      : cookieLine;
    if (mergedCookie.length > 0) {
      headers['cookie'] = mergedCookie;
    }
    options.headers.forEach((value: string, key: string) => {
      if (key.toLowerCase() !== 'cookie') {
        headers[key] = value;
      }
    });
    if (method === 'POST' && options.contentType.length === 0) {
      headers['content-type'] = 'application/x-www-form-urlencoded';
    }
    return headers;
  }

  private ingestCookies(response: rcp.Response, requestUrl: string): void {
    if (response.cookies !== undefined && response.cookies.length > 0) {
      this.cookies.setFromResponseCookies(response.cookies, requestUrl);
      return;
    }
    const raw: string[] = NetworkSession.setCookieList(response.headers);
    if (raw.length > 0) {
      this.cookies.setFromSetCookieStrings(raw, requestUrl);
    }
  }

  private wrap(response: rcp.Response, requestUrl: string, options: SessionOptions): SessionResponse {
    const result: SessionResponse = new SessionResponse();
    result.statusCode = response.statusCode;
    result.finalUrl = requestUrl;
    result.location = NetworkSession.headerValue(response.headers, 'location');
    result.setCookies = NetworkSession.setCookieList(response.headers);
    result.isRedirect = result.statusCode === 301 || result.statusCode === 302
      || result.statusCode === 303 || result.statusCode === 307 || result.statusCode === 308;
    const headerKeys: string[] = Object.keys(response.headers);
    headerKeys.forEach((key: string): void => {
      const value: string | string[] | undefined = response.headers[key];
      if (value === undefined) {
        return;
      }
      result.headers.set(key.toLowerCase(), typeof value === 'string' ? value : value[0]);
    });
    if (response.body !== undefined) {
      result.bodyBytes = response.body;
      result.bodyText = CharsetDecoder.decodeToString(response.body, options.charset);
    }
    return result;
  }

  async request(method: string, targetUrl: string, options: SessionOptions): Promise<SessionResponse> {
    const opts: SessionOptions = options !== undefined ? options : new SessionOptions();
    let currentUrl: string = targetUrl;
    let currentMethod: string = method;
    let hops: number = 0;
    for (; ;) {
      const headers: rcp.RequestHeaders = this.buildHeaders(opts, currentMethod, currentUrl);
      let content: rcp.RequestContent | undefined = undefined;
      if (opts.hasBody && currentMethod !== 'GET') {
        content = opts.body;
      }
      const request: rcp.Request = new rcp.Request(currentUrl, currentMethod, headers, content);
      const response: rcp.Response = await this.session.fetch(request);
      this.ingestCookies(response, currentUrl);
      const wrapped: SessionResponse = this.wrap(response, currentUrl, opts);
      if (wrapped.isRedirect && opts.maxHops > 0 && wrapped.location.length > 0) {
        hops++;
        if (hops > opts.maxHops || hops > NetworkSession.HARD_HOPS_LIMIT) {
          Log.warn(`NetworkSession redirect hops exhausted: ${targetUrl}`);
          return wrapped;
        }
        const nextUrl: string = CookieContainer.resolveRedirect(currentUrl, wrapped.location);
        if (wrapped.statusCode === 301 || wrapped.statusCode === 302 || wrapped.statusCode === 303) {
          currentMethod = 'GET';
          opts.hasBody = false;
        }
        currentUrl = nextUrl;
        continue;
      }
      return wrapped;
    }
  }

  async get(targetUrl: string, options?: SessionOptions): Promise<SessionResponse> {
    return this.request('GET', targetUrl, options !== undefined ? options : new SessionOptions());
  }

  async postForm(targetUrl: string, fields: Map<string, string>, options?: SessionOptions): Promise<SessionResponse> {
    const opts: SessionOptions = options !== undefined ? options : new SessionOptions();
    opts.hasBody = true;
    opts.body = NetworkSession.formEncode(fields);
    opts.contentType = 'application/x-www-form-urlencoded';
    return this.request('POST', targetUrl, opts);
  }

  async postRaw(targetUrl: string, contentType: string, body: string, options?: SessionOptions): Promise<SessionResponse> {
    const opts: SessionOptions = options !== undefined ? options : new SessionOptions();
    opts.hasBody = true;
    opts.body = body;
    opts.contentType = contentType;
    return this.request('POST', targetUrl, opts);
  }

  async close(): Promise<void> {
    try {
      await this.session.close();
    } catch (e) {
      Log.warn(`NetworkSession.close error: ${e}`);
    }
  }
}
