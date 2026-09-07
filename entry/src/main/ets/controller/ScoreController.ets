import { ScoreSession } from '../service/ids/ScoreSession';
import { PreferenceService } from '../service/preference/PreferenceService';
import { FetchResult } from '../model/FetchResult';
import { Score, ComposeDetail } from '../model/score/ScoreData';
import { Log } from '../utils/Log';

/** 汇总统计视图（对应 Dart bottomInfo：已选/学分/平均分/绩点；M6 为全部口径）。 */
export interface ScoreSummary {
  count: number;
  credit: number;
  avg: number;
  gpa: number;
}

/**
 * 成绩控制器（对应 Dart page/score/score_state.dart 的统计部分，M6 精简为"全部"口径）。
 * 统计排除规则照搬 _evalCount：CET-4/6、未出分、失败且无分、重修重考失败。
 * 勾选课程自定义统计（isSelected 模式）后置迭代。
 */
export class ScoreController {
  private static result: FetchResult<Score[]> | null = null;
  private static inflight: Promise<void> | null = null;
  /** 详情弹窗当前目标（CustomDialog 参数桥）。 */
  static detailTarget: Score | null = null;

  static loadCache(): void {
    if (ScoreController.result !== null) {
      return;
    }
    const cached: Score[] = ScoreSession.getCacheData();
    if (cached.length > 0) {
      ScoreController.result =
        FetchResult.cached<Score[]>(cached, ScoreSession.cacheFetchTime(), '');
    }
  }

  static hasData(): boolean {
    return ScoreController.result !== null;
  }

  static data(): Score[] {
    const r: FetchResult<Score[]> | null = ScoreController.result;
    return r !== null ? r.data : [];
  }

  static isFromCache(): boolean {
    const r: FetchResult<Score[]> | null = ScoreController.result;
    return r !== null && r.isCache;
  }

  static fetchTime(): number {
    const r: FetchResult<Score[]> | null = ScoreController.result;
    return r !== null ? r.fetchTime : 0;
  }

  /** 拉取成绩（不含学期同步；成绩不随学期切换清缓存——历史成绩持续累计）。 */
  static refreshData(): Promise<void> {
    if (ScoreController.inflight !== null) {
      return ScoreController.inflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        const fetchResult: FetchResult<Score[]> =
          await ScoreSession.getScore(PreferenceService.getBool('role', false));
        ScoreController.result = fetchResult;
        AppStorage.setOrCreate('scoreVersion', (AppStorage.get<number>('scoreVersion') ?? 0) + 1);
      } finally {
        ScoreController.inflight = null;
      }
    })();
    ScoreController.inflight = task;
    return task;
  }

  static refresh(): Promise<void> {
    return ScoreController.refreshData();
  }

  /** 学期列表（按数据出现顺序去重，服务端已按学期升序）。 */
  static semesters(): string[] {
    const semesters: string[] = [];
    ScoreController.data().forEach((s: Score): void => {
      if (s.semesterCode.length > 0 && !semesters.includes(s.semesterCode)) {
        semesters.push(s.semesterCode);
      }
    });
    return semesters;
  }

  /** 统计口径过滤（照搬 Dart _evalCount）。 */
  private static evalCount(s: Score): boolean {
    if (s.name.includes('国家英语四级') || s.name.includes('国家英语六级')) {
      return false;
    }
    if (!s.isFinish()) {
      return false;
    }
    const passed: boolean = s.isPassed() as boolean;
    if (!passed && s.score === null) {
      return false;
    }
    if (s.scoreStatus !== '初修' && !passed) {
      return false;
    }
    return true;
  }

  /** 总学分（全部口径，对应 Dart evalCredit(isAll=true)）。 */
  static evalCredit(): number {
    let total: number = 0;
    ScoreController.data().forEach((s: Score): void => {
      if (ScoreController.evalCount(s)) {
        total += s.credit;
      }
    });
    return total;
  }

  /** 平均分/平均绩点（学分加权，全部口径，对应 Dart evalAvg）。 */
  static evalAvg(isGPA: boolean): number {
    const totalCredit: number = ScoreController.evalCredit();
    let totalScore: number = 0;
    ScoreController.data().forEach((s: Score): void => {
      if (!ScoreController.evalCount(s)) {
        return;
      }
      if (isGPA) {
        totalScore += s.gpa() * s.credit;
      } else if (s.score !== null) {
        totalScore += s.score * s.credit;
      }
    });
    return totalCredit !== 0 ? totalScore / totalCredit : 0.0;
  }

  static summary(): ScoreSummary {
    return {
      count: ScoreController.data().filter((s: Score): boolean => ScoreController.evalCount(s)).length,
      credit: ScoreController.evalCredit(),
      avg: ScoreController.evalAvg(false),
      gpa: ScoreController.evalAvg(true)
    };
  }

  /** 单科成绩组成（needRelogin=缓存回退时需续登，对应 Dart getScoreComposeInfo）。 */
  static getDetail(score: Score): Promise<ComposeDetail[]> {
    return ScoreSession.getDetail(score.classID, score.semesterCode, ScoreController.isFromCache());
  }
}
