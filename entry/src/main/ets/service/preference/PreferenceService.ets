import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Log } from '../../utils/Log';

/**
 * 偏好存储封装（@ohos.data.preferences，同步 API）。
 * 对应 Dart shared_preferences 的 Preference 枚举（约 45 个键，随模块推进逐步补全）。
 * 使用 getPreferencesSync 在 EntryAbility.onCreate 同步初始化，避免页面早于存储就绪的竞态。
 */
export class PreferenceService {
  private static store: preferences.Preferences | null = null;
  private static readonly STORE_NAME: string = 'xdyou_prefs';

  static init(context: common.Context): void {
    try {
      PreferenceService.store = preferences.getPreferencesSync(context, { name: PreferenceService.STORE_NAME });
    } catch (e) {
      Log.error(`PreferenceService.init failed: ${e}`);
      PreferenceService.store = null;
    }
  }

  private static storeOrThrow(): preferences.Preferences {
    const store: preferences.Preferences | null = PreferenceService.store;
    if (store === null) {
      throw new Error('PreferenceService not initialized');
    }
    return store;
  }

  static getString(key: string, defaultValue: string): string {
    const store: preferences.Preferences = PreferenceService.storeOrThrow();
    const v: preferences.ValueType = store.getSync(key, defaultValue);
    return typeof v === 'string' ? v : defaultValue;
  }

  static getBool(key: string, defaultValue: boolean): boolean {
    const store: preferences.Preferences = PreferenceService.storeOrThrow();
    const v: preferences.ValueType = store.getSync(key, defaultValue);
    return typeof v === 'boolean' ? v : defaultValue;
  }

  static getNumber(key: string, defaultValue: number): number {
    const store: preferences.Preferences = PreferenceService.storeOrThrow();
    const v: preferences.ValueType = store.getSync(key, defaultValue);
    return typeof v === 'number' ? v : defaultValue;
  }

  static putString(key: string, value: string): void {
    try {
      const store: preferences.Preferences = PreferenceService.storeOrThrow();
      store.putSync(key, value);
      store.flush();
    } catch (e) {
      Log.error(`PreferenceService.putString ${key} failed: ${e}`);
    }
  }

  static putBool(key: string, value: boolean): void {
    try {
      const store: preferences.Preferences = PreferenceService.storeOrThrow();
      store.putSync(key, value);
      store.flush();
    } catch (e) {
      Log.error(`PreferenceService.putBool ${key} failed: ${e}`);
    }
  }

  static putNumber(key: string, value: number): void {
    try {
      const store: preferences.Preferences = PreferenceService.storeOrThrow();
      store.putSync(key, value);
      store.flush();
    } catch (e) {
      Log.error(`PreferenceService.putNumber ${key} failed: ${e}`);
    }
  }

  static remove(key: string): void {
    try {
      const store: preferences.Preferences = PreferenceService.storeOrThrow();
      store.deleteSync(key);
      store.flush();
    } catch (e) {
      Log.error(`PreferenceService.remove ${key} failed: ${e}`);
    }
  }

  static has(key: string): boolean {
    const store: preferences.Preferences = PreferenceService.storeOrThrow();
    return store.hasSync(key);
  }
}
