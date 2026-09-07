import { EnergyController } from '../../controller/EnergyController';
import { EnergyInfo, ElectricityHistoryInfo, MeterInfo } from '../../model/energy/EnergyData';
import { DateUtil } from '../../utils/date/DateUtil';
import { Log } from '../../utils/Log';

/**
 * 电费查询页（NavDestination，M6）：剩余电量大卡（低阈值告警）+ 近一月电表读数
 * + 近一年水表读数（若有）+ 本地余量记录（每次成功刷新自动追加）。
 * 注意：能耗系统仅校园网环境可访问，错误信息透传说明。
 */
@Component
export struct ElectricityPage {
  // 主题响应式 token（AppTheme.syncStorage 维护）；在 build 中经 accentColor 读取即建立刷新依赖。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('energyVersion') version: number = 0;
  @State busy: boolean = false;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    EnergyController.loadCache();
    this.refresh();
  }

  private refresh(): void {
    this.busy = true;
    this.errorMsg = '';
    EnergyController.refreshData().then((): void => {
      this.busy = false;
    }).catch((e: Object): void => {
      this.busy = false;
      this.errorMsg = `${e}`;
      Log.error(`electricity refresh failed: ${e}`);
    });
  }

  private accentColor(): ResourceColor {
    return this.themePrimary;
  }

  private info(): EnergyInfo | null {
    return EnergyController.data();
  }

  private isLow(info: EnergyInfo): boolean {
    const threshold: number = EnergyController.lowThreshold();
    return threshold > 0 && info.electricityRemain < threshold;
  }

  private historyDay(h: ElectricityHistoryInfo): string {
    return DateUtil.formatDash(h.fetchDay);
  }

  private meterDay(m: MeterInfo): string {
    return DateUtil.formatDash(m.readTime);
  }

  build() {
    NavDestination() {
      Column() {
        if (this.errorMsg.length > 0 && !EnergyController.hasData()) {
          Column({ space: 16 }) {
            Text(this.errorMsg)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
            Text($r('app.string.electricity_schoolnet_only'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
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
        } else if (!EnergyController.hasData() && this.busy) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.accentColor())
            Text($r('app.string.electricity_loading'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              if (EnergyController.isFromCache() && EnergyController.fetchTime() > 0) {
                Text($r('app.string.electricity_cache_hint'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ left: 4, bottom: 8 })
              }

              if (this.busy && EnergyController.hasData()) {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(16)
                    .height(16)
                    .color(this.accentColor())
                  Text($r('app.string.electricity_refreshing'))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding({ left: 4, bottom: 8 })
              }

              if (this.info() !== null) {
                this.RemainCard(this.info() as EnergyInfo)
                if ((this.info() as EnergyInfo).electricityMeterList.length > 0) {
                  this.MeterCard($r('app.string.electricity_meter_section'), 16,
                    (this.info() as EnergyInfo).electricityMeterList)
                }
                if ((this.info() as EnergyInfo).waterMeterList.length > 0) {
                  this.MeterCard($r('app.string.electricity_water_section'), 16,
                    (this.info() as EnergyInfo).waterMeterList)
                }
              }

              if (EnergyController.historyList().length > 0) {
                Column({ space: 8 }) {
                  Text($r('app.string.electricity_history_section'))
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                  Text($r('app.string.electricity_history_desc'))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                  ForEach(EnergyController.historyList(), (h: ElectricityHistoryInfo) => {
                    Row() {
                      Text(this.historyDay(h))
                        .fontSize(13)
                        .fontColor($r('app.color.text_secondary'))
                      Blank()
                      Text(`${h.remain} 度`)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                    .padding({ top: 6, bottom: 6 })
                  }, (h: ElectricityHistoryInfo) => `his-${this.historyDay(h)}-${h.remain}`)
                }
                .width('100%')
                .padding(16)
                .borderRadius(16)
                .backgroundColor($r('app.color.app_card'))
                .alignItems(HorizontalAlign.Start)
                .margin({ top: 16 })
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
    .title($r('app.string.electricity_title'))
    .backgroundColor($r('app.color.app_bg'))
  }

  @Builder
  RemainCard(info: EnergyInfo) {
    Column({ space: 8 }) {
      Text($r('app.string.electricity_remain_label'))
        .fontSize(14)
        .fontColor(this.isLow(info) ? $r('app.color.error') : $r('app.color.text_secondary'))
      Row({ space: 6 }) {
        Text(`${info.electricityRemain}`)
          .fontSize(44)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isLow(info) ? $r('app.color.error') : this.accentColor())
        Text('度')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(VerticalAlign.Bottom)

      if (this.isLow(info)) {
        Text($r('app.string.electricity_low_warning'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.error'))
      }

      Text() {
        Span($r('app.string.electricity_last_read'))
        Span(`: ${DateUtil.formatDash(info.lastReadDate)}`)
      }
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  MeterCard(title: Resource, marginTop: number, list: MeterInfo[]) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Row() {
        Text('日期')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
        Text('上次数')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('本次数')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      ForEach(list, (m: MeterInfo) => {
        Row() {
          Text(this.meterDay(m))
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
          Text(`${m.startNum}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text(`${m.endNum}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .padding({ top: 5, bottom: 5 })
      }, (m: MeterInfo) => `meter-${this.meterDay(m)}-${m.endNum}`)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Start)
    .margin({ top: marginTop })
  }
}
