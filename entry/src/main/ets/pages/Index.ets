import { LoginPage } from './LoginPage';
import { HomePageView } from './home/HomePageView';
import { SliderCaptchaPage } from './SliderCaptchaPage';
import { ClassTablePage } from './classtable/ClassTablePage';
import { ExamPage } from './exam/ExamPage';
import { ScorePage } from './score/ScorePage';
import { ElectricityPage } from './energy/ElectricityPage';
import { SchoolnetPage } from './schoolnet/SchoolnetPage';
import { WebViewPage } from './web/WebViewPage';
import { DormWaterPage } from './dormwater/DormWaterPage';
import { DormWaterLoginPage } from './dormwater/DormWaterLoginPage';
import { SportPage } from './sport/SportPage';
import { EmptyClassroomPage } from './classroom/EmptyClassroomPage';
import { LibraryPage } from './library/LibraryPage';
import { BookDetailPage } from './library/BookDetailPage';
import { ExperimentPage } from './experiment/ExperimentPage';
import { AppNav } from '../service/nav/AppNav';

/**
 * 应用根页面：Navigation 容器 + 登录态分流。
 * - 未登录（无保存账号）→ LoginPage；
 * - 已登录 → HomePageView（三 Tab 悬浮底栏框架：首页 / 全部功能 / 设置）；
 * - NavDestination：sliderCaptcha（滑块验证码）、classTable（课程表）、exam（考试安排）等。
 * 注意：pagesMap 必须用 if / else if 链，多个独立 if 会使 navDestination 解析失效
 * （系统路由查找失败后创建空节点，子页白屏且返回键直接退出应用，2026-09-06 模拟器实证）。
 */
@Entry
@Component
struct Index {
  pageStack: NavPathStack = new NavPathStack();
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;

  aboutToAppear(): void {
    AppNav.init(this.pageStack);
  }

  @Builder
  pagesMap(name: string) {
    if (name === 'sliderCaptcha') {
      SliderCaptchaPage()
    } else if (name === 'classTable') {
      ClassTablePage()
    } else if (name === 'exam') {
      ExamPage()
    } else if (name === 'score') {
      ScorePage()
    } else if (name === 'electricity') {
      ElectricityPage()
    } else if (name === 'schoolnet') {
      SchoolnetPage()
    } else if (name === 'dormWater') {
      DormWaterPage()
    } else if (name === 'dormWaterLogin') {
      DormWaterLoginPage()
    } else if (name === 'sport') {
      SportPage()
    } else if (name === 'emptyClassroom') {
      EmptyClassroomPage()
    } else if (name === 'library') {
      LibraryPage()
    } else if (name === 'bookDetail') {
      BookDetailPage()
    } else if (name === 'experiment') {
      ExperimentPage()
    } else if (name === 'webView') {
      WebViewPage()
    }
  }

  build() {
    Navigation(this.pageStack) {
      if (this.isLoggedIn) {
        HomePageView()
      } else {
        LoginPage()
      }
    }
    .navDestination(this.pagesMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
  }
}
