import { SchoolnetController } from '../../controller/SchoolnetController';
import { SchoolnetCaptchaHandler } from '../../service/schoolnet/SchoolnetSession';
import { CurrentUserNetInfo, GeneralNetworkUsage, IpUsageRow, formatBytes } from '../../model/schoolnet/NetworkUsage';
import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { Log } from '../../utils/Log';

/**
 * 校园网页（NavDestination，M6）：在线信息卡（rad_user_info）+ 自助服务用量卡（zfw）。
 * 未登录时内联呈现验证码图 + 输入（Promise 桥回全会话，UI 用鸿蒙组件重构、逻辑照搬 Dart）。
 * 密码未配置时提示到设置页配置。
 */
@Component
export struct SchoolnetPage {
  // 主题响应式 token（AppTheme.syncStorage 维护），build 中引用即建立刷新依赖。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  // 数据版本信号：schoolnetVersion 未在 build 中真实读取时不建立刷新依赖（2026-09-06 教训），
  // 本页数据到达经 @State 翻转驱动重渲染（同 busy 模式），version 仅作外部信号备用。
  @StorageProp('schoolnetVersion') version: number = 0;
  @State busy: boolean = false;
  @State infoLoaded: boolean = false;
  @State infoError: string = '';
  @State usageError: string = '';
  // @State 只存展示就绪的 data URL 字符串：TypedArray 不在 ArkUI @State 支持的观测类型清单内，
  // 赋值非空但首帧渲染可能读到空数组（真机 jscrash 实证）；转换在赋值处完成，build 只读字符串。
  @State captchaDataUrlStr: string = '';
  @State captchaInput: string = '';
  private captchaResolver: ((value: string) => void) | null = null;
  private refreshCaptchaFn: (() => Promise<Uint8Array>) | null = null;

  aboutToAppear(): void {
    // 缓存命中直接就绪，避免重进页面闪加载态；infoLoaded 必须被下方 if 条件读取才建立刷新依赖。
    SchoolnetController.loadCache();
    this.infoLoaded = SchoolnetController.hasUserInfo();
    this.loadUserInfo();
    this.loadUsage();
  }

  private accentColor(): ResourceColor {
    return this.themePrimary;
  }

  private loadUserInfo(): void {
    // 成功路径必须翻 @State：数据落在控制器静态字段，无状态变化则 InlineLoading 永不退出（真机实证）。
    SchoolnetController.refreshUserInfo().then((): void => {
      this.infoLoaded = true;
    }).catch((e: Object): void => {
      this.infoError = `${e}`;
      Log.warn(`schoolnet info load failed: ${e}`);
    });
  }

  private loadUsage(): void {
    this.busy = true;
    this.usageError = '';
    SchoolnetController.refreshUsage(this.captchaHandler()).then((): void => {
      this.busy = false;
    }).catch((e: Object): void => {
      this.busy = false;
      this.usageError = `${e}`;
      Log.warn(`schoolnet usage load failed: ${e}`);
    });
  }

  /** 验证码交互桥：图片字节立即转 data URL 入 @State，确认/取消经唯一 resolve 返回。 */
  private captchaHandler(): SchoolnetCaptchaHandler {
    return (imageBytes: Uint8Array, refresh: () => Promise<Uint8Array>): Promise<string> => {
      return new Promise<string>((resolver: (value: string) => void) => {
        this.captchaInput = '';
        this.refreshCaptchaFn = refresh;
        this.captchaResolver = resolver;
        this.showCaptcha(imageBytes);
      });
    };
  }

  private showCaptcha(imageBytes: Uint8Array): void {
    if (imageBytes.length === 0) {
      this.abortCaptcha();
      return;
    }
    this.captchaDataUrlStr = this.toDataUrl(imageBytes);
  }

  private toDataUrl(bytes: Uint8Array): string {
    const b64: string = CryptoUtil.base64Encode(bytes);
    const isPng: boolean = bytes.length > 4 && bytes[0] === 0x89 && bytes[1] === 0x50;
    return `data:image/${isPng ? 'png' : 'jpeg'};base64,${b64}`;
  }

  private confirmCaptcha(): void {
    const code: string = this.captchaInput.trim();
    const resolver = this.captchaResolver;
    this.captchaResolver = null;
    this.captchaDataUrlStr = '';
    this.refreshCaptchaFn = null;
    if (resolver !== null) {
      resolver(code);
    }
  }

  private cancelCaptcha(): void {
    this.abortCaptcha();
  }

