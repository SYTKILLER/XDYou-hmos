import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 统一日志封装（hilog）。对应 Dart 端 talker 日志的最小替代。
 */
export class Log {
  private static readonly DOMAIN: number = 0xD001;
  private static readonly TAG: string = 'XDYou';

  static debug(msg: string): void {
    hilog.debug(Log.DOMAIN, Log.TAG, '%{public}s', msg);
  }

  static info(msg: string): void {
    hilog.info(Log.DOMAIN, Log.TAG, '%{public}s', msg);
  }

  static warn(msg: string): void {
    hilog.warn(Log.DOMAIN, Log.TAG, '%{public}s', msg);
  }

  static error(msg: string): void {
    hilog.error(Log.DOMAIN, Log.TAG, '%{public}s', msg);
  }
}
