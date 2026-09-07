import { IdsReAuthClient } from '../service/ids/IdsReAuthClient';
import { IdsProtocolError, IdsReAuthCancelledError, IdsReAuthExpiredError,
  IdsSmsDelivery } from '../service/ids/IdsAuthProtocol';
import { Log } from '../utils/Log';

/**
 * 短信二次认证结果（resolve-only：Promise reject 形参与标准库 any 比对会触发
 * arkts-no-structural-typing，因此用结果对象代替 reject）。
 * 注意 error 字段不能声明为 Error | null——ArkTS 中 Error 是接口式类型，
 * 子类实例赋值给 Error 字段同样触发结构化类型检查，必须用具体子类联合。
 */
export class ReAuthResult {
  ok: boolean = false;
  uri: string = '';
  error: IdsReAuthCancelledError | IdsReAuthExpiredError | null = null;
}

/**
 * 登录流程 ↔ 短信二次认证对话框 的桥接（对应 Dart showIDSReAuthDialog）：
 * 服务层 solve(client) → LoginPage 打开 CustomDialog → 完成/取消/过期 → resolve 结果。
 */
export class ReAuthCoordinator {
  private static pendingClient: IdsReAuthClient | null = null;
  private static resolver: ((result: ReAuthResult) => void) | null = null;

  static pendingClientValue(): IdsReAuthClient | null {
    return ReAuthCoordinator.pendingClient;
  }

  static solve(client: IdsReAuthClient): Promise<ReAuthResult> {
    ReAuthCoordinator.pendingClient = client;
    return new Promise<ReAuthResult>((resolve: (result: ReAuthResult) => void) => {
      ReAuthCoordinator.resolver = resolve;
    });
  }

  static finishWithUri(uri: string): void {
    if (ReAuthCoordinator.resolver !== null) {
      const result: ReAuthResult = new ReAuthResult();
      result.ok = true;
      result.uri = uri;
      ReAuthCoordinator.resolver(result);
      ReAuthCoordinator.cleanup();
    }
  }

  static finishCancelled(): void {
    if (ReAuthCoordinator.resolver !== null) {
      const result: ReAuthResult = new ReAuthResult();
      result.ok = false;
      result.error = new IdsReAuthCancelledError();
      ReAuthCoordinator.resolver(result);
      ReAuthCoordinator.cleanup();
    }
  }

  static finishExpired(err: IdsReAuthExpiredError): void {
    if (ReAuthCoordinator.resolver !== null) {
      const result: ReAuthResult = new ReAuthResult();
      result.ok = false;
      result.error = err;
      ReAuthCoordinator.resolver(result);
      ReAuthCoordinator.cleanup();
    }
  }

  private static cleanup(): void {
    ReAuthCoordinator.resolver = null;
    ReAuthCoordinator.pendingClient = null;
  }
}

/**
 * 短信二次认证对话框（对应 Dart _IDSReAuthDialog）：
 * 发送验证码（含重发倒计时与已发送态）→ 输入验证码 → 可选勾选"信任此设备"（skipTmpReAuth）→ 提交。
 */
@CustomDialog
export struct ReAuthDialog {
  controller?: CustomDialogController;
  onSuccess: (uri: string) => void = () => {
  };
  // 主题响应式 token（AppTheme.syncStorage 维护），按钮/描边颜色随种子色/深浅色刷新。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State code: string = '';
  @State notice: string = '';
  @State errorText: string = '';
  @State trustDevice: boolean = false;
  @State sending: boolean = false;
  @State submitting: boolean = false;
  @State secondsRemaining: number = 0;
  private client: IdsReAuthClient | null = null;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.client = ReAuthCoordinator.pendingClientValue();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private startCountdown(seconds: number): void {
    this.stopTimer();
    this.secondsRemaining = seconds;
    if (seconds <= 0) {
      return;
    }
    this.timerId = setInterval(() => {
      if (this.secondsRemaining <= 1) {
        this.stopTimer();
        this.secondsRemaining = 0;
        return;
      }
      this.secondsRemaining--;
    }, 1000);
  }