  /** 放弃验证码（清 UI 并以空串回全会话，会话层按验证码失败处理）。 */
  private abortCaptcha(): void {
    const resolver = this.captchaResolver;
    this.captchaResolver = null;
    this.captchaDataUrlStr = '';
    this.refreshCaptchaFn = null;
    if (resolver !== null) {
      resolver('');
    }
  }

  private changeCaptcha(): void {
    const refresh = this.refreshCaptchaFn;
    if (refresh === null) {
      return;
    }
    refresh().then((bytes: Uint8Array): void => {
      this.showCaptcha(bytes);
    }).catch((e: Object): void => {
      Log.warn(`captcha refresh failed: ${e}`);
    });
  }

  private passwordMissing(): boolean {
    return this.usageError.includes('未配置校园网查询密码');
  }

  private userInfo(): CurrentUserNetInfo | null {
    return SchoolnetController.userInfoData();
  }

  private usage(): GeneralNetworkUsage | null {
    return SchoolnetController.usageData();
  }

  /** 本周期已用百分比（sumBytes/(sum+remain)，原版 CurrentNetInfoPage 同口径）。 */
  private usedPercent(): number {
    const info: CurrentUserNetInfo | null = this.userInfo();
    if (info === null) {
      return 0;
    }
    const total: number = info.periodTotalBytes();
    return total > 0 ? info.sumBytes / total * 100 : 0;
  }

  private progressValue(): number {
    const p: number = this.usedPercent();
    return Math.min(100, Math.max(0, p));
  }

  private percentText(): string {
    return this.usedPercent().toFixed(1);
  }

  private balanceText(): string {
    const info: CurrentUserNetInfo | null = this.userInfo();
    return info === null ? '—' : `¥${info.userBalance.toFixed(2)}`;
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          this.UserInfoSection()

          this.UsageSection()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .title($r('app.string.schoolnet_title'))
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  UserInfoSection() {
    Text($r('app.string.schoolnet_online_section'))
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4, top: 8, bottom: 8 })

