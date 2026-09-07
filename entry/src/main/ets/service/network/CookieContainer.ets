import { rcp } from '@kit.RemoteCommunicationKit';
import { UrlUtil } from '../../utils/net/UrlUtil';
import { Log } from '../../utils/Log';

/**
 * 单条 Cookie（对应 Dart cookie_jar 的 Cookie）。
 * hostOnly = true 表示服务端未下发 Domain 属性，仅对原主机精确匹配。
 */
export class HttpCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  hostOnly: boolean;

  constructor(name: string, value: string, domain: string, path: string, hostOnly: boolean) {
    this.name = name;
    this.value = value;
    this.domain = domain;
    this.path = path;
    this.hostOnly = hostOnly;
  }
}

interface StoredCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  hostOnly: boolean;
}

/**
 * 自研持久化 Cookie 容器（鸿蒙 rcp/http 均无跨请求 Cookie 管理的等价 PersistCookieJar）。
 * - 写入：每次响应后将 Set-Cookie 灌入容器；
 * - 读出：每次请求前按 RFC6265 简化规则（域后缀 + 路径前缀 + path 长度排序）拼 Cookie 头；
 * - 持久化：serialize()/loadFrom() 由 NetworkSession 落盘，保证重启免登录。
 */
export class CookieContainer {
  private cookies: HttpCookie[] = [];

  static hostOf(targetUrl: string): string {
    return UrlUtil.hostOf(targetUrl);
  }

  static pathOf(targetUrl: string): string {
    return UrlUtil.pathOf(targetUrl);
  }

  static resolveRedirect(base: string, location: string): string {
    return UrlUtil.resolveRedirect(base, location);
  }

  /**
   * 将 rcp 响应中的结构化 Cookie 灌入容器。
   */
  setFromResponseCookies(responseCookies: rcp.ResponseCookie[], requestUrl: string): void {
    const host: string = CookieContainer.hostOf(requestUrl);
    for (let i = 0; i < responseCookies.length; i++) {
      const rc: rcp.ResponseCookie = responseCookies[i];
      if (rc.name.length === 0) {
        continue;
      }
      let domain: string = rc.domain !== undefined ? rc.domain.toLowerCase() : '';
      let hostOnly: boolean = domain.length === 0;
      if (hostOnly) {
        domain = host;
      }
      if (domain.startsWith('.')) {
        domain = domain.substring(1);
        hostOnly = false;
      }
      const path: string = rc.path !== undefined && rc.path.length > 0 ? rc.path : '/';
      this.put(new HttpCookie(rc.name, rc.value !== undefined ? rc.value : '', domain, path, hostOnly));
    }
  }

  /**
   * 解析 Set-Cookie 原始头（rcp.cookies 缺失时的回退路径）。
   */
  setFromSetCookieStrings(rawList: string[], requestUrl: string): void {
    const host: string = CookieContainer.hostOf(requestUrl);
    for (let i = 0; i < rawList.length; i++) {
      const parts: string[] = rawList[i].split(';');
      if (parts.length === 0) {
        continue;
      }
      const firstEq: number = parts[0].indexOf('=');
      if (firstEq <= 0) {
        continue;
      }
      const name: string = parts[0].substring(0, firstEq).trim();
      const value: string = parts[0].substring(firstEq + 1).trim();
      let domain: string = '';
      let hostOnly: boolean = true;
      let path: string = '/';
      for (let j = 1; j < parts.length; j++) {
        const attrEq: number = parts[j].indexOf('=');
        const attrName: string = (attrEq > 0 ? parts[j].substring(0, attrEq) : parts[j]).trim().toLowerCase();
        const attrValue: string = attrEq > 0 ? parts[j].substring(attrEq + 1).trim() : '';
        if (attrName === 'domain' && attrValue.length > 0) {
          domain = attrValue.toLowerCase();
          if (domain.startsWith('.')) {
            domain = domain.substring(1);
          }
          hostOnly = false;
        } else if (attrName === 'path' && attrValue.length > 0) {
          path = attrValue;
        }
      }
      if (hostOnly) {
        domain = host;
      }
      this.put(new HttpCookie(name, value, domain, path, hostOnly));
    }
  }

  private put(cookie: HttpCookie): void {
    for (let i = 0; i < this.cookies.length; i++) {
      const existing: HttpCookie = this.cookies[i];
      if (existing.name === cookie.name && existing.domain === cookie.domain
        && existing.path === cookie.path && existing.hostOnly === cookie.hostOnly) {
        this.cookies[i] = cookie;
        return;
      }
    }
    this.cookies.push(cookie);
  }

  private domainMatches(host: string, cookie: HttpCookie): boolean {
    if (cookie.hostOnly) {
      return host === cookie.domain;
    }
    return host === cookie.domain || host.endsWith(`.${cookie.domain}`);
  }

  private pathMatches(requestPath: string, cookiePath: string): boolean {
    if (cookiePath === '/') {
      return true;
    }
    if (!requestPath.startsWith(cookiePath)) {
      return false;
    }
    if (requestPath.length === cookiePath.length) {
      return true;
    }
    return cookiePath.endsWith('/') || requestPath.charAt(cookiePath.length) === '/';
  }

  /**
   * 生成请求 Cookie 头（无匹配 Cookie 返回空串）。
   */
  cookieHeader(targetUrl: string): string {
    const host: string = CookieContainer.hostOf(targetUrl);
    const path: string = CookieContainer.pathOf(targetUrl);
    if (host.length === 0) {
      return '';
    }
    const matched: HttpCookie[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      const c: HttpCookie = this.cookies[i];
      if (this.domainMatches(host, c) && this.pathMatches(path, c.path)) {
        matched.push(c);
      }
    }
    matched.sort((a: HttpCookie, b: HttpCookie): number => b.path.length - a.path.length);
    const segments: string[] = [];
    for (let i = 0; i < matched.length; i++) {
      segments.push(`${matched[i].name}=${matched[i].value}`);
    }
    return segments.join('; ');
  }

  allCookies(): HttpCookie[] {
    return this.cookies;
  }

  clear(): void {
    this.cookies = [];
  }

  isEmpty(): boolean {
    return this.cookies.length === 0;
  }

  serialize(): string {
    const stored: StoredCookie[] = [];
    for (let i = 0; i < this.cookies.length; i++) {
      const c: HttpCookie = this.cookies[i];
      stored.push({ name: c.name, value: c.value, domain: c.domain, path: c.path, hostOnly: c.hostOnly });
    }
    return JSON.stringify(stored);
  }

  loadFrom(json: string): void {
    this.cookies = [];
    if (json.length === 0) {
      return;
    }
    try {
      const parsed: Array<StoredCookie> = JSON.parse(json) as Array<StoredCookie>;
      for (let i = 0; i < parsed.length; i++) {
        const s: StoredCookie = parsed[i];
        this.put(new HttpCookie(s.name, s.value, s.domain, s.path, s.hostOnly));
      }
    } catch (e) {
      Log.warn(`CookieContainer.loadFrom parse failed: ${json.substring(0, 64)}`);
    }
  }
}
