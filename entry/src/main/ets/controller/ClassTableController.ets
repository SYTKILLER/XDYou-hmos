import { ClassTableSession } from '../service/ids/ClassTableSession';
import { SemesterController } from './SemesterController';
import { PreferenceService } from '../service/preference/PreferenceService';
import { FetchResult } from '../model/FetchResult';
import { HomeArrangement, compareHomeArrangement } from '../model/HomeArrangement';
import { ClassTableData, TimeArrangement } from '../model/classtable/ClassTableData';
import { TIME_LIST } from '../model/TimeList';
import { DateUtil } from '../utils/date/DateUtil';
import { Log } from '../utils/Log';

/** 周缩略图单格圆点状态（对应 Dart WeekChoiceView 的 5×5 课程预览，三态用透明度呈现）。 */
export interface WeekDot {
  occupied: boolean;
  completed: boolean;
}

/** 缩略图时段桶（11 节压缩为 5 行预览，对齐原版早/上午/下午/傍晚/晚的分段）。 */
interface SlotBucket {
  start: number;
  stop: number;
}

/**
 * 课程表控制器（对应 Dart controller/classtable_controller.dart 的精简版）。
 * 状态发布：AppStorage 'classTableVersion' 自增驱动 UI 重建，数据本体由本类静态持有
 * （信号量系统的等价替代；M4 首页聚合沿用同一模式）。
 */
export class ClassTableController {
  private static result: FetchResult<ClassTableData> | null = null;
  private static inflight: Promise<void> | null = null;
  private static readonly PREVIEW_SLOTS: SlotBucket[] = [
    { start: 1, stop: 2 }, { start: 3, stop: 4 }, { start: 5, stop: 6 },
    { start: 7, stop: 8 }, { start: 9, stop: 11 }
  ];

  /** 课程详情弹窗数据桥：点击课表格子时赋值，CourseDetailDialog 构建时读取（ScoreController.detailTarget 同款）。 */
  static detailTargets: TimeArrangement[] = [];
  /** 详情弹窗对应的周次（0 基），周次圆点表描边当前周。 */
  static detailWeek: number = 0;

  /** 启动/进页面时同步回放缓存（快速显示，对应 Dart 构造函数读缓存）。 */
  static loadCache(): void {
    if (ClassTableController.result !== null) {
      return;
    }
    const cached: ClassTableData | null = ClassTableSession.getCacheData();
    if (cached !== null) {
      ClassTableController.result =
        FetchResult.cached<ClassTableData>(cached, ClassTableSession.cacheFetchTime(), '');
    }
  }

  static hasData(): boolean {
    return ClassTableController.result !== null;
  }

  static data(): ClassTableData {
    const r: FetchResult<ClassTableData> | null = ClassTableController.result;
    return r !== null ? r.data : new ClassTableData();
  }

  static isFromCache(): boolean {
    const r: FetchResult<ClassTableData> | null = ClassTableController.result;
    return r !== null && r.isCache;
  }

  static fetchTime(): number {
    const r: FetchResult<ClassTableData> | null = ClassTableController.result;
    return r !== null ? r.fetchTime : 0;
  }

