import { SportSession, SportCredentialError } from '../service/sport/SportSession';
import { SportClassItem, SportScore } from '../model/sport/SportModels';
import { FetchResult } from '../model/FetchResult';
import { Log } from '../utils/Log';

/**
 * 体育信息控制器（对应 Dart 仅内存缓存：_scoreCache/_classCache）。
 * score/class 各自 inflight 去重；成功后 bump sportVersion 通知页面。
 */
export class SportController {
  private static scoreResult: FetchResult<SportScore> | null = null;
  private static scoreInflight: Promise<void> | null = null;
  private static classResult: FetchResult<SportClassItem[]> | null = null;
  private static classInflight: Promise<void> | null = null;

  static hasScore(): boolean {
    return SportController.scoreResult !== null;
  }

  static score(): SportScore | null {
    const r: FetchResult<SportScore> | null = SportController.scoreResult;
    return r !== null ? r.data : null;
  }

  static scoreIsCache(): boolean {
    const r: FetchResult<SportScore> | null = SportController.scoreResult;
    return r !== null && r.isCache;
  }

  static scoreHint(): string {
    const r: FetchResult<SportScore> | null = SportController.scoreResult;
    return r !== null ? r.hintKey : '';
  }

  static hasClass(): boolean {
    return SportController.classResult !== null;
  }

  static classData(): SportClassItem[] {
    const r: FetchResult<SportClassItem[]> | null = SportController.classResult;
    return r !== null ? r.data : [];
  }

  static classIsCache(): boolean {
    const r: FetchResult<SportClassItem[]> | null = SportController.classResult;
    return r !== null && r.isCache;
  }

  static classHint(): string {
    const r: FetchResult<SportClassItem[]> | null = SportController.classResult;
    return r !== null ? r.hintKey : '';
  }

  private static bumpVersion(): void {
    AppStorage.setOrCreate('sportVersion', (AppStorage.get<number>('sportVersion') ?? 0) + 1);
  }

  static refreshScore(): Promise<void> {
    if (SportController.scoreInflight !== null) {
      return SportController.scoreInflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        SportController.scoreResult = await SportSession.getScore();
        SportController.bumpVersion();
      } catch (e) {
        if (e instanceof SportCredentialError) {
          throw e;
        }
        if (SportController.scoreResult !== null) {
          SportController.bumpVersion();
          return;
        }
        Log.warn(`sport refreshScore failed: ${e}`);
        throw e instanceof Error ? e : new Error(`${e}`);
      } finally {
        SportController.scoreInflight = null;
      }
    })();
    SportController.scoreInflight = task;
    return task;
  }

  static refreshClass(): Promise<void> {
    if (SportController.classInflight !== null) {
      return SportController.classInflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        SportController.classResult = await SportSession.getClass();
        SportController.bumpVersion();
      } catch (e) {
        if (e instanceof SportCredentialError) {
          throw e;
        }
        if (SportController.classResult !== null) {
          SportController.bumpVersion();
          return;
        }
        Log.warn(`sport refreshClass failed: ${e}`);
        throw e instanceof Error ? e : new Error(`${e}`);
      } finally {
        SportController.classInflight = null;
      }
    })();
    SportController.classInflight = task;
    return task;
  }
}
