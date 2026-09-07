import { url } from '@kit.ArkTS';
import { Log } from '../Log';

/**
 * URL / 表单编码纯函数集（无原生依赖，可本地单测）。
 */
export class UrlUtil {
  static hostOf(targetUrl: string): string {
    try {
      const u: url.URL = new url.URL(targetUrl);
      return u.hostname.toLowerCase();
    } catch (e) {
      Log.warn(`UrlUtil.hostOf invalid url: ${targetUrl}`);
      return '';
    }
  }

  static pathOf(targetUrl: string): string {
    try {
      const u: url.URL = new url.URL(targetUrl);
      const p: string = u.pathname;
      if (p.length === 0) {
        return '/';
      }
      return p;
    } catch (e) {
      return '/';
    }
  }

  static schemeOf(targetUrl: string): string {
    try {
      const u: url.URL = new url.URL(targetUrl);
      return u.protocol.toLowerCase();
    } catch (e) {
      return '';
    }
  }

  /**
   * 以 base 为基准解析 Location（绝对 / 协议相对 / 根相对 / 相对路径）。
   */
  static resolveRedirect(base: string, location: string): string {
    const trimmed: string = location.trim();
    if (trimmed.length === 0) {
      return base;
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    try {
      const u: url.URL = new url.URL(base);
      const origin: string = `${u.protocol}//${u.host}`;
      if (trimmed.startsWith('//')) {
        return `${u.protocol}${trimmed}`;
      }
      if (trimmed.startsWith('/')) {
        return `${origin}${trimmed}`;
      }
      const basePath: string = u.pathname;
      const dirIndex: number = basePath.lastIndexOf('/');
      const dir: string = dirIndex >= 0 ? basePath.substring(0, dirIndex + 1) : '/';
      return `${origin}${dir}${trimmed}`;
    } catch (e) {
      return trimmed;
    }
  }

  static formEncode(fields: Map<string, string>): string {
    const parts: string[] = [];
    fields.forEach((value: string, key: string) => {
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    });
    return parts.join('&');
  }
}
