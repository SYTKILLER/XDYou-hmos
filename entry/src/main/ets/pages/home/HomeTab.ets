import { HomepageController } from '../../controller/HomepageController';
import { ClassTableController } from '../../controller/ClassTableController';
import { ExamController } from '../../controller/ExamController';
import { EnergyController } from '../../controller/EnergyController';
import { LibraryController } from '../../controller/LibraryController';
import { SchoolnetController } from '../../controller/SchoolnetController';
import { HomeArrangement } from '../../model/HomeArrangement';
import { Subject } from '../../model/exam/ExamData';
import { BorrowData } from '../../model/library/LibraryModels';
import { CurrentUserNetInfo, formatBytes } from '../../model/schoolnet/NetworkUsage';
import { EnergyInfo } from '../../model/energy/EnergyData';
import { AppNav } from '../../service/nav/AppNav';
import { TAB_BAR_CLEARANCE } from './HomeLayout';
import { Log } from '../../utils/Log';

/**
 * 首页页签（"此刻"聚焦版）：
 * Hero 卡 = 课程/考试双形态（合并时间线取最近一条未结束日程，课程上完考试自然顶到首位；
 * 考试态展示时间/考场/座位，21:25 后展示明天）+ 需要留意提醒条（电费低于阈值/图书临期/
 * 考试临近，Hero 已是考试态时去重考试条）+ 2×2 信息瓦片（考试倒计时/宿舍电费/图书借阅/校园网流量）。
 * Refresh 下拉全量刷新；整分定时器 nowTick 驱动进度条与倒计时刷新。
 * 各控制器版本号（classTable/exam/energy/library/schoolnet Version）在取数方法中真实读取：
 * 静默刷新完成后展示节点立即重建，不等整分 tick（NOTICE 2026-09-06 刷新依赖教训）。
 */
@Component
export struct HomeTab {
  // 主题响应式 token（AppTheme.syncStorage 维护），build 中直接引用才有刷新依赖。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themePrimaryContainer') themePrimaryContainer: string = '#D0E4FF';
  @StorageProp('nowTick') tick: number = Date.now();
  // 控制器版本号：取数方法内真实读取建立刷新依赖（bumpVersion 自增 → 展示节点立即重建）。
  @StorageProp('classTableVersion') classTableVersion: number = 0;
  @StorageProp('examVersion') examVersion: number = 0;
  @StorageProp('energyVersion') energyVersion: number = 0;
  @StorageProp('libraryVersion') libraryVersion: number = 0;
  @StorageProp('schoolnetVersion') schoolnetVersion: number = 0;
  @State refreshing: boolean = false;
  @State silentRefreshed: boolean = false;

  aboutToAppear(): void {
    ClassTableController.loadCache();
    ExamController.loadCache();
    EnergyController.loadCache();
    SchoolnetController.loadCache();
    // 静默全量刷新（与 HomePageView 的启动刷新共享 inflight，不会重复请求）：
    // 完成后必须翻转 @State 强制重渲染，否则各卡要等下一个整分 nowTick 才更新。
    HomepageController.refreshAll().then((): void => {
      this.silentRefreshed = true;
    }).catch((e: Object): void => {
      Log.warn(`homepage silent refresh failed: ${e}`);
    });
  }

  private nowDate(): Date {
    return new Date(this.tick);
  }

  private dateText(): string {
    const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    const now: Date = this.nowDate();
    return `${now.getMonth() + 1}月${now.getDate()}日 星期${weekdays[now.getDay()]}`;
  }

  private weekText(): string {
    const week: number = ClassTableController.getCurrentWeek(this.nowDate());
    return week >= 0 ? `第${week + 1}周` : '假期中';
  }

  private greeting(): string {
    const h: number = this.nowDate().getHours();
    if (h >= 5 && h < 11) {
      return '早上好';
    }
    if (h >= 11 && h < 13) {
      return '中午好';
    }
    if (h >= 13 && h < 18) {
      return '下午好';
    }
    return '晚上好';
  }

