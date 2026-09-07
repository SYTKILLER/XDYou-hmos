import { ClassTableController } from '../../controller/ClassTableController';
import { ClassDetail, TimeArrangement } from '../../model/classtable/ClassTableData';
import { TIME_LIST } from '../../model/TimeList';

/** 课程色板（与 ClassTablePage 同源 app.color.course_0..7；独立副本避免 页⇄弹窗 循环导入）。 */
const COURSE_BG: Resource[] = [
  $r('app.color.course_0'), $r('app.color.course_1'), $r('app.color.course_2'), $r('app.color.course_3'),
  $r('app.color.course_4'), $r('app.color.course_5'), $r('app.color.course_6'), $r('app.color.course_7')
];

const COURSE_BG_COUNT: number = 8;

const WEEKDAY_NAMES: string[] = ['一', '二', '三', '四', '五', '六', '日'];

/**
 * 课程详情卡片弹窗（对应 Dart arrangement_detail/course_detail_card.dart）。
 * 点击课表格子弹出，展示该时段全部排课（冲突课并列多卡）：
 * 课程名/课程代码·班级号/任课老师/教室/星期节次+钟点/周次圆点表（当前周描边）。
 * 数据经 ClassTableController.detailTargets/detailWeek 桥传入（ScoreDetailDialog.detailTarget 同款参数桥）。
 */
@CustomDialog
export struct CourseDetailDialog {
  controller?: CustomDialogController = undefined;
  // 主题响应式 token（AppTheme.syncStorage 维护），当前周描边随种子色/深浅色刷新。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';

  private targets(): TimeArrangement[] {
    return ClassTableController.detailTargets;
  }

  private detailOf(t: TimeArrangement): ClassDetail {
    return ClassTableController.data().getClassDetail(t);
  }

  /** 课程代码 | 班级号（原版 class_number_string；均空时不显示该行）。 */
  private subTitle(t: TimeArrangement): string {
    const d: ClassDetail = this.detailOf(t);
    const parts: string[] = [];
    if (d.code.length > 0) {
      parts.push(d.code);
    }
    if (d.number.length > 0) {
      parts.push(`班级号 ${d.number}`);
    }
    return parts.join(' | ');
  }

  private teacherText(t: TimeArrangement): string {
    return t.teacher.length > 0 ? t.teacher : '未知老师';
  }

  private roomText(t: TimeArrangement): string {
    return t.classroom.length > 0 ? t.classroom : '未知地点';
  }

  /** 周 X 第 a-b 节 + 钟点区间（节次越界时退化为纯节次文案）。 */
  private timeText(t: TimeArrangement): string {
    const dayName: string = t.day >= 1 && t.day <= 7 ? WEEKDAY_NAMES[t.day - 1] : `${t.day}`;
    const period: string = `周${dayName} 第${t.start}-${t.stop}节`;
    const startIdx: number = (t.start - 1) * 2;
    const stopIdx: number = (t.stop - 1) * 2 + 1;
    if (startIdx < 0 || stopIdx >= TIME_LIST.length) {
      return period;
    }
    return `${period} ${TIME_LIST[startIdx]}-${TIME_LIST[stopIdx]}`;
  }

  /** weight 仅供横向并排（老师/教室）分半宽度；纵向单独使用必须传 0，否则吃掉剩余高度撑满弹窗。 */
  @Builder
  IconLine(icon: Resource, text: string, weight: number) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([$r('app.color.text_primary')])
      Text(text)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .alignItems(VerticalAlign.Center)
    .layoutWeight(weight)
  }

  /** 周次圆点：有课填充、无课淡化、当前周（点击所在周）主题色描边。 */
  @Builder
  WeekCircle(weekList: boolean[], index: number) {
    Text(`${index + 1}`)
      .fontSize(11)
      .fontColor(weekList[index] ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      .width(28)
      .height(28)
      .textAlign(TextAlign.Center)
      .borderRadius(14)
      .backgroundColor(weekList[index] ? $r('app.color.app_card') : Color.Transparent)
      .opacity(weekList[index] ? 1 : 0.6)
      .border(ClassTableController.detailWeek === index
        ? { width: 2, color: this.themePrimary } : { width: 0, color: Color.Transparent })
      .margin(2)
  }

  @Builder
  CourseCard(t: TimeArrangement, index: number) {
    Column({ space: 8 }) {
      Text(this.detailOf(t).name)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.subTitle(t).length > 0) {
        Text(this.subTitle(t))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      Row({ space: 12 }) {
        this.IconLine($r('sys.symbol.person'), this.teacherText(t), 1)
        this.IconLine($r('sys.symbol.pin'), this.roomText(t), 1)
      }
      .width('100%')
      this.IconLine($r('sys.symbol.clock'), this.timeText(t), 0)
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(t.weekList, (occupied: boolean, i: number) => {
          this.WeekCircle(t.weekList, i)
        }, (occupied: boolean, i: number) => `${i}`)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(COURSE_BG[ClassTableController.data().colorIndex(t) % COURSE_BG_COUNT])
  }

  build() {
    Column({ space: 12 }) {
      if (this.targets().length === 0) {
        Text('暂无课程信息')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
      } else {
        ForEach(this.targets(), (t: TimeArrangement, index: number) => {
          this.CourseCard(t, index)
        }, (t: TimeArrangement, index: number) => `${index}-${t.start}-${t.stop}-${t.classroom}`)
      }
    }
    .width('100%')
    .padding(12)
  }
}
