import { bundleManager, ConfigurationConstant } from '@kit.AbilityKit';
import { TAB_BAR_CLEARANCE } from '../home/HomeLayout';
import { SchoolnetPasswordDialog } from './SchoolnetPasswordDialog';
import { ExperimentPasswordDialog } from './ExperimentPasswordDialog';
import { SportPasswordDialog } from './SportPasswordDialog';
import { AppTheme, ThemeSeed } from '../../theme/AppTheme';
import { SessionManager } from '../../service/SessionManager';
import { PreferenceService } from '../../service/preference/PreferenceService';
import { AppContext } from '../../service/AppContext';
import { AppNav } from '../../service/nav/AppNav';
import { Log } from '../../utils/Log';

/**
 * 设置页签（M5）：账号区（尽力真实姓名，回退学号）→ 平台账号管理（校园网自助服务查询密码 /
 * 实验平台密码 / 体育平台密码 / 宿舍水机手机号登录）→ 偏好（主题种子色 / 深浅色）→ 关于 → 退出登录。
 * 深浅色切换经 ApplicationContext.setColorMode 触发 onConfigurationUpdate，全局（含窗口背景）自动跟随。
 */
@Component
export struct SettingTab {
  // 主题响应式 token：AppStorage 键由 AppTheme.syncStorage 维护（种子色/深浅色变化时自动更新）。
  @StorageProp('themeSeedIndex') seedIndex: number = 0;
  @StorageProp('themeDarkMode') darkMode: number = 0;
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themePrimaryContainer') themePrimaryContainer: string = '#D0E4FF';
  @StorageProp('settingsVersion') settingsVersion: number = 0;
  @State account: string = PreferenceService.getString('idsAccount', '');
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: SchoolnetPasswordDialog(),
    autoCancel: true
  });
  private experimentDialogController: CustomDialogController = new CustomDialogController({
    builder: ExperimentPasswordDialog(),
    autoCancel: true
  });
  private sportDialogController: CustomDialogController = new CustomDialogController({
    builder: SportPasswordDialog(),
    autoCancel: true
  });

  /** 昵称：尽力真实姓名，回退学号。 */
  private displayName(): string {
    const name: string = PreferenceService.getString('displayName', '');
    return name.length > 0 ? name : this.account;
  }

  private avatarChar(): string {
    const display: string = this.displayName();
    return display.length > 0 ? display.charAt(0) : '西';
  }

  private schoolnetSubtitle(): string {
    return PreferenceService.getString('schoolNetQueryPassword', '').length > 0 ? '已配置查询密码' : '未配置查询密码';
  }

  private experimentSubtitle(): string {
    return PreferenceService.getString('experimentPassword', '').length > 0 ? '已配置实验密码' : '未配置实验密码';
  }

  private sportSubtitle(): string {
    return PreferenceService.getString('sportPassword', '').length > 0 ? '已配置查询密码' : '未配置查询密码';
  }

  private dormWaterSubtitle(): string {
    const phone: string = PreferenceService.getString('dormWaterPhone', '');
    if (PreferenceService.getString('dormWaterToken', '').length === 0) {
      return '未登录';
    }
    return phone.length === 11 ? `已登录 ${phone.substring(0, 3)}****${phone.substring(7)}` : '已登录';
  }

  private openDormWaterLogin(): void {
    const stack: NavPathStack | null = AppNav.stackOrNull();
    if (stack !== null) {
      stack.pushPath({ name: 'dormWaterLogin' });
    }
  }

  private seedOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    AppTheme.seeds().forEach((seed: ThemeSeed): void => {
      options.push({ value: seed.label });
    });
    return options;
  }

  /** Select 按钮文本：selected 只定菜单高亮，按钮文字必须用 value 提供；索引越界钳回首项（与 AppTheme.seedByIndex 回退一致），不允许空文本。 */
  private seedLabel(): string {
    const options: SelectOption[] = this.seedOptions();
    const index: number = this.seedIndex >= 0 && this.seedIndex < options.length ? this.seedIndex : 0;
    const v: string | Resource = options[index].value;
    return typeof v === 'string' ? v : '宇宙蓝';
  }

  private darkOptions(): SelectOption[] {
    return [{ value: '跟随系统' }, { value: '浅色' }, { value: '深色' }];
  }

  private darkLabel(): string {
    const options: SelectOption[] = this.darkOptions();
    const index: number = this.darkMode >= 0 && this.darkMode < options.length ? this.darkMode : 0;
    const v: string | Resource = options[index].value;
    return typeof v === 'string' ? v : '跟随系统';
  }

  private applyDarkMode(mode: number): void {
    AppTheme.saveDarkMode(mode);
    try {
      const colorMode: ConfigurationConstant.ColorMode = mode === 1
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : (mode === 2 ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      AppContext.applicationContext().setColorMode(colorMode);
    } catch (e) {
      Log.warn(`applyDarkMode failed: ${e}`);
    }
  }

  private versionName(): string {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      Log.warn(`versionName failed: ${e}`);
      return '未知';
    }
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.settings_logout_confirm_title'),
      message: $r('app.string.settings_logout_confirm_message'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.settings_logout'),
        fontColor: $r('app.color.error'),
        action: () => {
          this.doLogout();
        }
      }
    });
  }

  private doLogout(): void {
    SessionManager.clearStore('ids');
    PreferenceService.remove('idsAccount');
    PreferenceService.remove('idsPassword');
    AppStorage.setOrCreate('isLoggedIn', false);
  }

  @Builder
  SectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4 })
      .margin({ top: 24, bottom: 8 })
  }

  build() {
    Scroll() {
      Column() {
        Text($r('app.string.tab_settings'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        this.SectionHeader('账号')

        Row({ space: 12 }) {
          Text(this.avatarChar())
            .width(44)
            .height(44)
            .borderRadius(22)
            .backgroundColor(this.themePrimaryContainer)
            .fontColor(this.themePrimary)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)

          Column({ space: 2 }) {
            Text(this.displayName())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(`${this.account} · 西电统一身份认证`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .alignItems(VerticalAlign.Center)

        this.SectionHeader('平台账号')

        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right'))
            .fontSize(20)
            .fontColor([this.themePrimary])
          Column({ space: 2 }) {
            Text($r('app.string.settings_schoolnet_title'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.schoolnetSubtitle())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.dialogController.open())

        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.laboratories'))
            .fontSize(20)
            .fontColor([this.themePrimary])
          Column({ space: 2 }) {
            Text('实验平台（物理实验）')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.experimentSubtitle())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
        .onClick(() => this.experimentDialogController.open())

        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.figure_run'))
            .fontSize(20)
            .fontColor([this.themePrimary])
          Column({ space: 2 }) {
            Text('体育平台')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.sportSubtitle())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
        .onClick(() => this.sportDialogController.open())

        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.cup_fill'))
            .fontSize(20)
            .fontColor([this.themePrimary])
          Column({ space: 2 }) {
            Text('宿舍水机')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.dormWaterSubtitle())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
        .onClick(() => this.openDormWaterLogin())

        this.SectionHeader('偏好')

        Column() {
          Row({ space: 12 }) {
            Text($r('app.string.settings_theme_color'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Select(this.seedOptions())
              .selected(this.seedIndex)
              .value(this.seedLabel())
              .font({ size: 14 })
              .onSelect((index: number): void => {
                AppTheme.saveSeedIndex(index);
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))
            .width('100%')

          Row({ space: 12 }) {
            Text($r('app.string.settings_dark_mode'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Select(this.darkOptions())
              .selected(this.darkMode)
              .value(this.darkLabel())
              .font({ size: 14 })
              .onSelect((index: number): void => {
                this.applyDarkMode(index);
              })
          }
          .width('100%')
          .padding({ top: 12, bottom: 12 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))

        this.SectionHeader('关于')

        Row({ space: 12 }) {
          Text($r('app.string.settings_version'))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.versionName())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))

        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.arrow_right_to_line'))
            .fontSize(20)
            .fontColor([$r('app.color.error')])
          Text($r('app.string.settings_logout'))
            .fontSize(16)
            .fontColor($r('app.color.error'))
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .margin({ top: 24 })
        .onClick(() => this.confirmLogout())
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 16, bottom: TAB_BAR_CLEARANCE })
    }
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
  }
}
