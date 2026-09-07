import { ClassTableController, WeekDot } from '../../controller/ClassTableController';
import { ClassTableData, TimeArrangement } from '../../model/classtable/ClassTableData';
import { CourseDetailDialog } from './CourseDetailDialog';
import { TIME_LIST, SECTION_COUNT } from '../../model/TimeList';
import { DateUtil } from '../../utils/date/DateUtil';
import { Log } from '../../utils/Log';

/** 课程色板（app.color.course_0..7，base/dark 双份自动切换）。 */
const COURSE_BG: Resource[] = [
  $r('app.color.course_0'), $r('app.color.course_1'), $r('app.color.course_2'), $r('app.color.course_3'),
  $r('app.color.course_4'), $r('app.color.course_5'), $r('app.color.course_6'), $r('app.color.course_7')
];

interface CellSpec {
  row: number;
  col: number;
  rowSpan: number;
  title: string;
  subtitle: string;
  colorIndex: number;
}

/**
 * 课程表页（NavDestination，M2）：节次×星期周视图 Grid。
 * 顶部周缩略图条（第N周 + 5×5 课程圆点预览，点击切周）；主表 Swiper 左右滑动切周；
 * Select/箭头/刷新保留。weekIndex 是唯一周次状态源，四路切换都写它。
 * 数据来自 ClassTableController（缓存先行，无数据时自动拉取）。
 */