  private static hhmm(full: string): string {
    return full.length >= 16 ? full.substring(11, 16) : full;
  }

  private isOngoing(a: HomeArrangement): boolean {
    const now: number = this.nowDate().getTime();
    return a.startTime().getTime() <= now && now < a.endTime().getTime();
  }

  private infoLine(a: HomeArrangement): string {
    const parts: string[] = [];
    if (a.place.length > 0) {
      parts.push(a.place);
    }
    if (a.seat.length > 0) {
      parts.push(`座位 ${a.seat}`);
    }
    if (a.teacher.length > 0) {
      parts.push(a.teacher);
    }
    return parts.join(' · ');
  }

  // ---- Hero：合并时间线（课程+考试）取最近一条未结束日程 ----

  private heroItem(): HomeArrangement | null {
    const version: number = this.classTableVersion + this.examVersion;
    const items: HomeArrangement[] = version >= 0
      ? HomepageController.currentSchedule(this.nowDate()).items : [];
    return items.length > 0 ? items[0] : null;
  }

  private heroOngoing(): boolean {
    const a: HomeArrangement | null = this.heroItem();
    return a !== null && this.isOngoing(a);
  }

  private heroIsExam(): boolean {
    const a: HomeArrangement | null = this.heroItem();
    return a !== null && a.type === 'exam';
  }

  /** 考试聚合条目名为 "{课程名}考试"，展示时还原课程名 + "考试"标签。 */
  private displayTitle(a: HomeArrangement): string {
    if (a.type === 'exam' && a.name.endsWith('考试')) {
      return a.name.substring(0, a.name.length - 2);
    }
    return a.name;
  }

  private heroTitle(): string {
    const a: HomeArrangement | null = this.heroItem();
    return a !== null ? this.displayTitle(a) : '';
  }

  private heroLabel(): string {
    const tomorrow: boolean = HomepageController.isTomorrow(this.nowDate());
    if (this.heroIsExam()) {
      if (tomorrow) {
        return '明天考试';
      }
      return this.heroOngoing() ? '正在考试' : '即将考试';
    }
    if (tomorrow) {
      return '明天';
    }
    return this.heroOngoing() ? '正在上' : '下一节';
  }

  private heroEmptyText(): string {
    return HomepageController.isTomorrow(this.nowDate()) ? '明天没有安排，好好休息' : '今天没有更多安排了';
  }

  /** 分钟级倒计时（跨天 X 天 Y 小时，当日 X 小时 Y 分 / Y 分）。 */
  private heroCountdownText(): string {
    const a: HomeArrangement | null = this.heroItem();
    if (a === null) {
      return '';
    }
    const diff: number = a.startTime().getTime() - this.nowDate().getTime();
    if (diff <= 0) {
      return '即将开始';
    }
    const days: number = Math.floor(diff / 86400000);
    const hours: number = Math.floor((diff % 86400000) / 3600000);
    const mins: number = Math.floor((diff % 3600000) / 60000);
    if (days > 0) {
      return `${days} 天 ${hours} 小时`;
    }
    if (hours > 0) {
      return `${hours} 小时 ${mins} 分`;
    }
    return `${Math.max(mins, 1)} 分`;
  }

  private heroRemainText(): string {
    const a: HomeArrangement | null = this.heroItem();
    if (a === null) {
      return '';
    }
    const min: number = Math.max(1, Math.ceil((a.endTime().getTime() - this.nowDate().getTime()) / 60000));
    return `剩 ${min} 分钟`;
  }

  private heroElapsedMin(): number {
    const a: HomeArrangement | null = this.heroItem();
    if (a === null) {
      return 0;
    }
    const elapsed: number = Math.floor((this.nowDate().getTime() - a.startTime().getTime()) / 60000);
    return Math.min(Math.max(elapsed, 0), this.heroTotalMin());
  }

