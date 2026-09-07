import { SchoolnetSession, SchoolnetCaptchaHandler } from '../service/schoolnet/SchoolnetSession';
import { GeneralNetworkUsage, CurrentUserNetInfo } from '../model/schoolnet/NetworkUsage';
import { FetchResult } from '../model/FetchResult';
import { Log } from '../utils/Log';

/**
 * 校园网控制器：在线信息（rad_user_info）与自助服务用量（zfw）两条独立数据线。
 * 验证码交互经 SchoolnetCaptchaHandler 由页面承接（Promise 桥只存 resolve，照搬 Coordinator 教训）。
 */
export class SchoolnetController {
  private static userInfo: CurrentUserNetInfo | null = null;
  private static usage: FetchResult<GeneralNetworkUsage> | null = null;
  private static infoInflight: Promise<void> | null = null;
  private static usageInflight: Promise<void> | null = null;

  /**
   * 冷启动直读磁盘缓存（cacheDir schoolnet_user.json / schoolnet_usage.json），
   * 首页瓦片与校园网页面即时有数；已有更新数据（含 fresh）时不覆盖。与 ExamController.loadCache 同模式。
   */
  static loadCache(): void {
    if (SchoolnetController.userInfo === null) {
      SchoolnetController.userInfo = SchoolnetSession.getUserCacheData();
    }
    if (SchoolnetController.usage === null) {
      const cached: GeneralNetworkUsage | null = SchoolnetSession.getCacheData();
      if (cached !== null) {
        SchoolnetController.usage = FetchResult.cached<GeneralNetworkUsage>(
          cached, SchoolnetSession.cacheFetchTime(), 'school_net.cache_hint_network_failed');
      }
    }
  }

  static hasUserInfo(): boolean {
    return SchoolnetController.userInfo !== null;
  }

  static userInfoData(): CurrentUserNetInfo | null {
    return SchoolnetController.userInfo;
  }

  static hasUsage(): boolean {
    return SchoolnetController.usage !== null;
  }

  static usageData(): GeneralNetworkUsage | null {
    const r: FetchResult<GeneralNetworkUsage> | null = SchoolnetController.usage;
    return r !== null ? r.data : null;
  }

  static isUsageFromCache(): boolean {
    const r: FetchResult<GeneralNetworkUsage> | null = SchoolnetController.usage;
    return r !== null && r.isCache;
  }

  static usageFetchTime(): number {
    const r: FetchResult<GeneralNetworkUsage> | null = SchoolnetController.usage;
    return r !== null ? r.fetchTime : 0;
  }

  private static bumpVersion(): void {
    AppStorage.setOrCreate('schoolnetVersion', (AppStorage.get<number>('schoolnetVersion') ?? 0) + 1);
  }

  /** 当前在线信息（无需验证码；失败抛错由页面呈现）。 */
  static refreshUserInfo(): Promise<void> {
    if (SchoolnetController.infoInflight !== null) {
      Log.info('schoolnet rad_user_info: join inflight');
      return SchoolnetController.infoInflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        Log.info('schoolnet rad_user_info fetch start');
        SchoolnetController.userInfo = await SchoolnetSession.getCurrentUserNetInfo();
        const info: CurrentUserNetInfo = SchoolnetController.userInfo;
        Log.info(`schoolnet rad_user_info done: online=${info.isOnline()} user=${info.userName} sum=${info.sumBytes} remain=${info.remainBytes}`);
        SchoolnetController.bumpVersion();
      } finally {
        SchoolnetController.infoInflight = null;
      }
    })();
    SchoolnetController.infoInflight = task;
    return task;
  }

  /** 自助服务用量（未登录时经 handler 交互验证码后登录）。 */
  static refreshUsage(handler: SchoolnetCaptchaHandler): Promise<void> {
    if (SchoolnetController.usageInflight !== null) {
      Log.info('schoolnet zfw: join inflight');
      return SchoolnetController.usageInflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        Log.info('schoolnet zfw fetch start');
        SchoolnetController.usage = await SchoolnetSession.getGeneralNetworkUsage(handler);
        Log.info('schoolnet zfw fetch done');
        SchoolnetController.bumpVersion();
      } finally {
        SchoolnetController.usageInflight = null;
      }
    })();
    SchoolnetController.usageInflight = task;
    return task;
  }
}