    // infoLoaded 必须参与本 if 链条件：ArkUI 只重渲染读取了变化状态的节点，
    // 控制器静态字段无人观测，翻转状态是数据到达后走出加载态的唯一触发（真机两轮实证）。
    if (this.infoLoaded && SchoolnetController.hasUserInfo() && this.userInfo() !== null) {
      // 原版 CurrentNetInfoPage 不校验 error 字段、有数据即渲染（error≠ok 时接口仍返回完整账号信息，
      // 真机实证），仅在连账号都没有时按离线呈现。
      if ((this.userInfo() as CurrentUserNetInfo).userName.length === 0) {
        Text($r('app.string.schoolnet_offline'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor($r('app.color.app_card'))
      } else {
        Text($r('app.string.schoolnet_current_notice'))
          .fontSize(12)
          .fontColor($r('app.color.warning_text'))
          .width('100%')
          .padding(12)
          .borderRadius(12)
          .backgroundColor($r('app.color.warning_bg'))
          .border({ width: 1, color: $r('app.color.warning_border') })

        // 账户概览（原版 current_login_net.overview：账号/套餐类型/余额）
        Column({ space: 10 }) {
          Text($r('app.string.schoolnet_overview'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          this.InfoRow($r('app.string.schoolnet_account'), (this.userInfo() as CurrentUserNetInfo).userName)
          if ((this.userInfo() as CurrentUserNetInfo).productsName.length > 0) {
            this.InfoRow($r('app.string.schoolnet_product'), (this.userInfo() as CurrentUserNetInfo).productsName)
          }
          this.InfoRow($r('app.string.schoolnet_balance'), this.balanceText())
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8 })

        // 流量使用情况（原版 current_login_net.usage_situation：进度条 + 已用/剩余/总流量）
        Column({ space: 12 }) {
          Text($r('app.string.schoolnet_usage_situation'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Progress({ value: this.progressValue(), total: 100, type: ProgressType.Linear })
            .color(this.accentColor())
            .width('100%')
          Row() {
            Blank()
            Text($r('app.string.schoolnet_used'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(` ${this.percentText()}%`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          this.InfoRow($r('app.string.schoolnet_used_traffic'),
            formatBytes((this.userInfo() as CurrentUserNetInfo).sumBytes))
          this.InfoRow($r('app.string.schoolnet_remain'),
            formatBytes((this.userInfo() as CurrentUserNetInfo).remainBytes))
          this.InfoRow($r('app.string.schoolnet_total_traffic'),
            formatBytes((this.userInfo() as CurrentUserNetInfo).periodTotalBytes()))
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8 })
      }
    } else if (this.infoError.length > 0) {
      Text(this.infoError)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
    } else {
      this.InlineLoading()
    }
  }

  @Builder
  InfoRow(label: Resource, value: string) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value.length > 0 ? value : '—')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.End)
    }
    .width('100%')
  }

  @Builder
  InlineLoading() {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color(this.accentColor())
      Text($r('app.string.schoolnet_loading'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
  }

  @Builder
  UsageSection() {
    Text($r('app.string.schoolnet_usage_section'))
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4, top: 24, bottom: 8 })

    // 验证码登录区（会话需要登录时内联呈现）
    if (this.captchaDataUrlStr.length > 0) {
      Column({ space: 12 }) {
        Text($r('app.string.schoolnet_login_section'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Image(this.captchaDataUrlStr)
          .width(150)
          .height(48)
          .borderRadius(8)
          .objectFit(ImageFit.Contain)
          .backgroundColor($r('app.color.app_bg'))
        TextInput({ text: this.captchaInput, placeholder: $r('app.string.schoolnet_captcha_hint') })
          .height(50)
          .borderRadius(12)
          .fontSize(15)
          .width('100%')
          .onChange((value: string) => {
            this.captchaInput = value;
          })
        Row({ space: 12 }) {
          Button($r('app.string.schoolnet_captcha_refresh'))
            .layoutWeight(1)
            .height(50)
            .borderRadius(12)
            .fontSize(15)
            .backgroundColor($r('app.color.app_bg'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.changeCaptcha())
          Button($r('app.string.common_cancel'))
            .layoutWeight(1)
            .height(50)
            .borderRadius(12)
            .fontSize(15)
            .backgroundColor($r('app.color.app_bg'))
            .fontColor($r('app.color.text_primary'))
            .onClick(() => this.cancelCaptcha())
          Button($r('app.string.common_confirm'))
            .layoutWeight(1)
            .height(50)
            .borderRadius(12)
            .fontSize(15)
            .backgroundColor(this.themePrimary)
            .fontColor(this.themeOnPrimary)
            .onClick(() => this.confirmCaptcha())
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('app.color.app_card'))
      .alignItems(HorizontalAlign.Start)
    } else if (this.busy && !SchoolnetController.hasUsage()) {
      this.InlineLoading()
    } else if (this.usageError.length > 0) {
      Column({ space: 12 }) {
        Text(this.usageError)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        if (this.passwordMissing()) {
          Text($r('app.string.schoolnet_password_missing'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        Button($r('app.string.common_retry'))
          .width(120)
          .height(50)
          .borderRadius(12)
          .fontSize(15)
          .onClick(() => this.loadUsage())
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('app.color.app_card'))
      .alignItems(HorizontalAlign.Start)
    } else if (SchoolnetController.hasUsage() && this.usage() !== null) {
      Column({ space: 12 }) {
        if (SchoolnetController.isUsageFromCache() && SchoolnetController.usageFetchTime() > 0) {
          Text($r('app.string.schoolnet_cache_hint'))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        Row() {
          this.UsageCell($r('app.string.schoolnet_used'), (this.usage() as GeneralNetworkUsage).used)
          this.UsageCell($r('app.string.schoolnet_rest'), (this.usage() as GeneralNetworkUsage).rest)
          this.UsageCell($r('app.string.schoolnet_charged'), (this.usage() as GeneralNetworkUsage).charged)
        }
        .width('100%')

        if ((this.usage() as GeneralNetworkUsage).ipList.length > 0) {
          Divider()
            .color($r('app.color.divider'))
            .width('100%')
          Text($r('app.string.schoolnet_devices'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          ForEach((this.usage() as GeneralNetworkUsage).ipList, (row: IpUsageRow) => {
            Row({ space: 8 }) {
              Text(row.ip)
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(row.onlineTime)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
              Text(row.used)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }, (row: IpUsageRow) => `ip-${row.ip}-${row.used}`)
        }
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('app.color.app_card'))
      .alignItems(HorizontalAlign.Start)
    } else {
      Text($r('app.string.schoolnet_usage_empty'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))
    }
  }

  @Builder
  UsageCell(label: Resource, value: string) {
    Column({ space: 4 }) {
      Text(value.length > 0 ? value : '—')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}
