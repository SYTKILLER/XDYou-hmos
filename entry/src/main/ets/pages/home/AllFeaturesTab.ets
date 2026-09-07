import { TAB_BAR_CLEARANCE } from './HomeLayout';
import { AppNav } from '../../service/nav/AppNav';
import { WebNavParam } from '../web/WebViewPage';

/**
 * 全部功能页签：入口注册表 Grid，只展示已移植功能。
 * 后续里程碑完成后向 FEATURE_ENTRIES 追加条目即可出现在宫格中。
 * 纯网址跳转功能（原工具箱 url_launcher 项）url 非空，推入 webView 通用页应用内加载。
 */
interface FeatureEntry {
  icon: Resource;
  title: string;
  /** NavDestination 名称（Index.pagesMap 注册）。 */
  destination: string;
  /** 非空表示纯网址跳转功能，此串即目标网页地址。 */
  url: string;
}

const FEATURE_ENTRIES: FeatureEntry[] = [
  { icon: $r('sys.symbol.graduationcap_fill'), title: '课程表', destination: 'classTable', url: '' },
  { icon: $r('sys.symbol.doc_text_badge_clock'), title: '考试安排', destination: 'exam', url: '' },
  { icon: $r('sys.symbol.doc_plaintext'), title: '成绩查询', destination: 'score', url: '' },
  { icon: $r('sys.symbol.bolt'), title: '电费查询', destination: 'electricity', url: '' },
  { icon: $r('sys.symbol.dot_radiowaves_left_and_right'), title: '校园网', destination: 'schoolnet', url: '' },
  {
    icon: $r('sys.symbol.creditcard'), title: '缴费系统', destination: 'webView',
    url: 'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600&state=1231231231'
  },
  {
    icon: $r('sys.symbol.drop'), title: '订水系统', destination: 'webView',
    url: 'https://order.xidian.edu.cn/mobile/thirdoauth/oauth2Xidian/1'
  },
  { icon: $r('sys.symbol.cup_fill'), title: '宿舍水机', destination: 'dormWater', url: '' },
  { icon: $r('sys.symbol.figure_run'), title: '体育信息', destination: 'sport', url: '' },
  { icon: $r('sys.symbol.school'), title: '空闲教室', destination: 'emptyClassroom', url: '' },
  { icon: $r('sys.symbol.text_book_closed'), title: '图书馆', destination: 'library', url: '' },
  { icon: $r('sys.symbol.laboratories'), title: '实验信息', destination: 'experiment', url: '' },
  {
    icon: $r('sys.symbol.wrench_and_screwdriver'), title: '后勤报修', destination: 'webView',
    url: 'https://ids.xidian.edu.cn/authserver/login?service=https%3A%2F%2Fids.xidian.edu.cn%2Fauthserver%2Foauth2.0%2FcallbackAuthorize%3Fclient_id%3D869608421533880320%26redirect_uri%3Dhttp%253A%252F%252Frepair.xidian.edu.cn%252Fappsys%252FxidianCasLogin%252FoauthLogin%26response_type%3Dcode%26state%3Dhome%26client_name%3DCasOAuthClient'
  },
  {
    icon: $r('sys.symbol.building'), title: '空间预约', destination: 'webView',
    url: 'http://libspace.xidian.edu.cn'
  },
  {
    icon: $r('sys.symbol.wifi'), title: '网络查询', destination: 'webView',
    url: 'https://zfw.xidian.edu.cn'
  },
  {
    icon: $r('sys.symbol.calculator'), title: '物理计算', destination: 'webView',
    url: 'https://experiment-helper.wizzstudio.com/#/'
  },
  {
    icon: $r('sys.symbol.compass'), title: '睿思导航', destination: 'webView',
    url: 'https://nav.xdruisi.cn/'
  }
];

@Component
export struct AllFeaturesTab {
  // 主题响应式 token（AppTheme.syncStorage 维护）；在 build 中经 accentColor 读取即建立刷新依赖。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';

  private accentColor(): ResourceColor {
    return this.themePrimary;
  }

  private openEntry(entry: FeatureEntry): void {
    const stack: NavPathStack | null = AppNav.stackOrNull();
    if (stack === null) {
      return;
    }
    if (entry.url.length > 0) {
      const param = new WebNavParam();
      param.title = entry.title;
      param.url = entry.url;
      stack.pushPath({ name: entry.destination, param: param });
    } else {
      stack.pushPath({ name: entry.destination });
    }
  }

  @Builder
  FeatureCell(entry: FeatureEntry) {
    Column({ space: 8 }) {
      SymbolGlyph(entry.icon)
        .fontSize(28)
        .fontColor([this.accentColor()])
      Text(entry.title)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .onClick(() => {
      this.openEntry(entry);
    })
  }

  @Builder
  EmptyState() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.hourglass'))
        .fontSize(48)
        .fontColor([$r('app.color.text_secondary')])
      Text($r('app.string.features_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text($r('app.string.features_empty_subtitle'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      Text($r('app.string.tab_features'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))

      if (FEATURE_ENTRIES.length === 0) {
        this.EmptyState()
      } else {
        Scroll() {
          Grid() {
            ForEach(FEATURE_ENTRIES, (entry: FeatureEntry) => {
              GridItem() {
                this.FeatureCell(entry)
              }
            }, (entry: FeatureEntry) => entry.title)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .width('100%')
          .padding({ top: 24, bottom: TAB_BAR_CLEARANCE })
        }
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 16 })
    .backgroundColor($r('app.color.app_bg'))
  }
}
