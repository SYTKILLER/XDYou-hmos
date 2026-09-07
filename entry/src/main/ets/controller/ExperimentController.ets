import { ExperimentSession } from '../service/experiment/ExperimentSession';
import { OtherExperimentSession } from '../service/experiment/OtherExperimentSession';
import { PreferenceService } from '../service/preference/PreferenceService';
import { ExperimentData } from '../model/experiment/ExperimentData';
import { FetchResult } from '../model/FetchResult';
import { Log } from '../utils/Log';

/**
 * 实验信息控制器：物理实验（独立密码）+ 其他实验（复用 IDS）双源并行，各自文件缓存。
 * experimentVersion 通知页面；物理源密码缺失以 errorMsg='实验平台密码未配置' 体现。
 */
export class ExperimentController {
  private static physicsResult: FetchResult<ExperimentData[]> | null = null;
  private static physicsInflight: Promise<void> | null = null;
  private static otherResult: FetchResult<ExperimentData[]> | null = null;
  private static otherInflight: Promise<void> | null = null;

  static physicsData(): ExperimentData[] {
    const r: FetchResult<ExperimentData[]> | null = ExperimentController.physicsResult;
    return r !== null ? r.data : [];
  }

  static otherData(): ExperimentData[] {
    const r: FetchResult<ExperimentData[]> | null = ExperimentController.otherResult;
    return r !== null ? r.data : [];
  }

  static physicsFromCache(): boolean {
    const r: FetchResult<ExperimentData[]> | null = ExperimentController.physicsResult;
    return r !== null && r.isCache;
  }

  static otherFromCache(): boolean {
    const r: FetchResult<ExperimentData[]> | null = ExperimentController.otherResult;
    return r !== null && r.isCache;
  }

  static hasAnyData(): boolean {
    return ExperimentController.physicsResult !== null || ExperimentController.otherResult !== null;
  }

  static physicsError: string = '';
  static otherError: string = '';

  private static bumpVersion(): void {
    AppStorage.setOrCreate('experimentVersion', (AppStorage.get<number>('experimentVersion') ?? 0) + 1);
  }

  static refreshPhysics(): Promise<void> {
    if (ExperimentController.physicsInflight !== null) {
      return ExperimentController.physicsInflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        ExperimentController.physicsResult = await ExperimentSession.getDataWithCache();
        ExperimentController.physicsError = '';
      } catch (e) {
        ExperimentController.physicsError = e instanceof Error ? e.message : `${e}`;
        Log.warn(`experiment physics failed: ${e}`);
      } finally {
        ExperimentController.physicsInflight = null;
        ExperimentController.bumpVersion();
      }
    })();
    ExperimentController.physicsInflight = task;
    return task;
  }

  static refreshOther(): Promise<void> {
    if (ExperimentController.otherInflight !== null) {
      return ExperimentController.otherInflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        ExperimentController.otherResult = await OtherExperimentSession.getDataWithCache();
        ExperimentController.otherError = '';
      } catch (e) {
        ExperimentController.otherError = e instanceof Error ? e.message : `${e}`;
        Log.warn(`experiment other failed: ${e}`);
      } finally {
        ExperimentController.otherInflight = null;
        ExperimentController.bumpVersion();
      }
    })();
    ExperimentController.otherInflight = task;
    return task;
  }

  static loadCaches(): void {
    if (ExperimentController.physicsResult === null) {
      const cache: ExperimentData[] = ExperimentSession.getCacheData();
      if (cache.length > 0) {
        ExperimentController.physicsResult =
          FetchResult.cached<ExperimentData[]>(cache, ExperimentSession.cacheFetchTime(), '');
      }
    }
    if (ExperimentController.otherResult === null) {
      const cache: ExperimentData[] = OtherExperimentSession.getCacheData();
      if (cache.length > 0) {
        ExperimentController.otherResult =
          FetchResult.cached<ExperimentData[]>(cache, OtherExperimentSession.cacheFetchTime(), '');
      }
    }
  }

  /** 学期切换事件：删双缓存 + 清实验密码（对齐 Dart SemesterSyncEvent.didChange）。 */
  static onSemesterChanged(): void {
    ExperimentSession.deleteCache();
    OtherExperimentSession.deleteCache();
    PreferenceService.remove('experimentPassword');
  }
}