  private heroTotalMin(): number {
    const a: HomeArrangement | null = this.heroItem();
    if (a === null) {
      return 1;
    }
    return Math.max(1, Math.ceil((a.endTime().getTime() - a.startTime().getTime()) / 60000));
  }

  private heroTimeText(): string {
    const a: HomeArrangement | null = this.heroItem();
    return a !== null ? `${HomeTab.hhmm(a.startTimeStr)} – ${HomeTab.hhmm(a.endTimeStr)}` : '';
  }

  /** 课程态 meta：时间段 · 地点 · 教师。 */
  private heroMetaLine(): string {
    const a: HomeArrangement | null = this.heroItem();
    if (a === null) {
      return '';
    }
    const info: string = this.infoLine(a);
    return info.length > 0 ? `${this.heroTimeText()} · ${info}` : this.heroTimeText();
  }

  private heroExamPlace(): string {
    const a: HomeArrangement | null = this.heroItem();
    return a !== null ? a.place : '';
  }

  private heroExamSeat(): string {
    const a: HomeArrangement | null = this.heroItem();
    return a !== null && a.seat.length > 0 ? `${a.seat} 号` : '';
  }

  private heroNext(): HomeArrangement | null {
    const version: number = this.classTableVersion + this.examVersion;
    const items: HomeArrangement[] = version >= 0
      ? HomepageController.currentSchedule(this.nowDate()).items : [];
    return items.length > 1 ? items[1] : null;
  }

  private heroNextLabel(): string {
    const next: HomeArrangement | null = this.heroNext();
    if (next === null) {
      return '';
    }
    if (next.type === 'exam') {
      return '下一场';
    }
    return this.heroOngoing() ? '下一节' : '再之后';
  }

  private heroNextText(): string {
    const next: HomeArrangement | null = this.heroNext();
    return next !== null ? `${next.name} ${HomeTab.hhmm(next.startTimeStr)}` : '';
  }

  // ---- 需要留意：电费低于阈值 / 图书临期 / 考试临近（Hero 考试态去重）----

  /** 电费余量（度）；无数据为 null。 */
  private energyRemain(): number | null {
    const version: number = this.energyVersion;
    if (!EnergyController.hasData() || version < 0) {
      return null;
    }
    const info: EnergyInfo | null = EnergyController.data();
    return info !== null ? info.electricityRemain : null;
  }

  private energyLow(): boolean {
    const remain: number | null = this.energyRemain();
    return remain !== null && remain <= EnergyController.lowThreshold();
  }

  private energyRemainText(): string {
    const remain: number | null = this.energyRemain();
    return remain !== null ? `电费仅剩 ${remain} 度，低于提醒阈值` : '';
  }

  /** 7 天内到期的最近一本；无则 null。 */
  private nearestDueBook(): BorrowData | null {
    const version: number = this.libraryVersion;
    let nearest: BorrowData | null = null;
    const list: BorrowData[] = version >= 0 ? LibraryController.borrowData() : [];
    list.forEach((b: BorrowData): void => {
      if (b.lendDay() > 7) {
        return;
      }
      if (nearest === null || b.lendDay() < nearest.lendDay()) {
        nearest = b;
      }
    });
    return nearest;
  }

  private dueBookText(): string {
    const b: BorrowData | null = this.nearestDueBook();
    if (b === null) {
      return '';
    }
    const d: number = b.lendDay();
    if (d < 0) {
      return `《${b.title}》已逾期，请尽快归还`;
    }
    if (d === 0) {
      return `《${b.title}》今天到期`;
    }
    return `《${b.title}》${d} 天后到期`;
  }

  private upcomingExam(): Subject | null {
    const version: number = this.examVersion;
    const list: Subject[] = version >= 0 ? ExamController.isNotFinished(this.nowDate()) : [];
    return list.length > 0 ? list[0] : null;
  }