  /**
   * 拉取课表数据（不含学期同步；首页并行刷新用，学期由调用方先行确保）。
   * 并发调用共享同一 in-flight。
   */
  static refreshData(): Promise<void> {
    if (ClassTableController.inflight !== null) {
      return ClassTableController.inflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        const fetchResult: FetchResult<ClassTableData> = await ClassTableSession.getClassTable(
          SemesterController.currentSemester(), PreferenceService.getBool('role', false));
        ClassTableController.result = fetchResult;
        ClassTableController.bumpVersion();
      } finally {
        ClassTableController.inflight = null;
      }
    })();
    ClassTableController.inflight = task;
    return task;
  }

  /** 页面级全量刷新：确保学期后拉取（失败抛错由调用方呈现）。 */
  static refresh(): Promise<void> {
    return SemesterController.ensureSemester().then((): Promise<void> => ClassTableController.refreshData());
  }

  private static bumpVersion(): void {
    AppStorage.setOrCreate('classTableVersion', (AppStorage.get<number>('classTableVersion') ?? 0) + 1);
  }

  /** 学期起点（含用户周次偏移 weekSwift，对应 Dart startDayComputedSignal）。 */
  static startDay(): Date | null {
    const termStartDay: string = ClassTableController.data().termStartDay;
    if (termStartDay.length === 0) {
      return null;
    }
    const parsed: Date | null = DateUtil.parseDateTime(termStartDay);
    if (parsed === null) {
      return null;
    }
    const weekSwift: number = PreferenceService.getNumber('weekSwift', 0);
    return new Date(parsed.getTime() + 7 * weekSwift * DateUtil.MS_PER_DAY);
  }

  /**
   * 当前周次（0 基，对应 Dart getCurrentWeek）：开学前返回 -1（假期中）。
   * 时长整除采用向零截断，与 Dart Duration.inDays / ~/ 语义一致。
   */
  static getCurrentWeek(time: Date): number {
    const startDay: Date | null = ClassTableController.startDay();
    if (startDay === null) {
      return -1;
    }
    let delta: number = Math.trunc((time.getTime() - startDay.getTime()) / DateUtil.MS_PER_DAY);
    if (delta < 0) {
      delta = -7;
    }
    return Math.trunc(delta / 7);
  }

  /** 某周首日（周一，startDay + weekIndex*7 天，对应 Dart dateList 推导）；无学期数据返回 null。 */
  static weekStartDate(weekIndex: number): Date | null {
    const startDay: Date | null = ClassTableController.startDay();
    if (startDay === null) {
      return null;
    }
    return new Date(startDay.getTime() + weekIndex * 7 * DateUtil.MS_PER_DAY);
  }

  /** 节次 stop 的结束时刻是否已过（当天比较，HH:mm 转分钟数）。 */
  private static slotFinished(stopSection: number, now: Date): boolean {
    const index: number = (stopSection - 1) * 2 + 1;
    if (index < 0 || index >= TIME_LIST.length) {
      return false;
    }
    const parts: string[] = TIME_LIST[index].split(':');
    const endMinutes: number = Number(parts[0]) * 60 + Number(parts[1]);
    return now.getHours() * 60 + now.getMinutes() >= endMinutes;
  }

  /**
   * 某周缩略图 25 格圆点（5 天 × 5 时段桶，行优先）：
   * occupied = 该周该天存在与桶相交的排课；
   * completed = 全部相交课程已上完（过去周恒真、未来周恒假，当前周按日期/结束时刻判定）。
   */
  static getWeekDots(weekIndex: number): WeekDot[] {
    const dots: WeekDot[] = [];
    const maxStop: number[] = [];
    for (let i = 0; i < 25; i++) {
      dots.push({ occupied: false, completed: false });
      maxStop.push(0);
    }
    const startDay: Date | null = ClassTableController.startDay();
    if (startDay === null || weekIndex < 0) {
      return dots;
    }
    const data: ClassTableData = ClassTableController.data();
    for (let i = 0; i < data.timeArrangement.length; i++) {
      const t = data.timeArrangement[i];
      if (weekIndex >= t.weekList.length || !t.weekList[weekIndex] || t.day < 1 || t.day > 5) {
        continue;
      }
      for (let s = 0; s < ClassTableController.PREVIEW_SLOTS.length; s++) {
        const bucket: SlotBucket = ClassTableController.PREVIEW_SLOTS[s];
        if (t.start <= bucket.stop && t.stop >= bucket.start) {
          const idx: number = (t.day - 1) * 5 + s;
          dots[idx].occupied = true;
          maxStop[idx] = Math.max(maxStop[idx], t.stop);
        }
      }
    }
    const now: Date = new Date();
    const currentWeek: number = ClassTableController.getCurrentWeek(now);
    if (currentWeek >= 0 && weekIndex < currentWeek) {
      for (let i = 0; i < 25; i++) {
        dots[i].completed = dots[i].occupied;
      }
      return dots;
    }
    if (currentWeek >= 0 && weekIndex === currentWeek) {
      for (let d = 0; d < 5; d++) {
        const dayDate: Date = new Date(startDay.getTime() + (weekIndex * 7 + d) * DateUtil.MS_PER_DAY);
        for (let s = 0; s < 5; s++) {
          const idx: number = d * 5 + s;
          if (!dots[idx].occupied) {
            continue;
          }
          if (DateUtil.isSameDay(dayDate, now)) {
            dots[idx].completed = ClassTableController.slotFinished(maxStop[idx], now);
          } else {
            dots[idx].completed = dayDate.getTime() < now.getTime();
          }
        }
      }
    }
    return dots;
  }

  /**
   * 某天的日程聚合（课程部分，对应 Dart getArrangementOfDay；M4 将并入考试/实验）。
   * 返回按开始时间升序的 HomeArrangement 列表。
   */
  static getArrangementOfDay(updateTime: Date): HomeArrangement[] {
    const currentWeek: number = ClassTableController.getCurrentWeek(updateTime);
    const classTableData: ClassTableData = ClassTableController.data();
    if (currentWeek < 0 || currentWeek >= classTableData.semesterLength) {
      return [];
    }
    const weekday: number = DateUtil.weekday(updateTime);
    const result: HomeArrangement[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < classTableData.timeArrangement.length; i++) {
      const arrangement: TimeArrangement = classTableData.timeArrangement[i];
      if (arrangement.weekList.length <= currentWeek || !arrangement.weekList[currentWeek]
        || arrangement.day !== weekday) {
        continue;
      }
      const detail = classTableData.getClassDetail(arrangement);
      const startIndex: number = (arrangement.start - 1) * 2;
      const stopIndex: number = (arrangement.stop - 1) * 2 + 1;
      if (startIndex < 0 || stopIndex >= TIME_LIST.length) {
        continue;
      }
      const startTime: string = `${DateUtil.formatFull(updateTime).substring(0, 11)}${TIME_LIST[startIndex]}:00`;
      const endTime: string = `${DateUtil.formatFull(updateTime).substring(0, 11)}${TIME_LIST[stopIndex]}:00`;
      const item: HomeArrangement = new HomeArrangement(
        detail.name, startTime, endTime, arrangement.teacher, arrangement.classroom, '',
        classTableData.colorIndex(arrangement));
      const key: string = `${item.name}|${item.startTimeStr}|${item.endTimeStr}|${item.place}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      result.push(item);
    }
    result.sort(compareHomeArrangement);
    return result;
  }
}
