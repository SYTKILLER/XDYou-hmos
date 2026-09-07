import { IdsSession, LoginFailedError, PasswordWrongError, ReAuthHandler } from '../service/ids/IdsSession';
import { CaptchaCoordinator } from '../service/ids/CaptchaCoordinator';
import { SliderCaptchaHandler } from '../service/ids/SliderCaptchaHandler';
import { SliderCaptchaClient } from '../service/ids/SliderCaptchaClient';
import { IdsReAuthCancelledError, IdsReAuthExpiredError, IdsReAuthRequiredError,
  CaptchaSolveFailedError } from '../service/ids/IdsAuthProtocol';
import { IdsReAuthClient } from '../service/ids/IdsReAuthClient';
import { ReAuthDialog, ReAuthCoordinator, ReAuthResult } from './ReAuthDialog';
import { SessionManager } from '../service/SessionManager';
import { PreferenceService } from '../service/preference/PreferenceService';
import { Log } from '../utils/Log';

/**
 * 登录页。样式约定（UI 开发规范）：
 * 控件高 50、水平内边距 16、基础间距 16 / 模块间距 24、按钮圆角 12、禁用态 opacity 0.6；
 * 静态色走 $r('app.color.*')（base/dark 自动切换），种子色相关走主题响应式 token（@StorageProp）。
 */
@Component
export struct LoginPage {
  // 主题响应式 token（AppTheme.syncStorage 维护），build 中直接引用才有刷新依赖。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State account: string = PreferenceService.getString('idsAccount', '');
  @State password: string = '';
  @State couldNotView: boolean = true;
  @State busy: boolean = false;
  @State progressMsg: string = '';
  @State progressPercent: number = 0;
  private reAuthDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.reAuthDialogController = new CustomDialogController({
      builder: ReAuthDialog({
        onSuccess: (uri: string): void => {
          this.busy = true;
          this.progressPercent = 80;
          this.progressMsg = this.progressText('login_progress_after_process');
        }
      }),
      autoCancel: false,
      customStyle: false,
      alignment: DialogAlignment.Center,
      cancel: (): void => {
        ReAuthCoordinator.finishCancelled();
      }
    });
  }

  aboutToDisappear(): void {
    this.reAuthDialogController = null;
  }

  private toast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg });
  }

  private progressText(key: string): string {
    if (key === 'login_progress_ready_page') {
      return '正在准备登录页…';
    }
    if (key === 'login_progress_get_encrypt') {
      return '正在获取加密密钥…';
    }
    if (key === 'login_progress_ready_login') {
      return '正在准备登录…';
    }
    if (key === 'login_progress_slider') {
      return '请完成滑块验证…';
    }
    if (key === 'login_progress_submitting') {
      return '正在提交登录…';
    }
    return '正在处理登录后事宜…';
  }

  private errorText(err: Error): string {
    if (err instanceof PasswordWrongError || err instanceof LoginFailedError
      || err instanceof CaptchaSolveFailedError) {
      return err.message;
    }
    if (err instanceof IdsReAuthCancelledError || err instanceof IdsReAuthExpiredError
      || err instanceof IdsReAuthRequiredError) {
      return err.message;
    }
    return '无法连接服务器，请检查网络';
  }

  private async startLogin(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.password.length === 0) {
      this.toast('请输入密码');
      return;
    }
    this.busy = true;
    this.progressPercent = 0;
    this.progressMsg = '';
    SessionManager.clearStore('ids');
    const captchaHandler: SliderCaptchaHandler = (cookieStr: string): Promise<void> => {
      const client = new SliderCaptchaClient(cookieStr);
      return client.solveWithAuto((): Promise<boolean> => CaptchaCoordinator.solve(cookieStr));
    };
    const reAuthHandler: ReAuthHandler = (client: IdsReAuthClient): Promise<string> => {
      this.busy = false;
      this.progressMsg = '';
      const controller: CustomDialogController | null = this.reAuthDialogController;
      if (controller === null) {
        throw new IdsReAuthCancelledError();
      }
      Log.info('reAuth sms challenge, open dialog');
      controller.open();
      return ReAuthCoordinator.solve(client).then((result: ReAuthResult): string => {
        if (result.ok) {
          this.busy = true;
          this.progressPercent = 55;
          this.progressMsg = this.progressText('login_progress_after_process');
          return result.uri;
        }
        if (result.error instanceof IdsReAuthExpiredError) {
          throw result.error;
        }
        throw new IdsReAuthCancelledError();
      });
    };
    try {
      await IdsSession.login(this.account, this.password, captchaHandler,
        (percent: number, key: string): void => {
          this.progressPercent = percent;
          this.progressMsg = this.progressText(key);
        }, undefined, reAuthHandler);
      SessionManager.save('ids');
      PreferenceService.putString('idsAccount', this.account);
      PreferenceService.putString('idsPassword', this.password);
      IdsSession.setActiveReAuthHandler(reAuthHandler);
      try {
        await IdsSession.checkWhetherPostgraduate(captchaHandler, reAuthHandler);
      } catch (e) {
        Log.warn(`postgraduate check skipped: ${e}`);
      }
      this.busy = false;
      this.progressMsg = '';
      AppStorage.setOrCreate('isLoggedIn', true);
    } catch (e) {
      this.busy = false;
      this.progressMsg = '';
      const err: Error = e instanceof Error ? e : new Error(String(e));
      this.toast(this.errorText(err));
      Log.error(`login failed: ${err.message}`);
    }
  }

  build() {
    Column() {
      Blank().height(88)
      Text('XDYou')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themePrimary)
      Text('西安电子科技大学校园助手')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8, bottom: 40 })

      Column({ space: 16 }) {
        TextInput({ text: this.account, placeholder: $r('app.string.login_identity_number') })
          .type(InputType.USER_NAME)
          .width('100%')
          .height(50)
          .maxLength(64)
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.app_card'))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .placeholderFont({ size: 15 })
          .onChange((value: string) => {
            this.account = value;
          })
        TextInput({ text: this.password, placeholder: $r('app.string.login_password') })
          .type(this.couldNotView ? InputType.Password : InputType.Normal)
          .width('100%')
          .height(50)
          .maxLength(64)
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.app_card'))
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .placeholderFont({ size: 15 })
          .onChange((value: string) => {
            this.password = value;
          })
          .onSubmit(() => {
            this.startLogin();
          })
        Row() {
          Text(this.couldNotView ? '显示密码' : '隐藏密码')
            .fontSize(14)
            .fontColor(this.themePrimary)
        }
        .width('100%')
        .height(40)
        .padding({ left: 4 })
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')

      Button($r('app.string.login_login'))
        .width('100%')
        .height(50)
        .borderRadius(12)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 24 })
        .fontColor(this.themeOnPrimary)
        .backgroundColor(this.themePrimary)
        .enabled(!this.busy)
        .opacity(this.busy ? 0.6 : 1)
        .onClick(() => {
          this.startLogin();
        })

      if (this.busy) {
        Row() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.themePrimary)
          Progress({ value: this.progressPercent, total: 100 })
            .width(120)
            .color(this.themePrimary)
            .margin({ left: 12 })
          Text(this.progressMsg)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.app_bg'))
  }
}