  private examCountdown(s: Subject): string {
    const start: Date | null = s.startTime();
    if (start === null) {
      return '';
    }
    const diff: number = start.getTime() - this.nowDate().getTime();
    if (diff <= 0) {
      return '即将开始';
    }
    const days: number = Math.floor(diff / 86400000);
    const hours: number = Math.floor((diff % 86400000) / 3600000);
    return days > 0 ? `${days} 天 ${hours} 小时后` : `${hours} 小时后`;
  }

  private hasExamReminder(): boolean {
    return !this.heroIsExam() && this.upcomingExam() !== null;
  }

  private examReminderText(): string {
    const s: Subject | null = this.upcomingExam();
    return s !== null ? `${s.subject}考试 ${this.examCountdown(s)}开考` : '';
  }

  // ---- 信息瓦片数据 ----

  private examTileMain(): string {
    const s: Subject | null = this.upcomingExam();
    return s !== null ? s.subject : '暂无考试';
  }

  private examTileSub(): string {
    const version: number = this.examVersion;
    const list: Subject[] = version >= 0 ? ExamController.isNotFinished(this.nowDate()) : [];
    if (list.length === 0) {
      return '点击查看考试安排';
    }
    const cd: string = this.examCountdown(list[0]);
    return list.length > 1 ? `${cd} · 共 ${list.length} 场` : cd;
  }

  private energyTileMain(): string {
    const remain: number | null = this.energyRemain();
    return remain !== null ? `${remain} 度` : '暂无数据';
  }

  private energyTileSub(): string {
    if (!EnergyController.hasData()) {
      return '点击配置房间';
    }
    return this.energyLow() ? '低于提醒阈值，记得充值' : '余额充足';
  }

  private borrowTileMain(): string {
    const version: number = this.libraryVersion;
    const n: number = version >= 0 ? LibraryController.borrowData().length : 0;
    return n > 0 ? `在借 ${n} 本` : '暂无在借';
  }

  private borrowTileSub(): string {
    const b: BorrowData | null = this.nearestDueBook();
    if (b === null) {
      return '点击检索馆藏';
    }
    const d: number = b.lendDay();
    if (d < 0) {
      return '最近一本已逾期';
    }
    if (d === 0) {
      return '最近一本今天到期';
    }
    return `最近到期 ${d} 天后`;
  }

  /** 瓦片与校园网页面"流量使用情况"区同口径：rad_user_info 快照（不判 isOnline，页面同款）。 */
  private netTileMain(): string {
    const version: number = this.schoolnetVersion;
    const info: CurrentUserNetInfo | null = version >= 0 ? SchoolnetController.userInfoData() : null;
    return info !== null ? formatBytes(info.sumBytes) : '暂无数据';
  }

  private netTileSub(): string {
    const version: number = this.schoolnetVersion;
    const info: CurrentUserNetInfo | null = version >= 0 ? SchoolnetController.userInfoData() : null;
    return info !== null ? `剩余 ${formatBytes(info.remainBytes)}` : '点击查看校园网';
  }

  private doRefresh(): void {
    this.refreshing = true;
    HomepageController.refreshAll().then((): void => {
      this.refreshing = false;
    }).catch((e: Object): void => {
      this.refreshing = false;
      Log.warn(`homepage refresh failed: ${e}`);
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.home_refresh_failed') });
    });
  }

  private openPage(name: string): void {
    const stack: NavPathStack | null = AppNav.stackOrNull();
    if (stack !== null) {
      stack.pushPath({ name: name });
    }
  }

