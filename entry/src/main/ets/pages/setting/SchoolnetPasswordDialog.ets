import { PreferenceService } from '../../service/preference/PreferenceService';

/**
 * 校园网自助服务密码配置弹窗（@CustomDialog 规范：controller 可空、this.controller?.close()）。
 * 校园网用户名复用 IDS 学号（对应 Dart schoolnet_session 行为），此处仅配置查询密码。
 */
@CustomDialog
export struct SchoolnetPasswordDialog {
  controller?: CustomDialogController = undefined;
  // 主题响应式 token（AppTheme.syncStorage 维护）。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State password: string = PreferenceService.getString('schoolNetQueryPassword', '');

  private save(): void {
    PreferenceService.putString('schoolNetQueryPassword', this.password.trim());
    AppStorage.setOrCreate('settingsVersion', (AppStorage.get<number>('settingsVersion') ?? 0) + 1);
    this.controller?.close();
  }

  private clearSaved(): void {
    PreferenceService.remove('schoolNetQueryPassword');
    AppStorage.setOrCreate('settingsVersion', (AppStorage.get<number>('settingsVersion') ?? 0) + 1);
    this.controller?.close();
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.settings_schoolnet_title'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text($r('app.string.settings_schoolnet_desc'))
        .fontSize(13)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: this.password, placeholder: '校园网查询密码' })
        .type(InputType.Password)
        .height(50)
        .borderRadius(12)
        .fontSize(15)
        .width('100%')
        .onChange((value: string) => {
          this.password = value;
        })

      Row({ space: 12 }) {
        Button($r('app.string.common_cancel'))
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .fontSize(15)
          .backgroundColor($r('app.color.app_bg'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => this.controller?.close())
        Button($r('app.string.common_save'))
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .fontSize(15)
          .backgroundColor(this.themePrimary)
          .fontColor(this.themeOnPrimary)
          .onClick(() => this.save())
      }
      .width('100%')

      if (PreferenceService.getString('schoolNetQueryPassword', '').length > 0) {
        Text($r('app.string.settings_schoolnet_clear'))
          .fontSize(13)
          .fontColor($r('app.color.error'))
          .onClick(() => this.clearSaved())
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 20 })
  }
}