  private busy(): boolean {
    return this.sending || this.submitting;
  }

  private mapError(err: Error): string {
    if (err instanceof IdsProtocolError) {
      return err.message;
    }
    return '网络错误，请重试';
  }

  private async sendCode(): Promise<void> {
    if (this.client === null || this.busy()) {
      return;
    }
    this.sending = true;
    this.errorText = '';
    try {
      const delivery: IdsSmsDelivery = await this.client.sendSms();
      const recipient: string = delivery.maskedMobile.length > 0
        ? delivery.maskedMobile : this.client.recipientDescription;
      this.notice = recipient.length > 0 ? `${delivery.message}（${recipient}）` : delivery.message;
      this.startCountdown(delivery.retryAfterSeconds);
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      if (err instanceof IdsReAuthExpiredError) {
        this.expire(err);
        return;
      }
      this.errorText = this.mapError(err);
      Log.warn(`reAuth sendSms failed: ${err.message}`);
    } finally {
      this.sending = false;
    }
  }

  private async submit(): Promise<void> {
    if (this.client === null || this.busy()) {
      return;
    }
    if (this.code.trim().length === 0) {
      this.errorText = '请输入短信验证码';
      return;
    }
    this.submitting = true;
    this.errorText = '';
    try {
      const uri: string = await this.client.submitSms(this.code, this.trustDevice);
      this.controller?.close();
      ReAuthCoordinator.finishWithUri(uri);
      this.onSuccess(uri);
    } catch (e) {
      const err: Error = e instanceof Error ? e : new Error(String(e));
      if (err instanceof IdsReAuthExpiredError) {
        this.expire(err);
        return;
      }
      if (err instanceof IdsProtocolError) {
        this.errorText = err.message;
        this.code = '';
      } else {
        this.errorText = this.mapError(err);
      }
      Log.warn(`reAuth submit failed: ${err.message}`);
    } finally {
      this.submitting = false;
    }
  }

  private expire(err: IdsReAuthExpiredError): void {
    this.controller?.close();
    ReAuthCoordinator.finishExpired(err);
  }

  build() {
    Column() {
      Text('短信二次认证')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      Text('为确认是你本人操作，请输入收到的短信验证码')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
      TextInput({ text: this.code, placeholder: '验证码' })
        .type(InputType.Number)
        .width('100%')
        .maxLength(8)
        .enabled(!this.busy())
        .margin({ top: 16 })
        .onChange((value: string) => {
          this.code = value;
        })
        .onSubmit(() => {
          this.submit();
        })
      Button(this.secondsRemaining > 0 ? `重新发送（${this.secondsRemaining}s）` : '发送验证码')
        .width('100%')
        .height(36)
        .fontSize(14)
        .margin({ top: 8 })
        .fontColor(this.themeOnPrimary)
        .backgroundColor(this.secondsRemaining > 0 || this.busy()
          ? $r('app.color.divider') : this.themePrimary)
        .enabled(!this.busy() && this.secondsRemaining <= 0)
        .onClick(() => {
          this.sendCode();
        })
      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
          .width('100%')
      }
      Row() {
        Checkbox({ name: 'trustDevice' })
          .select(this.trustDevice)
          .width(20)
          .height(20)
          .onChange((value: boolean) => {
            this.trustDevice = value;
          })
        Column() {
          Text('信任此设备').fontSize(14)
          Text('勾选后本设备近期登录可免短信验证')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(13)
          .fontColor($r('app.color.error'))
          .margin({ top: 8 })
          .width('100%')
      }
      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor($r('app.color.divider'))
          .fontColor($r('app.color.text_primary'))
          .enabled(!this.busy())
          .onClick(() => {
            this.controller?.close();
            ReAuthCoordinator.finishCancelled();
          })
        Button(this.submitting ? '提交中…' : '确认')
          .layoutWeight(1)
          .height(40)
          .margin({ left: 12 })
          .fontColor(this.themeOnPrimary)
          .backgroundColor(this.themePrimary)
          .enabled(!this.busy())
          .onClick(() => {
            this.submit();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
  }
}
