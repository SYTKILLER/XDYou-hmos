import { ScoreController, ScoreSummary } from '../../controller/ScoreController';
import { Score } from '../../model/score/ScoreData';
import { ScoreDetailDialog } from './ScoreDetailDialog';
import { Log } from '../../utils/Log';

/**
 * 成绩查询页（NavDestination，M6）：汇总卡（学分/平均分/绩点，排除规则照搬原版）
 * + 学期筛选 + 成绩列表（不及格标红）+ 点击查看单科成绩组成。
 * 勾选课程自定义统计（isSelected 模式）后置迭代。
 */
@Component
export struct ScorePage {
  // 主题响应式 token（AppTheme.syncStorage 维护）；在 build 中经 accentColor 读取即建立刷新依赖。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('scoreVersion') version: number = 0;
  @State busy: boolean = false;
  @State errorMsg: string = '';
  @State semesterIndex: number = 0;
  // DEBUG 实验：延迟创建 dialog，验证成员初始化器创建 CustomDialogController 是否导致页面白屏
  private dialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    ScoreController.loadCache();
    this.refresh();
  }

  private refresh(): void {
    this.busy = true;
    this.errorMsg = '';
    ScoreController.refresh().then((): void => {
      this.busy = false;
    }).catch((e: Object): void => {
      this.busy = false;
      this.errorMsg = `${e}`;
      Log.error(`score refresh failed: ${e}`);
    });
  }

  private accentColor(): ResourceColor {
    return this.themePrimary;
  }

  private semesterOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部学期' }];
    ScoreController.semesters().forEach((semester: string): void => {
      options.push({ value: semester });
    });
    return options;
  }

  /** Select 按钮文本：selected 只定菜单高亮，按钮文字必须用 value 提供（越界回退"全部学期"，不允许空文本）。 */
  private semesterLabel(): string {
    const options: SelectOption[] = this.semesterOptions();
    const index: number = this.semesterIndex >= 0 && this.semesterIndex < options.length ? this.semesterIndex : 0;
    const v: string | Resource = options[index].value;
    return typeof v === 'string' ? v : '全部学期';
  }

  private chosenSemester(): string {
    if (this.semesterIndex === 0) {
      return '';
    }
    const semesters: string[] = ScoreController.semesters();
    return this.semesterIndex - 1 < semesters.length ? semesters[this.semesterIndex - 1] : '';
  }

  private filtered(): Score[] {
    const chosen: string = this.chosenSemester();
    const all: Score[] = ScoreController.data();
    if (chosen.length === 0) {
      return all;
    }
    return all.filter((s: Score): boolean => s.semesterCode === chosen);
  }

  private summary(): ScoreSummary {
    return ScoreController.summary();
  }

  private scoreColor(s: Score): ResourceColor {
    if (s.isFinish() && s.isPassed() === false) {
      return $r('app.color.error');
    }
    if (s.scoreStr() === '暂无' || s.scoreStr() === '暂无但及格' || s.scoreStr() === '暂无但未及格') {
      return $r('app.color.text_secondary');
    }
    return $r('app.color.text_primary');
  }

  private onScoreClick(s: Score): void {
    if (s.classID.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '该课程暂无组成明细' });
      return;
    }
    ScoreController.detailTarget = s;
    if (this.dialogController === null) {
      this.dialogController = new CustomDialogController({
        builder: ScoreDetailDialog(),
        autoCancel: true
      });
    }
    this.dialogController.open();
  }

  build() {
    NavDestination() {
      Column() {
        if (this.errorMsg.length > 0 && !ScoreController.hasData()) {
          Column({ space: 16 }) {
            Text(this.errorMsg)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
            Button($r('app.string.common_retry'))
              .width(120)
              .height(40)
              .borderRadius(12)
              .fontSize(15)
              .onClick(() => this.refresh())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (!ScoreController.hasData() && this.busy) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.accentColor())
            Text($r('app.string.score_loading'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              // 汇总卡
              Row() {
                this.SummaryCell(`${this.summary().credit.toFixed(2)}`, $r('app.string.score_credit'))
                this.SummaryCell(`${this.summary().avg.toFixed(2)}`, $r('app.string.score_avg'))
                this.SummaryCell(`${this.summary().gpa.toFixed(2)}`, $r('app.string.score_gpa'))
              }
              .width('100%')
              .padding({ top: 16, bottom: 16 })
              .borderRadius(16)
              .backgroundColor($r('app.color.app_card'))

              if (ScoreController.isFromCache() && ScoreController.fetchTime() > 0) {
                Text($r('app.string.score_cache_hint'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ left: 4, top: 8 })
              }

              if (this.busy && ScoreController.hasData()) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color(this.accentColor())
                  Text($r('app.string.common_refreshing'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding({ left: 4, top: 4 })
              }

              // 学期筛选
              Row({ space: 8 }) {
                Text($r('app.string.score_filter_semester'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Select(this.semesterOptions())
                  .selected(this.semesterIndex)
                  .value(this.semesterLabel())
                  .font({ size: 14 })
                  .onSelect((index: number): void => {
                    this.semesterIndex = index;
                  })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })

              if (this.filtered().length === 0) {
                Text($r('app.string.score_empty_hint'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 80 })
              } else {
                Column({ space: 8 }) {
                  ForEach(this.filtered(), (s: Score) => {
                    Row({ space: 12 }) {
                      Column({ space: 4 }) {
                        Text(s.name)
                          .fontSize(15)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(`${s.semesterCode} · ${s.credit}学分 · ${s.classStatus}`)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text(s.scoreStr())
                        .fontSize(18)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.scoreColor(s))
                    }
                    .width('100%')
                    .padding(14)
                    .borderRadius(14)
                    .backgroundColor($r('app.color.app_card'))
                    .alignItems(VerticalAlign.Center)
                    .onClick(() => this.onScoreClick(s))
                  }, (s: Score) => `${s.mark}-${s.name}-${s.semesterCode}`)
                }
                .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16, bottom: 32 })
          }
          .scrollable(ScrollDirection.Vertical)
          .edgeEffect(EdgeEffect.Spring)
          .width('100%')
          .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_bg'))
    }
    .title($r('app.string.score_title'))
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  SummaryCell(value: string, label: Resource) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}
