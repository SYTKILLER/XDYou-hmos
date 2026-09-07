import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Log } from '../utils/Log';

/**
 * UIAbility 上下文持有者：服务层（非组件环境）取 cacheDir 等路径用。
 * EntryAbility.onCreate 注入，对应 Dart getApplicationSupportDirectory() 的落点。
 */
export class AppContext {
  private static context: common.UIAbilityContext | null = null;

  static init(context: common.UIAbilityContext): void {
    AppContext.context = context;
  }

  private static get(): common.UIAbilityContext {
    const ctx: common.UIAbilityContext | null = AppContext.context;
    if (ctx === null) {
      throw new Error('AppContext not initialized');
    }
    return ctx;
  }

  /** ApplicationContext（应用级上下文，供深浅色切换等设置操作）。 */
  static applicationContext(): common.ApplicationContext {
    return AppContext.get().getApplicationContext();
  }

  private static cachePath(fileName: string): string {
    return `${AppContext.get().cacheDir}/${fileName}`;
  }

  /** 读缓存文件全文；不存在/读失败返回 null。 */
  static readCacheText(fileName: string): string | null {
    try {
      return fs.readTextSync(AppContext.cachePath(fileName));
    } catch (e) {
      Log.warn(`AppContext.readCacheText ${fileName}: ${e}`);
      return null;
    }
  }

  /** 写缓存文件（覆盖）；成功返回 true。 */
  static writeCacheText(fileName: string, content: string): boolean {
    const path: string = AppContext.cachePath(fileName);
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      return true;
    } catch (e) {
      Log.error(`AppContext.writeCacheText ${fileName}: ${e}`);
      return false;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          Log.warn(`AppContext.close ${fileName}: ${e}`);
        }
      }
    }
  }

  /** 缓存文件最后修改时间（毫秒）；不存在/失败返回 0。 */
  static cacheModifiedMs(fileName: string): number {
    try {
      const stat: fs.Stat = fs.statSync(AppContext.cachePath(fileName));
      return stat.mtime * 1000;
    } catch (e) {
      return 0;
    }
  }

  /** 删除缓存文件（不存在视为成功）。 */
  static deleteCache(fileName: string): void {
    try {
      fs.unlinkSync(AppContext.cachePath(fileName));
    } catch (e) {
      Log.warn(`AppContext.deleteCache ${fileName}: ${e}`);
    }
  }
}
