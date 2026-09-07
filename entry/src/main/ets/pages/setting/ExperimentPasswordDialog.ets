import { PreferenceService } from '../../service/preference/PreferenceService';

/**
 * 实验平台（物理实验）密码配置弹窗（克隆 SchoolnetPasswordDialog 模式）。
 * wlsy 物理实验系统账号复用 IDS 学号，此处仅配置独立实验密码（原版明文表单提交）。
 * 同一对话框组件供设置页入口与实验信息页（未配置时直接拉起）共用。
 */
@CustomDialog
export struct ExperimentPasswordDialog {
  controller?: CustomDialogController = undefined;
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State password: string = PreferenceService.getString('experimentPassword', '');

  private save(): void {
    PreferenceService.putString('experimentPassword', this.password.trim());
    AppStorage.setOrCreate('settingsVersion', (AppStorage.get<number>('settingsVersion') ?? 0) + 1);
    this.controller?.close();
  }

  private clearSaved(): void {
    PreferenceService.remove('experimentPassword');
    AppStorage.setOrCreate('settingsVersion', (AppStorage.get<number>('settingsVersion') ?? 0) + 1);
    this.controller?.close();
  }

  build() {
    Column({ space: 16 }) {
      Text('实验平台（物理实验）')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text(`用于物理实验系统查询（wlsy.xidian.edu.cn），账号使用当前登录学号 ${PreferenceService.getString('idsAccount', '')}`)
        .fontSize(13)
        .lineHeight(18)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: this.password, placeholder: '实验平台密码' })
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

      if (PreferenceService.getString('experimentPassword', '').length > 0) {
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
