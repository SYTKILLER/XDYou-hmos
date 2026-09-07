import { PreferenceService } from '../../service/preference/PreferenceService';
import { ExperimentController } from '../../controller/ExperimentController';
import { ExperimentData, ExperimentTimeRange } from '../../model/experiment/ExperimentData';
import { ExperimentPasswordDialog } from '../setting/ExperimentPasswordDialog';
import { Log } from '../../utils/Log';

/**
 * 实验信息页（对应 Dart experiment_window：物理实验 + 其他实验合并展示）。
 * 按 进行中/未开始/已完成 分组（now+1 天窗口判定，对齐原版 GlobalTimer + 1.days）。
 * 未配置实验平台密码时直接拉起与设置页共用的 ExperimentPasswordDialog（页内不保留登录入口）。
 */
@Component
export struct ExperimentPage {
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @StorageProp('experimentVersion') version: number = 0;
  @StorageProp('settingsVersion') @Watch('onSettingsChanged') settingsVersion: number = 0;
  @State busy: boolean = false;
  @State errorMsg: string = '';
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ExperimentPasswordDialog(),
    autoCancel: true
  });

  private passwordConfigured(): boolean {
    return PreferenceService.getString('experimentPassword', '').length > 0;
  }

  /** 密码保存（设置页或本页对话框）后自动加载。 */
  onSettingsChanged(): void {
    if (this.passwordConfigured() && !ExperimentController.hasAnyData()) {
      this.refreshAll();
    }
  }

  aboutToAppear(): void {
    ExperimentController.loadCaches();
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
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorMsg = '';
    ExperimentController.refreshPhysics().catch((e: Object): void => {
      Log.warn(`experiment physics refresh failed: ${e}`);
    });
    ExperimentController.refreshOther().then((): void => {
      this.busy = false;
    }).catch((e: Object): void => {
      this.busy = false;
      this.errorMsg = e instanceof Error ? e.message : `${e}`;
      Log.warn(`experiment other refresh failed: ${e}`);
    });
  }

  private nowWindowMs(): number {
    return Date.now() + 86400000;
  }

  private doingList(): ExperimentData[] {
    const now: number = this.nowWindowMs();
    const list: ExperimentData[] = [];
    ExperimentController.physicsData().concat(ExperimentController.otherData())
      .forEach((e: ExperimentData): void => {
        const qualified: ExperimentTimeRange[] = e.timeRanges.filter((r: ExperimentTimeRange): boolean =>
          now > r.startMs && now < r.endMs);
        if (qualified.length > 0) {
          list.push(e);
        }
      });
    list.sort((a: ExperimentData, b: ExperimentData): number => a.firstStartMs() - b.firstStartMs());
    return list;
  }

  private notStartedList(): ExperimentData[] {
    const now: number = this.nowWindowMs();
    const list: ExperimentData[] = [];
    ExperimentController.physicsData().concat(ExperimentController.otherData())
      .forEach((e: ExperimentData): void => {
        const qualified: ExperimentTimeRange[] = e.timeRanges.filter((r: ExperimentTimeRange): boolean => now < r.startMs);
        if (qualified.length > 0) {
          list.push(e);
        }
      });
    list.sort((a: ExperimentData, b: ExperimentData): number => a.firstStartMs() - b.firstStartMs());
    return list;
  }

  private finishedList(): ExperimentData[] {
    const now: number = this.nowWindowMs();
    const list: ExperimentData[] = [];
    ExperimentController.physicsData().concat(ExperimentController.otherData())
      .forEach((e: ExperimentData): void => {
        const qualified: ExperimentTimeRange[] = e.timeRanges.filter((r: ExperimentTimeRange): boolean => now > r.endMs);
        if (qualified.length > 0) {
          list.push(e);
        }
      });
    list.sort((a: ExperimentData, b: ExperimentData): number => a.firstStartMs() - b.firstStartMs());
    return list;
  }

  private formatRange(startMs: number, endMs: number): string {
    const fmt = (ms: number): string => {
      const d: Date = new Date(ms);
      const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
      return `${d.getMonth() + 1}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
    };
    return `${fmt(startMs)} ~ ${fmt(endMs)}`;
  }

  @Builder
  SectionTitle(title: string) {
    Row({ space: 8 }) {
      Column()
        .width(4)
        .height(16)
        .borderRadius(2)
        .backgroundColor(this.themePrimary)
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 8 })
  }

  @Builder
  ExperimentCard(item: ExperimentData) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.type === 'physics') {
          Text('物理实验')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor($r('app.color.app_bg'))
        }
        if (item.score !== null && item.score.found && item.score.label.length > 0) {
          Text(`成绩 ${item.score.label}`)
            .fontSize(13)
            .fontColor(this.themePrimary)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      ForEach(item.timeRanges, (range: ExperimentTimeRange, idx: number) => {
        Text(this.formatRange(range.startMs, range.endMs))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }, (range: ExperimentTimeRange, idx: number) => `${idx}-${range.startMs}`)

      Text(`教室：${item.classroom}${item.teacher.length > 0 ? ' · ' + item.teacher : ''}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (item.reference.length > 0) {
        Text(`参考：${item.reference}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.busy && !ExperimentController.hasAnyData()) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.themePrimary)
            Text('正在加载实验信息…')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (!ExperimentController.hasAnyData()
          && ExperimentController.physicsError.length > 0 && ExperimentController.otherError.length > 0) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(44)
              .fontColor([$r('app.color.error')])
            Text(ExperimentController.physicsError)
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
                    this.dialogController.open();
                    return;
                  }
                  this.refreshAll();
                })
            }
          }
          .width('100%')
          .padding({ left: 32, right: 32 })
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              if (this.busy) {
                Text('正在刷新…')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              if (ExperimentController.physicsFromCache() || ExperimentController.otherFromCache()) {
                Text('当前为缓存数据')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              if (!this.passwordConfigured()) {
                Text('实验平台密码未配置：物理实验部分需要到「设置 → 平台账号 → 实验平台」配置')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              if (ExperimentController.physicsError.length > 0) {
                Text(`物理实验：${ExperimentController.physicsError}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              if (ExperimentController.otherError.length > 0) {
                Text(`其他实验：${ExperimentController.otherError}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }

              this.SectionTitle('进行中')
              if (this.doingList().length === 0) {
                Text('暂无进行中的实验')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ left: 4 })
              }
              ForEach(this.doingList(), (item: ExperimentData) => {
                this.ExperimentCard(item)
              }, (item: ExperimentData, idx: number) => `doing-${idx}-${item.name}`)

              this.SectionTitle('未开始')
              if (this.notStartedList().length === 0) {
                Text('暂无未开始的实验')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ left: 4 })
              }
              ForEach(this.notStartedList(), (item: ExperimentData) => {
                this.ExperimentCard(item)
              }, (item: ExperimentData, idx: number) => `undone-${idx}-${item.name}`)

              this.SectionTitle('已完成')
              if (this.finishedList().length === 0) {
                Text('暂无已完成的实验')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ left: 4 })
              }
              ForEach(this.finishedList(), (item: ExperimentData) => {
                this.ExperimentCard(item)
              }, (item: ExperimentData, idx: number) => `done-${idx}-${item.name}`)
            }
            .width('100%')
            .padding({ bottom: 24 })
          }
          .scrollable(ScrollDirection.Vertical)
          .edgeEffect(EdgeEffect.Spring)
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('实验信息')
    .backgroundColor($r('app.color.app_bg'))
  }
}