@Component
export struct ClassTablePage {
  // 主题响应式 token（AppTheme.syncStorage 维护），今日列/缩略图选中态随种子色/深浅色刷新。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themePrimaryContainer') themePrimaryContainer: string = '#D0E4FF';
  // weekIndex 变化统一走 @Watch：缩略图条滚动到居中位置（Swiper index 与它单向绑定 + onChange 幂等回写）。
  @State @Watch('onWeekIndexChange') weekIndex: number = 0;
  @State busy: boolean = false;
  @State errorMsg: string = '';
  // 数据刷新完成信号：进入 Swiper/List 的 ForEach key（页内容不读 weekIndex，刷新后靠 key 变更强制重建）。
  @State dataVersion: number = 0;
  private listScroller: ListScroller = new ListScroller();
  private swiperController: SwiperController = new SwiperController();
  private thumbReady: boolean = false;
  private thumbInitialized: boolean = false;
  // 课程详情弹窗：点击格子时才创建（延迟创建，成员初始化器创建会导致白屏，见 ScorePage 同款）。
  private dialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    ClassTableController.loadCache();
    const current: number = ClassTableController.getCurrentWeek(new Date());
    this.weekIndex = current >= 0 ? current : 0;
    this.clampWeek();
    this.refresh();
  }

  private onWeekIndexChange(): void {
    if (this.thumbReady && this.weekIndex >= 0 && this.weekIndex < this.semesterLength()) {
      this.listScroller.scrollToIndex(this.weekIndex, true, ScrollAlign.CENTER);
    }
  }

  private semesterLength(): number {
    return Math.max(1, ClassTableController.data().semesterLength);
  }

  private clampWeek(): void {
    if (this.weekIndex < 0) {
      this.weekIndex = 0;
    }
    if (this.weekIndex >= this.semesterLength()) {
      this.weekIndex = this.semesterLength() - 1;
    }
  }

  private semesterText(): string {
    const code: string = ClassTableController.data().semesterCode;
    return code.length > 0 ? code : '学期未知，请刷新';
  }

  private refresh(): void {
    this.busy = true;
    this.errorMsg = '';
    ClassTableController.refresh().then((): void => {
      this.busy = false;
      const current: number = ClassTableController.getCurrentWeek(new Date());
      if (current >= 0) {
        this.weekIndex = current;
      }
      this.clampWeek();
      this.dataVersion++;
    }).catch((e: Object): void => {
      this.busy = false;
      this.errorMsg = `${e}`;
      Log.error(`classtable refresh failed: ${e}`);
    });
  }

  private weekOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (let i = 0; i < this.semesterLength(); i++) {
      options.push({ value: `第${i + 1}周` });
    }
    return options;
  }

  /** Select 按钮文本：selected 只定菜单高亮，按钮文字必须用 value 提供（越界回退第 1 周，不允许空文本）。 */
  private weekLabel(): string {
    const options: SelectOption[] = this.weekOptions();
    const index: number = this.weekIndex >= 0 && this.weekIndex < options.length ? this.weekIndex : 0;
    const v: string | Resource = options[index].value;
    return typeof v === 'string' ? v : '第1周';
  }

  /** 表头星期文案（表头/节次列不进 Grid：模板串含 vp 单位会使整个网格解析塌陷，Grid 只用纯 fr）。 */
  private static readonly WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  /** 11 个节次的起始时间（与 Grid 的 11 个 1fr 行对齐）。 */
  private timeHeaders(): string[] {
    const list: string[] = [];
    for (let r = 1; r <= SECTION_COUNT; r++) {
      list.push(TIME_LIST[(r - 1) * 2]);
    }
    return list;
  }

  /** 全部周次序号（Swiper 页与缩略图卡的公共数据源）。 */
  private weekRange(): number[] {
    const weeks: number[] = [];
    for (let i = 0; i < this.semesterLength(); i++) {
      weeks.push(i);
    }
    return weeks;
  }

  /** 某周 7 天日期（周一起）。startDay 不可用时退化用当前时刻占位（仅无数据期渲染，随数据到达重建）。 */
  private weekDates(week: number): Date[] {
    const dates: Date[] = [];
    const first: Date | null = ClassTableController.weekStartDate(week);
    const base: number = first !== null ? first.getTime() : Date.now();
    for (let i = 0; i < 7; i++) {
      dates.push(new Date(base + i * DateUtil.MS_PER_DAY));
    }
    return dates;
  }

  /** 日期行月份标签（取该周首日所在月，跨月周与原版一致只标首日月）。 */
  private monthLabel(week: number): string {
    const first: Date | null = ClassTableController.weekStartDate(week);
    return first !== null ? `${first.getMonth() + 1}月` : '';
  }

  /** 第 col 列（0 基）是否今天：隐含「显示的周 = 实际当前周」，过去/未来周不命中。 */
  private isToday(week: number, col: number): boolean {
    return DateUtil.isSameDay(this.weekDates(week)[col], new Date());
  }

  /** 实际当前周次（0 基，假期为 -1）：缩略图当前周加粗用。 */
  private actualWeek(): number {
    return ClassTableController.getCurrentWeek(new Date());
  }

  /** 缩略图 5 行圆点（每行 5 格，行优先切自 25 元素数组）。 */
  private thumbRows(week: number): WeekDot[][] {
    const dots: WeekDot[] = ClassTableController.getWeekDots(week);
    const rows: WeekDot[][] = [];
    for (let r = 0; r < 5; r++) {
      rows.push(dots.slice(r * 5, r * 5 + 5));
    }
    return rows;
  }

  /** 本周课程格（0-based 行列：row = 起始节-1，col = 星期-1，官方闭区间跨度 = end-start+1）。 */
  private courseCells(week: number): CellSpec[] {
    const cells: CellSpec[] = [];
    if (week < 0) {
      return cells;
    }
    const data: ClassTableData = ClassTableController.data();
    for (let i = 0; i < data.timeArrangement.length; i++) {
      const t = data.timeArrangement[i];
      if (week >= t.weekList.length || !t.weekList[week]) {
        continue;
      }
      if (t.day < 1 || t.day > 7) {
        continue;
      }
      cells.push({
        row: t.start - 1, col: t.day - 1, rowSpan: Math.max(1, t.stop - t.start + 1),
        title: data.getClassDetail(t).name, subtitle: t.classroom,
        colorIndex: data.colorIndex(t) % COURSE_BG.length
      });
    }
    return cells;
  }

  /** 与点击格子同一天且节次区间有交集的本周排课（冲突课一并进详情卡，对应 Dart ArrangementList）。 */
  private arrangementsAt(cell: CellSpec): TimeArrangement[] {
    const data: ClassTableData = ClassTableController.data();
    const result: TimeArrangement[] = [];
    const rowEnd: number = cell.row + cell.rowSpan - 1;
    for (let i = 0; i < data.timeArrangement.length; i++) {
      const t = data.timeArrangement[i];
      const coversWeek: boolean = this.weekIndex < t.weekList.length && t.weekList[this.weekIndex];
      const overlaps: boolean = t.day - 1 === cell.col && t.start - 1 <= rowEnd && t.stop - 1 >= cell.row;
      if (coversWeek && overlaps) {
        result.push(t);
      }
    }
    return result;
  }

  private onCellClick(cell: CellSpec): void {
    const targets: TimeArrangement[] = this.arrangementsAt(cell);
    if (targets.length === 0) {
      return;
    }
    ClassTableController.detailTargets = targets;
    ClassTableController.detailWeek = this.weekIndex;
    if (this.dialogController === null) {
      this.dialogController = new CustomDialogController({
        builder: CourseDetailDialog(),
        autoCancel: true,
        // 表面圆角 24 = 内卡圆角 12 + 根 padding 12（同心圆角），白边四周均匀。
        cornerRadius: 24
      });
    }
    this.dialogController.open();
  }

  @Builder
  GridCell(cell: CellSpec) {
    Column({ space: 2 }) {
      Text(cell.title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(3)
        .textAlign(TextAlign.Center)
      if (cell.subtitle.length > 0) {
        Text(cell.subtitle)
          .fontSize(9)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(2)
    .borderRadius(8)
    .backgroundColor(COURSE_BG[cell.colorIndex])
    .onClick(() => this.onCellClick(cell))
  }

  /** 周缩略图卡：第N周 + 5×5 圆点（有课 1.0 / 已上完 0.45 / 无课 0.15，当前周标题加粗，选中周容器色底）。 */
  @Builder
  WeekThumbCard(week: number) {
    Column({ space: 4 }) {
      Text(`第${week + 1}周`)
        .fontSize(11)
        .fontWeight(week === this.actualWeek() ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.weekIndex === week ? this.themePrimary : $r('app.color.text_primary'))
      Column({ space: 2 }) {
        ForEach(this.thumbRows(week), (row: WeekDot[], r: number) => {
          Row({ space: 2 }) {
            ForEach(row, (dot: WeekDot, c: number) => {
              Column()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.themePrimary)
                .opacity(dot.occupied ? (dot.completed ? 0.45 : 1) : 0.15)
            }, (dot: WeekDot, c: number) => `${r}-${c}-${dot.occupied ? 1 : 0}-${dot.completed ? 1 : 0}`)
          }
        }, (row: WeekDot[], r: number) => `row-${r}`)
      }
    }
    .width(64)
    .height(76)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.weekIndex === week ? this.themePrimaryContainer : $r('app.color.app_card'))
    .onClick(() => {
      this.weekIndex = week;
    })
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
        // 周次选择行
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontColor([this.themePrimary])
            .onClick(() => {
              if (this.weekIndex > 0) {
                this.weekIndex--;
              }
            })
          Select(this.weekOptions())
            .selected(this.weekIndex)
            .value(this.weekLabel())
            .font({ size: 14 })
            .onSelect((index: number): void => {
              this.weekIndex = index;
            })
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(20)
            .fontColor([this.themePrimary])
            .onClick(() => {
              if (this.weekIndex < this.semesterLength() - 1) {
                this.weekIndex++;
              }
            })
          Blank()
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([this.themePrimary])
            .opacity(this.busy ? 0.4 : 1)
            .onClick(() => {
              if (!this.busy) {
                this.refresh();
              }
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })

        Row({ space: 8 }) {
          Text(this.semesterText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          if (ClassTableController.isFromCache() && ClassTableController.fetchTime() > 0) {
            Text($r('app.string.classtable_cache_hint'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          if (this.busy && ClassTableController.hasData()) {
            Text($r('app.string.common_refreshing'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        if (this.errorMsg.length > 0 && !ClassTableController.hasData()) {
          this.ErrorView()
        } else if (!ClassTableController.hasData() && this.busy) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.themePrimary)
            Text($r('app.string.classtable_loading'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 周缩略图条：横向 List 自由浏览，点击切周；weekIndex 变化经 @Watch 滚动居中
          List({ space: 6, scroller: this.listScroller }) {
            ForEach(this.weekRange(), (w: number) => {
              ListItem() {
                this.WeekThumbCard(w)
              }
            }, (w: number) => `thumb-${w}-${this.dataVersion}`)
          }
          .listDirection(Axis.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .height(78)
          .padding({ left: 8, right: 8 })
          .onAppear(() => {
            this.thumbReady = true;
          })
          .onAreaChange((oldArea: Area, newArea: Area) => {
            // 首次布局完成后无动画定位到当前周（onAppear 时机布局未完成，scrollToIndex 可能不生效）
            if (!this.thumbInitialized) {
              this.thumbInitialized = true;
              this.listScroller.scrollToIndex(this.weekIndex, false, ScrollAlign.CENTER);
            }
          })

          // 主表 Swiper：每页 = 日期行 + 周几表头 + 节次列 + 该周课程网格，左右滑动切周
          Swiper(this.swiperController) {
            ForEach(this.weekRange(), (w: number) => {
              Column() {
                // 日期行：月份 + 7 日号（今日列容器色圆角块高亮）
                Row() {
                  Text(this.monthLabel(w))
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width(34)
                    .textAlign(TextAlign.Center)
                  Row({ space: 2 }) {
                    ForEach(this.weekDates(w), (d: Date, i: number) => {
                      Text(`${d.getDate()}`)
                        .fontSize(12)
                        .fontWeight(this.isToday(w, i) ? FontWeight.Bold : FontWeight.Normal)
                        .fontColor(this.isToday(w, i) ? this.themePrimary : $r('app.color.text_secondary'))
                        .textAlign(TextAlign.Center)
                        .layoutWeight(1)
                        .height(20)
                        .borderRadius(8)
                        .backgroundColor(this.isToday(w, i) ? this.themePrimaryContainer : Color.Transparent)
                    }, (d: Date, i: number) => `date-${i}-${d.getDate()}`)
                  }
                  .layoutWeight(1)
                  .height(20)
                }
                .width('100%')
                .height(24)
                .padding({ left: 8, right: 8 })

                // 周几表头（今日列高亮；仅显示当前周时命中）
                Row() {
                  Text('节次')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width(34)
                    .textAlign(TextAlign.Center)
                  Row({ space: 2 }) {
                    ForEach(ClassTablePage.WEEKDAYS, (d: string, i: number) => {
                      Text(`周${d}`)
                        .fontSize(12)
                        .fontWeight(this.isToday(w, i) ? FontWeight.Bold : FontWeight.Normal)
                        .fontColor(this.isToday(w, i) ? this.themePrimary : $r('app.color.text_secondary'))
                        .textAlign(TextAlign.Center)
                        .layoutWeight(1)
                    }, (d: string) => d)
                  }
                  .layoutWeight(1)
                }
                .width('100%')
                .height(30)
                .padding({ left: 8, right: 8 })

                // 主体：左侧节次列（34vp）+ 课程网格（7 列 × 11 节）
                Row() {
                  Column({ space: 2 }) {
                    ForEach(this.timeHeaders(), (t: string) => {
                      Text(t)
                        .fontSize(9)
                        .fontColor($r('app.color.text_secondary'))
                        .width('100%')
                        .textAlign(TextAlign.Center)
                        .layoutWeight(1)
                    }, (t: string) => t)
                  }
                  .width(34)
                  .layoutWeight(0)
                  .height('100%')

                  Grid() {
                    ForEach(this.courseCells(w), (cell: CellSpec) => {
                      GridItem() {
                        this.GridCell(cell)
                      }
                      // GridItem 行列号为 0-based 闭区间行/列号（跨度 = end-start+1）；
                      // 网格模板串只能用 fr，含 vp/固定单位会使整个网格解析塌陷（真机实证）。
                      .rowStart(cell.row)
                      .rowEnd(cell.row + cell.rowSpan - 1)
                      .columnStart(cell.col)
                      .columnEnd(cell.col)
                    }, (cell: CellSpec) => `${cell.row}-${cell.col}-${cell.title}-${cell.subtitle}`)
                  }
                  .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
                  .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
                  .columnsGap(2)
                  .rowsGap(2)
                  .layoutWeight(1)
                  .height('100%')
                }
                .alignItems(VerticalAlign.Top)
                .width('100%')
                .layoutWeight(1)
                .padding({ left: 8, right: 8, bottom: 16 })
              }
              .width('100%')
              .height('100%')
            }, (w: number) => `week-${w}-${this.dataVersion}`)
          }
          .index(this.weekIndex)
          .loop(false)
          .indicator(false)
          .cachedCount(1)
          .onChange((i: number): void => {
            // 手势切周回写唯一状态源；程序化切周（箭头/Select/缩略图）时 i 相同，幂等防联动环
            if (i !== this.weekIndex) {
              this.weekIndex = i;
            }
          })
          .layoutWeight(1)
          .width('100%')

          if (ClassTableController.data().timeArrangement.length === 0) {
            Text($r('app.string.classtable_empty_hint'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ bottom: 24 })
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_bg'))
    }
    .title($r('app.string.classtable_title'))
    .backgroundColor($r('app.color.app_bg'))
  }
}
