import { ExamController } from '../../controller/ExamController';
import { Subject, ToBeArranged } from '../../model/exam/ExamData';
import { Log } from '../../utils/Log';

/**
 * 考试安排页（NavDestination，M3）：分组卡片列表。
 * 分组：未开考（升序，最近一场倒计时高亮）→ 已结束 → 时间待定（解析失败）→ 待安排课程。
 * 与原版 Timeline 三段语义一致，UI 按鸿蒙列表卡片重设计。
 */
@Component
export struct ExamPage {
  // 主题响应式 token（AppTheme.syncStorage 维护），最近一场高亮色随种子色/深浅色刷新。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themePrimaryContainer') themePrimaryContainer: string = '#D0E4FF';
  @StorageProp('examVersion') version: number = 0;
  @State busy: boolean = false;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    ExamController.loadCache();
    this.refresh();
  }

  private refresh(): void {
    this.busy = true;
    this.errorMsg = '';
    ExamController.refresh().then((): void => {
      this.busy = false;
    }).catch((e: Object): void => {
      this.busy = false;
      this.errorMsg = `${e}`;
      Log.error(`exam refresh failed: ${e}`);
    });
  }

  /** "MM-dd HH:mm"，来自 "yyyy-MM-dd HH:mm:ss" 截取。 */
  private static shortTime(full: string): string {
    return full.length >= 16 ? full.substring(5, 16) : full;
  }

  private timeRangeOf(s: Subject): string {
    if (s.startTime() === null) {
      return s.time;
    }
    const start: string = ExamPage.shortTime(s.startTimeStr);
    const stop: string = ExamPage.shortTime(s.endTimeStr);
    if (start.substring(0, 5) === stop.substring(0, 5)) {
      return `${start} ~ ${stop.substring(6)}`;
    }
    return `${start} ~ ${stop}`;
  }

  /** 最近一场倒计时文案。 */
  private countdownOf(s: Subject): string {
    const start: Date | null = s.startTime();
    if (start === null) {
      return '';
    }
    const diff: number = start.getTime() - Date.now();
    const days: number = Math.floor(diff / 86400000);
    const hours: number = Math.floor((diff % 86400000) / 3600000);
    if (days > 0) {
      return `${days}天${hours}小时后`;
    }
    return `${hours}小时后`;
  }

  @Builder
  GroupHeader(title: string, count: number) {
    Text(`${title} · ${count}`)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4, top: 8, bottom: 8 })
  }

  @Builder
  ExamCard(s: Subject, highlight: boolean) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(s.subject)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (s.type().length > 0) {
            Text(s.type())
              .fontSize(11)
              .fontColor(this.themePrimary)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(this.themePrimaryContainer)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.timeRangeOf(s))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
        Text(s.place === s.seat || s.seat.length === 0 ? s.place : `${s.place} · 座位 ${s.seat}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (highlight) {
        Text(this.countdownOf(s))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themePrimary)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .border({ width: highlight ? 1.5 : 0, color: this.themePrimary })
  }

  @Builder
  InvalidCard(s: Subject) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(s.subject)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(s.type())
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(`${s.time} · ${s.place}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .opacity(0.8)
  }

  @Builder
  TbaCard(t: ToBeArranged) {
    Text(`${t.subject}（考试时间待安排）`)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding(14)
      .borderRadius(12)
      .backgroundColor($r('app.color.app_card'))
  }

  @Builder
  Body() {
    Scroll() {
      Column() {
        if (ExamController.isFromCache() && ExamController.fetchTime() > 0) {
          Text($r('app.string.exam_cache_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 4, bottom: 8 })
        }

        if (this.busy && ExamController.hasData()) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(this.themePrimary)
            Text($r('app.string.common_refreshing'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .padding({ left: 4, bottom: 8 })
        }

        // 未开考（升序，最近一场高亮）
        if (ExamController.isNotFinished(new Date()).length > 0) {
          this.GroupHeader('未开考', ExamController.isNotFinished(new Date()).length)
          Column({ space: 12 }) {
            ForEach(ExamController.isNotFinished(new Date()), (s: Subject, idx: number) => {
              this.ExamCard(s, idx === 0)
            }, (s: Subject) => `upcoming-${s.subject}-${s.startTimeStr}`)
          }
          .width('100%')
        }

        // 已结束（含进行中）
        if (ExamController.isFinished(new Date()).length > 0) {
          this.GroupHeader('已结束', ExamController.isFinished(new Date()).length)
          Column({ space: 12 }) {
            ForEach(ExamController.isFinished(new Date()), (s: Subject) => {
              this.ExamCard(s, false)
            }, (s: Subject) => `finished-${s.subject}-${s.startTimeStr}`)
          }
          .width('100%')
          .opacity(0.75)
        }

        // 时间待定（解析失败，对应 Dart isDisQualified）
        if (ExamController.isDisQualified().length > 0) {
          this.GroupHeader('时间待定', ExamController.isDisQualified().length)
          Column({ space: 12 }) {
            ForEach(ExamController.isDisQualified(), (s: Subject) => {
              this.InvalidCard(s)
            }, (s: Subject) => `invalid-${s.subject}-${s.time}`)
          }
          .width('100%')
        }

        // 待安排
        if (ExamController.toBeArranged().length > 0) {
          this.GroupHeader('待安排', ExamController.toBeArranged().length)
          Column({ space: 12 }) {
            ForEach(ExamController.toBeArranged(), (t: ToBeArranged) => {
              this.TbaCard(t)
            }, (t: ToBeArranged) => `tba-${t.subject}-${t.id}`)
          }
          .width('100%')
        }

        if (!ExamController.hasData() || (ExamController.subjects().length === 0
          && ExamController.toBeArranged().length === 0)) {
          Text($r('app.string.exam_empty_hint'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 80 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 32 })
    }
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .height('100%')
  }

  @Builder
  LoadingView() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(this.themePrimary)
      Text($r('app.string.exam_loading'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ErrorView() {
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
  }

  build() {
    NavDestination() {
      Column() {
        if (this.errorMsg.length > 0 && !ExamController.hasData()) {
          this.ErrorView()
        } else if (!ExamController.hasData() && this.busy) {
          this.LoadingView()
        } else {
          this.Body()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_bg'))
    }
    .title($r('app.string.exam_title'))
    .backgroundColor($r('app.color.app_bg'))
  }
}
