import { DormWaterSession } from '../../service/dormwater/DormWaterSession';
import { DormWaterController } from '../../controller/DormWaterController';
import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { PreferenceService } from '../../service/preference/PreferenceService';
import { Log } from '../../utils/Log';

/**
 * 宿舍水机登录页（对应 Dart dorm_water_window 登录分支，迁移为独立 NavDestination）。
 * 手机号 + 图片验证码（点击刷新）+ 短信验证码；已登录态展示脱敏手机号与退出登录。
 * 登录入口本体在「设置 → 平台账号 → 宿舍水机」，水机页未登录时也直接拉起本页。
 * 注意：@State 只存 base64 data URL 字符串，TypedArray 不能进 @State（真机 crash 教训）。
 */
@Component
export struct DormWaterLoginPage {
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State loggedIn: boolean = DormWaterSession.isLoggedIn();
  @State phone: string = '';
  @State imageCode: string = '';
  @State smsCode: string = '';
  @State captchaDataUrl: string = '';
  @State captchaLoading: boolean = false;
  @State captchaFailed: boolean = false;
  @State sending: boolean = false;
  @State loggingIn: boolean = false;
  private sessionId: string = '';

  private maskedPhone(): string {
    const saved: string = PreferenceService.getString('dormWaterPhone', '');
    if (saved.length === 11) {
      return `${saved.substring(0, 3)}****${saved.substring(7)}`;
    }
    return saved;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private toDataUrl(bytes: Uint8Array): string {
    const b64: string = CryptoUtil.base64Encode(bytes);
    const isPng: boolean = bytes.length > 4 && bytes[0] === 0x89 && bytes[1] === 0x50;
    return `data:image/${isPng ? 'png' : 'jpeg'};base64,${b64}`;
  }

  private loadCaptcha(): void {
    if (this.captchaLoading) {
      return;
    }
    this.captchaLoading = true;
    this.captchaFailed = false;
    DormWaterSession.getCaptcha().then((data): void => {
      this.sessionId = data.sessionId;
      const bytes: Uint8Array = CryptoUtil.base64Decode(data.imageBase64);
      this.captchaDataUrl = this.toDataUrl(bytes);
      this.captchaLoading = false;
    }).catch((e: Object): void => {
      Log.warn(`dormWater captcha failed: ${e}`);
      this.captchaDataUrl = '';
      this.captchaFailed = true;
      this.captchaLoading = false;
    });
  }

  private refreshCaptcha(): void {
    this.imageCode = '';
    this.loadCaptcha();
  }

  private sendSms(): void {
    const phoneValue: string = this.phone.trim();
    const imageValue: string = this.imageCode.trim();
    if (phoneValue.length === 0) {
      this.toast('请输入手机号');
      return;
    }
    if (imageValue.length === 0) {
      this.toast('请输入图片验证码');
      return;
    }
    if (this.sessionId.length === 0) {
      this.toast('请先获取图片验证码');
      return;
    }
    this.sending = true;
    DormWaterSession.sendSmsCode(this.sessionId, imageValue, phoneValue).then((): void => {
      this.sending = false;
      this.toast('验证码已发送');
    }).catch((e: Object): void => {
      this.sending = false;
      this.toast(e instanceof Error ? e.message : '发送验证码失败');
      this.refreshCaptcha();
    });
  }

  private doLogin(): void {
    const phoneValue: string = this.phone.trim();
    const smsValue: string = this.smsCode.trim();
    if (phoneValue.length === 0) {
      this.toast('请输入手机号');
      return;
    }
    if (smsValue.length === 0) {
      this.toast('请输入短信验证码');
      return;
    }
    this.loggingIn = true;
    DormWaterSession.login(phoneValue, smsValue).then((): void => {
      this.loggingIn = false;
      this.loggedIn = true;
      this.toast('登录成功');
      DormWaterController.onLoginStateChanged();
      DormWaterController.refreshDevices().catch((e: Object): void => {
        Log.warn(`dormWater refresh after login failed: ${e}`);
      });
    }).catch((e: Object): void => {
      this.loggingIn = false;
      this.toast(e instanceof Error ? e.message : '登录失败');
    });
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: '确认退出宿舍水机登录？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: $r('app.color.error'),
        action: () => {
          DormWaterSession.logout();
          this.loggedIn = false;
          this.phone = '';
          this.imageCode = '';
          this.smsCode = '';
          this.toast('已退出登录');
          DormWaterController.onLoginStateChanged();
          this.loadCaptcha();
        }
      }
    });
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column({ space: 16 }) {
            if (this.loggedIn) {
              Column({ space: 16 }) {
                SymbolGlyph($r('sys.symbol.cup_fill'))
                  .fontSize(56)
                  .fontColor([this.themePrimary])
                Text(this.maskedPhone().length > 0 ? `已登录：${this.maskedPhone()}` : '已登录')
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                Text('慧798 水机平台账号已绑定，可直接使用宿舍水机功能。')
                  .fontSize(13)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                Button('退出登录')
                  .width('100%')
                  .height(50)
                  .borderRadius(12)
                  .fontSize(15)
                  .backgroundColor($r('app.color.app_card'))
                  .fontColor($r('app.color.error'))
                  .onClick(() => this.confirmLogout())
              }
              .width('100%')
              .padding(24)
              .borderRadius(16)
              .backgroundColor($r('app.color.app_card'))
            } else {
              Column({ space: 16 }) {
                Text('使用手机号登录慧798 水机平台，首次登录需短信验证。')
                  .fontSize(13)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')

                TextInput({ text: this.phone, placeholder: '手机号' })
                  .type(InputType.PhoneNumber)
                  .height(50)
                  .borderRadius(12)
                  .fontSize(15)
                  .width('100%')
                  .onChange((value: string) => {
                    this.phone = value;
                  })

                Row({ space: 12 }) {
                  TextInput({ text: this.imageCode, placeholder: '图片验证码' })
                    .height(50)
                    .borderRadius(12)
                    .fontSize(15)
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      this.imageCode = value;
                    })

                  Column() {
                    if (this.captchaLoading) {
                      LoadingProgress()
                        .width(26)
                        .height(26)
                        .color(this.themePrimary)
                    } else if (this.captchaFailed || this.captchaDataUrl.length === 0) {
                      Text('点击重试')
                        .fontSize(11)
                        .fontColor($r('app.color.error'))
                    } else {
                      Image(this.captchaDataUrl)
                        .objectFit(ImageFit.Fill)
                        .width('100%')
                        .height('100%')
                    }
                  }
                  .width(120)
                  .height(50)
                  .borderRadius(12)
                  .border({ width: 1, color: $r('app.color.divider') })
                  .clip(true)
                  .justifyContent(FlexAlign.Center)
                  .onClick(() => this.refreshCaptcha())
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Row({ space: 12 }) {
                  TextInput({ text: this.smsCode, placeholder: '短信验证码' })
                    .type(InputType.Number)
                    .height(50)
                    .borderRadius(12)
                    .fontSize(15)
                    .layoutWeight(1)
                    .onChange((value: string) => {
                      this.smsCode = value;
                    })

                  Button(this.sending ? '发送中…' : '发送验证码')
                    .height(50)
                    .borderRadius(12)
                    .fontSize(14)
                    .backgroundColor($r('app.color.app_card'))
                    .fontColor(this.themePrimary)
                    .enabled(!this.sending)
                    .opacity(this.sending ? 0.6 : 1)
                    .onClick(() => this.sendSms())
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Button(this.loggingIn ? '正在登录…' : '登 录')
                  .width('100%')
                  .height(50)
                  .borderRadius(12)
                  .fontSize(15)
                  .backgroundColor(this.themePrimary)
                  .fontColor(this.themeOnPrimary)
                  .enabled(!this.loggingIn)
                  .opacity(this.loggingIn ? 0.6 : 1)
                  .onClick(() => this.doLogin())
              }
              .width('100%')
              .padding(24)
              .borderRadius(16)
              .backgroundColor($r('app.color.app_card'))
            }
          }
          .width('100%')
        }
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .title('宿舍水机登录')
    .backgroundColor($r('app.color.app_bg'))
    .onShown(() => {
      if (!this.loggedIn && this.captchaDataUrl.length === 0 && !this.captchaLoading) {
        this.loadCaptcha();
      }
    })
  }
}
