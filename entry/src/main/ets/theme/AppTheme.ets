import { PreferenceService } from '../service/preference/PreferenceService';

/**
 * 主题种子色（对应 Dart themes/ default / green / orange，FlexColorScheme 生成值原样搬运）。
 * 默认种子为宇宙蓝 #0A59F7（2026-09-06 用户指定）；深色下主色变浅保证对比度
 * （#5B96FF 对深藏青容器 4.5:1，对深色背景 6.5:1）。
 * 深浅色跟随系统（ApplicationContext.setColorMode 由 EntryAbility 依据偏好设置）。
 * 页面用色约定：背景/正文/分割线等静态色一律走 $r('app.color.*')（base + dark 资源自动切换）；
 * 随种子色/深浅色变化的 primary/primaryContainer/onPrimary 走 AppStorage 响应式 token
 * （themePrimary / themePrimaryContainer / themeOnPrimary），页面用 @StorageProp 绑定。
 * 注意：状态变量必须在 build 中被真实读取才有刷新依赖——只声明一个版本号变量
 * 而不在 build 里引用，变化时不会触发任何 UI 更新（本次主题切换失效的根因）。
 * token 由本类 syncStorage 统一写入：启动、种子色切换、深浅色生效三个入口都会调用。
 */
export class ThemeSeed {
  key: string;
  label: string;
  lightPrimary: string;
  lightPrimaryContainer: string;
  darkPrimary: string;
  darkPrimaryContainer: string;

  constructor(key: string, label: string, lightPrimary: string, lightPrimaryContainer: string,
    darkPrimary: string, darkPrimaryContainer: string) {
    this.key = key;
    this.label = label;
    this.lightPrimary = lightPrimary;
    this.lightPrimaryContainer = lightPrimaryContainer;
    this.darkPrimary = darkPrimary;
    this.darkPrimaryContainer = darkPrimaryContainer;
  }
}

export class AppTheme {
  static readonly SEED_PREF_KEY: string = 'color'; // Dart 端为 int 索引：0 宇宙蓝 / 1 绿 / 2 橙
  static readonly DARK_MODE_PREF_KEY: string = 'brightness'; // 0 system / 1 light / 2 dark（与 Dart demoBlueModeMap 一致）

  private static readonly SEEDS: ThemeSeed[] = [
    new ThemeSeed('default', '宇宙蓝', '#0A59F7', '#D0E4FF', '#5B96FF', '#00325B'),
    new ThemeSeed('green', '绿色', '#4EA34C', '#92C692', '#4EA34C', '#73FA70'),
    new ThemeSeed('orange', '橙色', '#DB683F', '#FFDBCF', '#9FC9FF', '#00325B')
  ];

  static seeds(): ThemeSeed[] {
    return AppTheme.SEEDS;
  }

  static seedByIndex(index: number): ThemeSeed {
    const i: number = index >= 0 && index < AppTheme.SEEDS.length ? index : 0;
    return AppTheme.SEEDS[i];
  }

  static currentSeed(): ThemeSeed {
    return AppTheme.seedByIndex(PreferenceService.getNumber(AppTheme.SEED_PREF_KEY, 0));
  }

  static currentSeedIndex(): number {
    const index: number = PreferenceService.getNumber(AppTheme.SEED_PREF_KEY, 0);
    return index >= 0 && index < AppTheme.SEEDS.length ? index : 0;
  }

  static currentDarkMode(): number {
    const mode: number = PreferenceService.getNumber(AppTheme.DARK_MODE_PREF_KEY, 0);
    return mode >= 0 && mode <= 2 ? mode : 0;
  }

  static primary(isDark: boolean): string {
    const seed: ThemeSeed = AppTheme.currentSeed();
    return isDark ? seed.darkPrimary : seed.lightPrimary;
  }

  static primaryContainer(isDark: boolean): string {
    const seed: ThemeSeed = AppTheme.currentSeed();
    return isDark ? seed.darkPrimaryContainer : seed.lightPrimaryContainer;
  }

  /**
   * 主色之上的文字/图标色：深色下主色变浅（#5B96FF 等），白字对比度不足 3:1，改用深藏青。
   */
  static onPrimary(isDark: boolean): string {
    return isDark ? '#00325B' : '#FFFFFF';
  }

  static saveSeedIndex(index: number): void {
    PreferenceService.putNumber(AppTheme.SEED_PREF_KEY, index);
    AppTheme.syncStorage();
  }

  static saveDarkMode(mode: number): void {
    PreferenceService.putNumber(AppTheme.DARK_MODE_PREF_KEY, mode);
    AppTheme.syncStorage();
  }

  /**
   * 把当前主题的全部响应式值写入 AppStorage，供页面 @StorageProp 绑定。
   * 深浅色翻转时 EntryAbility.onConfigurationUpdate 先更新 'isDark' 再调本方法。
   */
  static syncStorage(): void {
    const isDark: boolean = AppStorage.get<boolean>('isDark') ?? false;
    AppStorage.setOrCreate('themeSeedIndex', AppTheme.currentSeedIndex());
    AppStorage.setOrCreate('themeDarkMode', AppTheme.currentDarkMode());
    AppStorage.setOrCreate('themePrimary', AppTheme.primary(isDark));
    AppStorage.setOrCreate('themePrimaryContainer', AppTheme.primaryContainer(isDark));
    AppStorage.setOrCreate('themeOnPrimary', AppTheme.onPrimary(isDark));
  }
}
