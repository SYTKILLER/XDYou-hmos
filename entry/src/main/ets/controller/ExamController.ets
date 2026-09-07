import { ExamSession } from '../service/ids/ExamSession';
import { SemesterController } from './SemesterController';
import { PreferenceService } from '../service/preference/PreferenceService';
import { FetchResult } from '../model/FetchResult';
import { ExamData, Subject, ToBeArranged } from '../model/exam/ExamData';
import { HomeArrangement } from '../model/HomeArrangement';
import { DateUtil } from '../utils/date/DateUtil';
import { Log } from '../utils/Log';

/**
 * 考试控制器（对应 Dart controller/exam_controller.dart 的精简版）。
 * 分组语义照搬：isDisQualified=时间解析失败；isFinished=已开考（含进行中）；isNotFinished=未开考升序。
 * 状态发布：AppStorage 'examVersion' 自增驱动 UI 重建。
 */
export class ExamController {
  private static result: FetchResult<ExamData> | null = null;
  private static inflight: Promise<void> | null = null;

  static loadCache(): void {
    if (ExamController.result !== null) {
      return;
    }
    const cached: ExamData | null = ExamSession.getCacheData();
    if (cached !== null) {
      ExamController.result = FetchResult.cached<ExamData>(cached, ExamSession.cacheFetchTime(), '');
    }
  }

  static hasData(): boolean {
    return ExamController.result !== null;
  }

  static data(): ExamData {
    const r: FetchResult<ExamData> | null = ExamController.result;
    return r !== null ? r.data : new ExamData();
  }

  static isFromCache(): boolean {
    const r: FetchResult<ExamData> | null = ExamController.result;
    return r !== null && r.isCache;
  }

  static fetchTime(): number {
    const r: FetchResult<ExamData> | null = ExamController.result;
    return r !== null ? r.fetchTime : 0;
  }

  /**
   * 拉取考试数据（不含学期同步；首页并行刷新用，学期由调用方先行确保）。
   * 并发调用共享同一 in-flight。
   */
  static refreshData(): Promise<void> {
    if (ExamController.inflight !== null) {
      return ExamController.inflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        const fetchResult: FetchResult<ExamData> = await ExamSession.getExamInfo(
          SemesterController.currentSemester(), PreferenceService.getBool('role', false));
        ExamController.result = fetchResult;
        ExamController.bumpVersion();
      } finally {
        ExamController.inflight = null;
      }
    })();
    ExamController.inflight = task;
    return task;
  }

  /** 页面级全量刷新：确保学期后拉取（失败抛错由调用方呈现）。 */
  static refresh(): Promise<void> {
    return SemesterController.ensureSemester().then((): Promise<void> => ExamController.refreshData());
  }

  private static bumpVersion(): void {
    AppStorage.setOrCreate('examVersion', (AppStorage.get<number>('examVersion') ?? 0) + 1);
  }

  static subjects(): Subject[] {
    return ExamController.data().subject;
  }

  static toBeArranged(): ToBeArranged[] {
    return ExamController.data().toBeArranged;
  }

  /** 时间解析失败（无法确定考试时间）。 */
  static isDisQualified(): Subject[] {
    return ExamController.subjects().filter((s: Subject): boolean => s.startTime() === null || s.stopTime() === null);
  }

  /** 已开考（含进行中，对应 Dart isFinished：startTime <= now）。 */
  static isFinished(now: Date): Subject[] {
    return ExamController.subjects().filter((s: Subject): boolean => {
      const start: Date | null = s.startTime();
      return start !== null && start.getTime() <= now.getTime();
    });
  }

  /** 未开考，按开始时间升序（下一场在前）。 */
  static isNotFinished(now: Date): Subject[] {
    const list: Subject[] = ExamController.subjects().filter((s: Subject): boolean => {
      const start: Date | null = s.startTime();
      return start !== null && start.getTime() > now.getTime();
    });
    list.sort((a: Subject, b: Subject): number => {
      const sa: Date = a.startTime() as Date;
      const sb: Date = b.startTime() as Date;
      return sa.getTime() - sb.getTime();
    });
    return list;
  }

  /**
   * 某天的考试 → 首页日程条目（对应 Dart todayExams/tomorrowExams，M4 首页聚合用）。
   * name 为 "{课程名}考试"，colorIndex 取该科目在列表中的原始下标。
   */
  static examsOfDay(day: Date): HomeArrangement[] {
    const result: HomeArrangement[] = [];
    const subjects: Subject[] = ExamController.subjects();
    for (let i = 0; i < subjects.length; i++) {
      const s: Subject = subjects[i];
      const start: Date | null = s.startTime();
      if (start === null || !DateUtil.isSameDay(start, day)) {
        continue;
      }
      const stop: Date | null = s.stopTime();
      result.push(new HomeArrangement(
        `${s.subject}考试`,
        start !== null ? DateUtil.formatFull(start) : s.startTimeStr,
        stop !== null ? DateUtil.formatFull(stop) : s.endTimeStr,
        '', s.place, s.seat, i, 'exam'
      ));
    }
    return result;
  }
}
