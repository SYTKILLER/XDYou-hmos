import { SemesterSession } from '../service/ids/SemesterSession';
import { ClassTableSession } from '../service/ids/ClassTableSession';
import { ExamSession } from '../service/ids/ExamSession';
import { ExperimentController } from './ExperimentController';
import { PreferenceService } from '../service/preference/PreferenceService';
import { Log } from '../utils/Log';

/**
 * 学期控制器（对应 Dart SemesterController 的精简版）：
 * 拉取远端学期，与本地"较新"者生效；学期变更时清空课表缓存（对应 Dart SemesterSyncEvent.didChange）。
 * 学期代码形如 "2025-2026-1"。
 */
export class SemesterController {
  static readonly SEMESTER_KEY: string = 'currentSemester';

  static currentSemester(): string {
    return PreferenceService.getString(SemesterController.SEMESTER_KEY, '');
  }

  private static inflight: Promise<void> | null = null;

  /**
   * 确保学期信息就绪：按角色拉取远端学期并与本地比较。
   * 远端更新 → 存储并清课表/考试缓存；本地较新（用户手动切学期，M5 提供 UI）→ 保留本地。
   * 并发调用共享同一 in-flight。
   */
  static ensureSemester(): Promise<void> {
    if (SemesterController.inflight !== null) {
      return SemesterController.inflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        await SemesterController.doEnsureSemester();
      } finally {
        SemesterController.inflight = null;
      }
    })();
    SemesterController.inflight = task;
    return task;
  }

  private static async doEnsureSemester(): Promise<void> {
    const isPostgraduate: boolean = PreferenceService.getBool('role', false);
    const remote: string = isPostgraduate
      ? await SemesterSession.getSemesterInfoYjspt()
      : await SemesterSession.getSemesterInfoEhall();
    if (remote.length === 0) {
      return;
    }
    const local: string = SemesterController.currentSemester();
    if (local.length === 0) {
      PreferenceService.putString(SemesterController.SEMESTER_KEY, remote);
      Log.info(`[SemesterController] semester initialized: ${remote}`);
      return;
    }
    if (SemesterController.compareSemester(remote, local) > 0) {
      PreferenceService.putString(SemesterController.SEMESTER_KEY, remote);
      ClassTableSession.deleteCache();
      ExamSession.deleteCache();
      ExperimentController.onSemesterChanged();
      Log.info(`[SemesterController] semester changed ${local} -> ${remote}, caches cleared`);
    }
  }

  /** 对应 Dart parseSemesterCodeToInt：去掉 '-' 后按数值比较。 */
  static compareSemester(a: string, b: string): number {
    const ia: number = Number(a.replace(/-/g, ''));
    const ib: number = Number(b.replace(/-/g, ''));
    if (isNaN(ia) || isNaN(ib)) {
      return 0;
    }
    return ia - ib;
  }
}
