import { XxcappSession } from '../service/ids/XxcappSession';
import { AccountInfo } from '../model/user/AccountInfo';
import { AppContext } from '../service/AppContext';
import { PreferenceService } from '../service/preference/PreferenceService';
import { Log } from '../utils/Log';

/**
 * 账号信息控制器（2026-09-15 新增，无 Dart 对应）：设置页账号区的姓名/头像数据线。
 * 数据源为「学在西电」门户 mine/index（真实姓名 + 学号 + 头像），低频变化：
 * 磁盘快照 6 小时内视为新鲜，ensureFresh 超期才走 CAS→xxcapp 链路刷新（含 inflight 去重）。
 * 版本号 accountVersion 供页面 @StorageProp 建立刷新依赖（bump 后重读 data()）。
 */
export class AccountController {
  private static info: AccountInfo | null = null;
  private static inflight: Promise<void> | null = null;
  private static readonly STALE_MS: number = 6 * 60 * 60 * 1000;

  /** 冷启动直读磁盘快照（与 SchoolnetController.loadCache 同模式，已有内存数据早退）。 */
  static loadCache(): void {
    if (AccountController.info === null) {
      AccountController.info = XxcappSession.getCacheData();
    }
  }

  static data(): AccountInfo | null {
    return AccountController.info;
  }

  /** 展示名：门户真实姓名优先，回退偏好 displayName（校园网/成绩等来源），再回退学号。 */
  static displayName(): string {
    const info: AccountInfo | null = AccountController.info;
    if (info !== null && info.realName.length > 0) {
      return info.realName;
    }
    const pref: string = PreferenceService.getString('displayName', '');
    if (pref.length > 0) {
      return pref;
    }
    return PreferenceService.getString('idsAccount', '');
  }

  private static bumpVersion(): void {
    AppStorage.setOrCreate('accountVersion', (AppStorage.get<number>('accountVersion') ?? 0) + 1);
  }

  /**
   * 按需刷新：缓存缺失或超过 6 小时才发起；inflight 进行中直接返回。
   */
  static ensureFresh(): void {
    AccountController.loadCache();
    if (AccountController.inflight !== null) {
      Log.info('account info: join inflight');
      return;
    }
    const mtime: number = AppContext.cacheModifiedMs(XxcappSession.CACHE_FILE);
    if (mtime !== 0 && Date.now() - mtime <= AccountController.STALE_MS) {
      return;
    }
    AccountController.refresh();
  }

  /**
   * 强制刷新（登录成功后会话正热时也可调用）。后台静默语义：
   * 失败只记日志不抛错，页面持有缓存/占位即可。
   */
  static refresh(): Promise<void> {
    AccountController.loadCache();
    if (AccountController.inflight !== null) {
      Log.info('account info: join inflight');
      return AccountController.inflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        Log.info('account info fetch start');
        const fresh: AccountInfo = await XxcappSession.getAccountInfo();
        AccountController.info = fresh;
        AppContext.writeCacheText(XxcappSession.CACHE_FILE, JSON.stringify(fresh.toCacheJson()));
        if (fresh.realName.length > 0) {
          PreferenceService.putString('displayName', fresh.realName);
        }
        AccountController.bumpVersion();
        Log.info(`account info fetch done: name=${fresh.realName} avatar=${fresh.avatarUrl.length > 0 ? 'yes' : 'no'}`);
      } catch (e) {
        Log.warn(`account info fetch failed: ${e}`);
      } finally {
        AccountController.inflight = null;
      }
    })();
    AccountController.inflight = task;
    return task;
  }

  /** 退出登录清空：内存 + 磁盘快照 + 版本号（防止下个账号串名）。 */
  static clear(): void {
    AccountController.info = null;
    AccountController.inflight = null;
    AppContext.deleteCache(XxcappSession.CACHE_FILE);
    AccountController.bumpVersion();
  }
}
