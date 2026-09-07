import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { window } from '@kit.ArkUI';
import { Log } from '../utils/Log';
import { PreferenceService } from '../service/preference/PreferenceService';
import { AppContext } from '../service/AppContext';
import { GlobalTimerController } from '../controller/GlobalTimerController';
import { AppTheme } from '../theme/AppTheme';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContext.init(this.context);
    PreferenceService.init(this.context);
    AppStorage.setOrCreate('isLoggedIn', PreferenceService.getString('idsAccount', '').length > 0);
    try {
      const brightness: number = AppTheme.currentDarkMode();
      const colorMode: number = brightness === 1 ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : (brightness === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      this.context.getApplicationContext().setColorMode(colorMode);
    } catch (err) {
      Log.error(`Failed to set colorMode: ${err}`);
    }
    AppStorage.setOrCreate('isDark', this.isDarkMode());
    // 首帧前播种主题响应式 token（themePrimary 等），保证页面 @StorageProp 绑定到真实值。
    AppTheme.syncStorage();
    Log.info('EntryAbility onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      AppStorage.setOrCreate('isDark', newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      AppTheme.syncStorage();
      this.applyWindowBackground();
    }
  }

  /**
   * 读取生效深浅色：跟随系统时 resourceManager 的 configuration 已解析为系统当前模式。
   * 注意 getConfigurationSync 返回的 colorMode 是 resourceManager.ColorMode（DARK=0/LIGHT=1），
   * 与 ConfigurationConstant.ColorMode 是两个类型，只能各自与自己的枚举值比较。
   */
  private isDarkMode(): boolean {
    try {
      const config: resourceManager.Configuration =
        this.context.getApplicationContext().resourceManager.getConfigurationSync();
      return config.colorMode === resourceManager.ColorMode.DARK;
    } catch (err) {
      Log.error(`Failed to read colorMode: ${err}`);
      return false;
    }
  }

  onDestroy(): void {
    Log.info('Ability onDestroy');
  }

  private windowStageRef?: window.WindowStage;

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Log.info('Ability onWindowStageCreate');
    this.windowStageRef = windowStage;
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Log.error(`Failed to load the content: ${err.code}`);
        return;
      }
      Log.info('Succeeded in loading the content.');
      this.applyWindowBackground();
    });
  }

  /**
   * 主窗口背景色设为应用背景色，让状态栏/导航条安全区与页面背景无缝融合（沉浸式观感）。
   * 资源色无法直接用于窗口接口，此处的深浅色值须与 resources 中 app.color.app_bg 保持一致。
   */
  private applyWindowBackground(): void {
    if (this.windowStageRef === undefined) {
      return;
    }
    try {
      const mainWindow: window.Window = this.windowStageRef.getMainWindowSync();
      mainWindow.setWindowBackgroundColor(AppStorage.get<boolean>('isDark') ? '#121316' : '#F7F8FA');
    } catch (err) {
      Log.error(`Failed to set window background: ${err}`);
    }
  }

  onWindowStageDestroy(): void {
    Log.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    Log.info('Ability onForeground');
    GlobalTimerController.poke();
  }

  onBackground(): void {
    Log.info('Ability onBackground');
  }
}
