import { PreferenceService } from '../../service/preference/PreferenceService';
import { SportController } from '../../controller/SportController';
import { SportClassItem, SportItems, SportScore, SportScoreOfYear } from '../../model/sport/SportModels';
import { SportPasswordDialog } from '../setting/SportPasswordDialog';
import { Log } from '../../utils/Log';

/**
 * 体育信息页（对应 Dart sport_window 双页签：体测成绩 + 体育课成绩）。
 * 未配置体育平台密码时不保留登录入口，直接拉起与设置页共用的 SportPasswordDialog，
 * 保存后自动加载；打卡记录子功能原版已废弃不移植。
 */
@Component
export struct SportPage {
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @StorageProp('sportVersion') version: number = 0;
  @StorageProp('settingsVersion') @Watch('onSettingsChanged') settingsVersion: number = 0;
  @State scoreBusy: boolean = false;
  @State scoreError: string = '';
  @State classBusy: boolean = false;
  @State classError: string = '';
  @State expandedYear: number = -1;
  private tabController: TabsController = new TabsController();
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: SportPasswordDialog(),
    autoCancel: true
  });

  /** 密码保存（设置页或本页对话框）后自动加载。 */
  onSettingsChanged(): void {
    if (!this.passwordConfigured()) {
      return;
    }
    if (!SportController.hasScore() && !this.scoreBusy) {
      this.loadScore();
    }
    if (!SportController.hasClass() && !this.classBusy) {
      this.loadClass();
    }
  }

  private passwordConfigured(): boolean {
    return PreferenceService.getString('sportPassword', '').length > 0;
  }

  aboutToAppear(): void {
    if (!this.passwordConfigured()) {
      this.dialogController.open();
      return;
    }
    this.refreshAll();
  }

  private refreshAll(): void {
    if (!this.passwordConfigured()) {
      return;
    }
    this.loadScore();
    this.loadClass();
  }

  private loadScore(): void {
    if (this.scoreBusy) {
      return;
    }
    this.scoreBusy = true;
    this.scoreError = '';
    SportController.refreshScore().then((): void => {
      this.scoreBusy = false;
    }).catch((e: Object): void => {
      this.scoreBusy = false;
      this.scoreError = e instanceof Error ? e.message : `${e}`;
      Log.warn(`sport score load failed: ${e}`);
    });
  }

  private loadClass(): void {
    if (this.classBusy) {
      return;
    }
    this.classBusy = true;
    this.classError = '';
    SportController.refreshClass().then((): void => {
      this.classBusy = false;
    }).catch((e: Object): void => {
      this.classBusy = false;
      this.classError = e instanceof Error ? e.message : `${e}`;
      Log.warn(`sport class load failed: ${e}`);
    });
  }

  private openPasswordDialog(): void {
    this.dialogController.open();
  }

  @Builder
  ErrorView(message: string, isClassTab: boolean) {
    Column({ space: 16 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(44)
        .fontColor([$r('app.color.error')])
      Text(message)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Row({ space: 12 }) {
        Button('重试')
          .height(44)
          .borderRadius(12)
          .fontSize(15)
          .backgroundColor(this.themePrimary)
          .fontColor(this.themeOnPrimary)
          .onClick(() => {
            if (!this.passwordConfigured()) {
              this.openPasswordDialog();
              return;
            }
            if (isClassTab) {
              this.loadClass();
            } else {
              this.loadScore();
            }
          })
      }
    }
    .width('100%')
    .padding({ left: 32, right: 32, top: 64 })
  }

  @Builder
  CacheHint() {
    Text('当前为缓存数据')
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
  }

  @Builder
  YearCard(item: SportScoreOfYear, index: number) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(item.year)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`总分 ${item.totalScore}`)
          .fontSize(13)
          .fontColor(this.themePrimary)
        SymbolGlyph(this.expandedYear === index ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.expandedYear = this.expandedYear === index ? -1 : index;
      })

      Text(`等级 ${item.rank}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (item.moreinfo.length > 0) {
        Text(item.moreinfo)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      if (this.expandedYear === index) {
        if (item.details.length === 0) {
          Text('暂无明细数据')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        } else {
          ForEach(item.details, (d: SportItems) => {
            Row({ space: 8 }) {
              Text(d.examName)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(d.examunit)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Text(`${d.actualScore} 分`)
                .fontSize(13)
                .fontColor(this.themePrimary)
              Text(d.rank)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding({ top: 6, bottom: 6 })
            .alignItems(VerticalAlign.Center)
          }, (d: SportItems, idx: number) => `${index}-${idx}-${d.examName}`)
        }
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ScoreView() {
    if (this.scoreBusy && SportController.score() === null) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(this.themePrimary)
        Text('正在加载体测成绩…')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ top: 64 })
    } else if (this.scoreError.length > 0 && SportController.score() === null) {
      this.ErrorView(this.scoreError, false)
    } else {
      Scroll() {
        Column({ space: 12 }) {
          if (this.scoreBusy) {
            Text('正在刷新…')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          if (SportController.scoreIsCache()) {
            this.CacheHint()
          }
          if (this.scoreError.length > 0) {
            Text(`刷新失败：${this.scoreError}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }

          Column({ space: 8 }) {
            Text('体测总览')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Row({ space: 16 }) {
              Column({ space: 4 }) {
                Text(SportController.score() !== null ? (SportController.score() as SportScore).total : '0.0')
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.themePrimary)
                Text('总分')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 4 }) {
                Text(SportController.score() !== null ? (SportController.score() as SportScore).detail : '')
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('等级')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 4 }) {
                Text(SportController.score() !== null ? (SportController.score() as SportScore).rank : '')
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('排名')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor($r('app.color.app_card'))
          .alignItems(HorizontalAlign.Start)

          ForEach(SportController.score() !== null ? (SportController.score() as SportScore).list : [],
            (item: SportScoreOfYear, index: number) => {
              this.YearCard(item, index)
            }, (item: SportScoreOfYear) => `${item.year}-${item.totalScore}`)
        }
        .width('100%')
      }
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
  }

  @Builder
  ClassView() {
    if (this.classBusy && !SportController.hasClass()) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(this.themePrimary)
        Text('正在加载体育课成绩…')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ top: 64 })
    } else if (this.classError.length > 0 && !SportController.hasClass()) {
      this.ErrorView(this.classError, true)
    } else {
      Scroll() {
        Column({ space: 12 }) {
          if (this.classBusy) {
            Text('正在刷新…')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          if (SportController.classIsCache()) {
            this.CacheHint()
          }
          if (this.classError.length > 0) {
            Text(`刷新失败：${this.classError}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          if (SportController.classData().length === 0) {
            Text('暂无体育课成绩')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .padding({ top: 64 })
              .textAlign(TextAlign.Center)
          }
          ForEach(SportController.classData(), (item: SportClassItem) => {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Text(item.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Text(`成绩 ${item.score}`)
                  .fontSize(13)
                  .fontColor(this.themePrimary)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

            Text(item.termToShow)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(`${item.teacher} · 星期${'一二三四五六日'.charAt(item.week - 1)} 第${item.start}-${item.stop}节 · ${item.place}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .padding(14)
            .borderRadius(14)
            .backgroundColor($r('app.color.app_card'))
            .alignItems(HorizontalAlign.Start)
          }, (item: SportClassItem, idx: number) => `${idx}-${item.term}-${item.name}`)
        }
        .width('100%')
      }
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
    }
  }

  build() {
    NavDestination() {
      Column() {
        Tabs({ barPosition: BarPosition.Start, controller: this.tabController }) {
          TabContent() {
            this.ScoreView()
          }
          .tabBar(this.tabTitle('体测成绩', 0))

          TabContent() {
            this.ClassView()
          }
          .tabBar(this.tabTitle('体育课成绩', 1))
        }
        .barPosition(BarPosition.Start)
        .onChange((index: number) => {
          if (index === 1 && !SportController.hasClass() && !this.classBusy && this.passwordConfigured()) {
            this.loadClass();
          }
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('体育信息')
    .backgroundColor($r('app.color.app_bg'))
  }

  private tabTitle(label: string, index: number): SubTabBarStyle {
    return SubTabBarStyle.of(label);
  }
}
