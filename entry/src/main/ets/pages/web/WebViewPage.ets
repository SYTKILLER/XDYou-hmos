import { webview } from '@kit.ArkWeb';
import { Log } from '../../utils/Log';

/**
 * 全部功能页 → WebViewPage 的跳转参数（pushPath param，显式类避免 any/字面量解析）。
 */
export class WebNavParam {
  title: string = '';
  url: string = '';
}

/**
 * 通用网页页（NavDestination）：对应原 Flutter 工具箱中仅跳转网址的功能
 * （缴费系统 / 订水系统 / 后勤报修 / 空间预约 / 网络查询 / 物理计算 / 睿思导航）。
 * 原版经 url_launcher 拉起外部浏览器，此处改为 ArkWeb 应用内加载；
 * 标题与网址由全部功能页经 pushPath param 传入，onReady 时取用。
 * 返回键优先回退网页历史（accessBackward），无历史才退出页面。
 */
@Component
export struct WebViewPage {
  // 主题响应式 token（AppTheme.syncStorage 维护），build 中引用即建立刷新依赖。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State pageTitle: string = '';
  @State pageUrl: string = '';
  @State loadProgress: number = 0;
  @State errorInfo: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  private accentColor(): ResourceColor {
    return this.themePrimary;
  }

  private reload(): void {
    this.errorInfo = '';
    try {
      this.controller.refresh();
    } catch (e) {
      Log.warn(`web reload failed: ${e}`);
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Web({ src: this.pageUrl, controller: this.controller })
          .zoomAccess(true)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .darkMode(WebDarkMode.Auto)
          .width('100%')
          .height('100%')
          .onProgressChange((event: OnProgressChangeEvent) => {
            this.loadProgress = event.newProgress;
          })
          .onPageEnd((event: OnPageEndEvent) => {
            this.loadProgress = 100;
            Log.info(`web page loaded: ${event.url}`);
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            // 仅主框架加载失败时呈现错误态，子资源失败不打断页面。
            if (event.request.isMainFrame() && this.errorInfo.length === 0) {
              this.loadProgress = 100;
              this.errorInfo = event.error.getErrorInfo();
              Log.warn(`web page load failed (${event.error.getErrorCode()}): ${this.errorInfo}`);
            }
          })

        if (this.loadProgress > 0 && this.loadProgress < 100) {
          Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color(this.accentColor())
        }

        if (this.errorInfo.length > 0) {
          Column() {
            this.ErrorView()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.pageTitle.length > 0 ? this.pageTitle : '网页')
    .backgroundColor($r('app.color.app_bg'))
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as WebNavParam;
      if (param !== null && param !== undefined && param.url.length > 0) {
        this.pageTitle = param.title;
        this.pageUrl = param.url;
      }
    })
    .onBackPressed((): boolean => {
      try {
        if (this.controller.accessBackward()) {
          this.controller.backward();
          return true;
        }
      } catch (e) {
        Log.warn(`web accessBackward failed: ${e}`);
      }
      return false;
    })
  }

  @Builder
  ErrorView() {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.wifi_badge_exclamationmark'))
        .fontSize(48)
        .fontColor([$r('app.color.text_secondary')])
      Text('网页加载失败')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(this.errorInfo)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Button('重新加载')
        .width('60%')
        .height(50)
        .borderRadius(12)
        .backgroundColor(this.accentColor())
        .fontColor(this.themeOnPrimary)
        .onClick(() => {
          this.reload();
        })
    }
    .width('80%')
    .padding(24)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Center)
  }
}
