import { PreferenceService } from '../../service/preference/PreferenceService';

/**
 * 体育平台密码配置弹窗（克隆 SchoolnetPasswordDialog 模式）。
 * tybjxgl 体育平台账号为学号（复用 IDS 账号），此处配置独立查询密码
 * （请求时以 RSA-PKCS1 加密后提交，本地仍明文保存，对齐原版）。
 * 同一对话框组件供设置页入口与体育信息页（未配置时直接拉起）共用。
 */
@CustomDialog
export struct SportPasswordDialog {
  controller?: CustomDialogController = undefined;
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State password: string = PreferenceService.getString('sportPassword', '');

  private save(): void {
    PreferenceService.putString('sportPassword', this.password.trim());
    AppStorage.setOrCreate('settingsVersion', (AppStorage.get<number>('settingsVersion') ?? 0) + 1);
    this.controller?.close();
  }

  private clearSaved(): void {
    PreferenceService.remove('sportPassword');
    AppStorage.setOrCreate('settingsVersion', (AppStorage.get<number>('settingsVersion') ?? 0) + 1);
    this.controller?.close();
  }

  build() {
    Column({ space: 16 }) {
      Text('体育平台')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(`用于体测成绩与体育课成绩查询（tybjxgl.xidian.edu.cn），账号使用当前登录学号 ${PreferenceService.getString('idsAccount', '')}`)
        .fontSize(13)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: this.password, placeholder: '体育平台密码' })
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

      if (PreferenceService.getString('sportPassword', '').length > 0) {
        Text('清除已保存密码')
          .fontSize(13)
          .fontColor($r('app.color.error'))
          .onClick(() => this.clearSaved())
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 20 })
  }
}
