import { ScoreController } from '../../controller/ScoreController';
import { ComposeDetail } from '../../model/score/ScoreData';
import { Log } from '../../utils/Log';

/**
 * 单科成绩组成弹窗（平时/期中/期末等占比与得分，来自 cxkckgcxlrcj 协议）。
 * 目标科目经 ScoreController.detailTarget 传入（CustomDialog 参数桥）。
 */
@CustomDialog
export struct ScoreDetailDialog {
  controller?: CustomDialogController = undefined;
  // 主题响应式 token（AppTheme.syncStorage 维护）。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @State details: ComposeDetail[] = [];
  @State loading: boolean = true;

  aboutToAppear(): void {
    const target = ScoreController.detailTarget;
    if (target === null) {
      this.loading = false;
      return;
    }
    ScoreController.getDetail(target).then((list: ComposeDetail[]): void => {
      this.details = list;
      this.loading = false;
    }).catch((e: Object): void => {
      Log.warn(`score detail dialog failed: ${e}`);
      this.details = [new ComposeDetail('', '获取详情失败', '')];
      this.loading = false;
    });
  }

  build() {
    Column({ space: 12 }) {
      Text(ScoreController.detailTarget !== null ? ScoreController.detailTarget.name : '')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.loading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.themePrimary)
          .margin({ top: 12, bottom: 12 })
      } else if (this.details.length === 0) {
        Text($r('app.string.score_detail_none'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      } else {
        ForEach(this.details, (d: ComposeDetail) => {
          Row({ space: 12 }) {
            Text(d.content)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            Text(d.ratio)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(d.score)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .border({ width: { bottom: 0.5 }, color: $r('app.color.divider') })
        }, (d: ComposeDetail) => `${d.content}-${d.ratio}`)
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 16 })
  }
}
