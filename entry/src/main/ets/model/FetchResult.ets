/**
 * 统一抓取结果（对应 Dart model/fetch_result.dart）：
 * fresh = 网络新数据；cached = 请求失败回退本地缓存（fetchTime 为缓存落盘时间）。
 */
export class FetchResult<T> {
  readonly data: T;
  readonly isCache: boolean;
  readonly fetchTime: number;
  readonly hintKey: string;

  private constructor(data: T, isCache: boolean, fetchTime: number, hintKey: string) {
    this.data = data;
    this.isCache = isCache;
    this.fetchTime = fetchTime;
    this.hintKey = hintKey;
  }

  static fresh<T>(data: T): FetchResult<T> {
    return new FetchResult<T>(data, false, Date.now(), '');
  }

  static cached<T>(data: T, fetchTime: number, hintKey: string): FetchResult<T> {
    return new FetchResult<T>(data, true, fetchTime, hintKey);
  }
}