  @Builder
  HeroCard() {
    Column({ space: 12 }) {
      if (this.heroItem() === null) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.calendar_badge_clock'))
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
          Text(this.heroEmptyText())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Row({ space: 8 }) {
          Text(this.heroLabel())
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
          if (this.heroIsExam()) {
            Text('考试')
              .fontSize(11)
              .fontColor(this.themePrimary)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(this.themePrimaryContainer)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.heroTitle())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.heroIsExam()) {
          Column({ space: 6 }) {
            Row({ space: 12 }) {
              Text('时间')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width(36)
              Text(this.heroTimeText())
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.heroExamPlace().length > 0) {
              Row({ space: 12 }) {
                Text('考场')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width(36)
                Text(this.heroExamPlace())
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }

            if (this.heroExamSeat().length > 0) {
              Row({ space: 12 }) {
                Text('座位')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width(36)
                Text(this.heroExamSeat())
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        } else {
          Text(this.heroMetaLine())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        if (!this.heroOngoing() && this.heroItem() !== null) {
          Text(`还有 ${this.heroCountdownText()}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .width('100%')
        }

        if (this.heroOngoing()) {
          Row({ space: 12 }) {
            Progress({ value: this.heroElapsedMin(), total: this.heroTotalMin(), type: ProgressType.Linear })
              .style({ strokeWidth: 6 })
              .color(this.themePrimary)
              .layoutWeight(1)
            Text(this.heroRemainText())
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }

        if (this.heroNext() !== null) {
          Divider()
            .strokeWidth(1)
            .color($r('app.color.divider'))
            .width('100%')

          Row({ space: 8 }) {
            Text(this.heroNextLabel())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(this.heroNextText())
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(12)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 20 })
    .onClick(() => this.openPage(this.heroIsExam() ? 'exam' : 'classTable'))
  }

  @Builder
  ReminderRow(icon: Resource, msg: string, action: string, page: string) {
    Row({ space: 10 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.themePrimary])
      Text(msg)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(action)
        .fontSize(13)
        .fontColor(this.themePrimary)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.openPage(page))
  }

  @Builder
  RemindersCard() {
    Column({ space: 4 }) {
      Text('需要留意')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      if (this.energyLow()) {
        this.ReminderRow($r('sys.symbol.bolt'), this.energyRemainText(), '去充值', 'electricity')
      }
      if (this.nearestDueBook() !== null) {
        this.ReminderRow($r('sys.symbol.text_book_closed'), this.dueBookText(), '去续借', 'library')
      }
      if (this.hasExamReminder()) {
        this.ReminderRow($r('sys.symbol.doc_text_badge_clock'), this.examReminderText(), '详情', 'exam')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 24 })
  }

  @Builder
  TileCard(icon: Resource, title: string, main: string, sub: string, page: string) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        SymbolGlyph(icon)
          .fontSize(15)
          .fontColor([this.themePrimary])
        Text(title)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(main)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(sub)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .onClick(() => this.openPage(page))
  }

  build() {
    Refresh({ refreshing: this.refreshing }) {
      Scroll() {
        Column() {
          Text(this.greeting())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(`${this.dateText()} · ${this.weekText()}`)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
          // silentRefreshed 在 build 中真实读取：冷启动静默刷新完成后立即重建各卡，
          // 否则要等下一个整分 nowTick（2026-09-06 刷新依赖教训）。
          if (!this.silentRefreshed && !ClassTableController.hasData()) {
            Text('正在同步数据…')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 12 })
          }

          this.HeroCard()

          if (this.energyLow() || this.nearestDueBook() !== null || this.hasExamReminder()) {
            this.RemindersCard()
          }

          Row({ space: 12 }) {
            this.TileCard($r('sys.symbol.doc_text_badge_clock'), '考试倒计时',
              this.examTileMain(), this.examTileSub(), 'exam')
            this.TileCard($r('sys.symbol.bolt'), '宿舍电费',
              this.energyTileMain(), this.energyTileSub(), 'electricity')
          }
          .width('100%')
          .margin({ top: 24 })

          Row({ space: 12 }) {
            this.TileCard($r('sys.symbol.text_book_closed'), '图书借阅',
              this.borrowTileMain(), this.borrowTileSub(), 'library')
            this.TileCard($r('sys.symbol.dot_radiowaves_left_and_right'), '校园网',
              this.netTileMain(), this.netTileSub(), 'schoolnet')
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: TAB_BAR_CLEARANCE })
      }
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
    }
    .onRefreshing(() => this.doRefresh())
    .width('100%')
    .height('100%')
  }
}
