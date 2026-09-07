import { EnergySession } from '../service/ids/EnergySession';
import { PreferenceService } from '../service/preference/PreferenceService';
import { FetchResult } from '../model/FetchResult';
import { EnergyInfo, ElectricityHistoryInfo } from '../model/energy/EnergyData';
import { DateUtil } from '../utils/date/DateUtil';
import { Log } from '../utils/Log';

/**
 * 电费控制器（对应 Dart controller/energy_controller.dart）。
 * 本地余量历史语义照搬：fresh 结果且与上一条不同日才追加，最多保留 15 条；
 * 低电量阈值默认 20 度（可在偏好关闭），M6 仅用于页面告警展示，提醒推送后置。
 */
export class EnergyController {
  static readonly DEFAULT_LOW_ELECTRICITY_WARNING_THRESHOLD: number = 20;

  private static result: FetchResult<EnergyInfo> | null = null;
  private static inflight: Promise<void> | null = null;
  private static history: ElectricityHistoryInfo[] = [];

  static loadCache(): void {
    if (EnergyController.result !== null) {
      return;
    }
    const cached: EnergyInfo | null = EnergySession.getCacheData();
    if (cached !== null) {
      EnergyController.result =
        FetchResult.cached<EnergyInfo>(cached, EnergySession.cacheFetchTime(), '');
    }
    EnergyController.history = EnergySession.getHistory();
  }

  static hasData(): boolean {
    return EnergyController.result !== null;
  }

  static data(): EnergyInfo | null {
    const r: FetchResult<EnergyInfo> | null = EnergyController.result;
    return r !== null ? r.data : null;
  }

  static isFromCache(): boolean {
    const r: FetchResult<EnergyInfo> | null = EnergyController.result;
    return r !== null && r.isCache;
  }

  static fetchTime(): number {
    const r: FetchResult<EnergyInfo> | null = EnergyController.result;
    return r !== null ? r.fetchTime : 0;
  }

  static historyList(): ElectricityHistoryInfo[] {
    return EnergyController.history;
  }

  static clearHistory(): void {
    EnergySession.clearHistory();
    EnergyController.history = [];
    AppStorage.setOrCreate('energyVersion', (AppStorage.get<number>('energyVersion') ?? 0) + 1);
  }

  static lowThreshold(): number {
    const enabled: boolean = PreferenceService.getBool('lowElectricityWarningEnabled', true);
    if (!enabled) {
      return -1;
    }
    const threshold: number = PreferenceService.getNumber('lowElectricityWarningThreshold', 0);
    return threshold > 0 ? threshold : EnergyController.DEFAULT_LOW_ELECTRICITY_WARNING_THRESHOLD;
  }

  /** fresh 结果同步本地历史（同日去重、上限 15 条，照搬 Dart _syncLastValidElectricity）。 */
  private static syncHistory(result: FetchResult<EnergyInfo>): void {
    if (result.isCache) {
      return;
    }
    const info: EnergyInfo = result.data;
    if (EnergyController.history.length > 0) {
      const last: ElectricityHistoryInfo = EnergyController.history[EnergyController.history.length - 1];
      if (DateUtil.isSameDay(last.fetchDay, info.lastReadDate)) {
        return;
      }
    }
    const next: ElectricityHistoryInfo[] = EnergyController.history.slice();
    if (next.length > 14) {
      next.shift();
    }
    next.push(new ElectricityHistoryInfo(info.lastReadDate, `${info.electricityRemain}`));
    EnergySession.saveHistory(next);
    EnergyController.history = next;
  }

  /** 拉取电费（不依赖学期；失败回退缓存，错误含"仅校园网可用"语义）。 */
  static refreshData(): Promise<void> {
    if (EnergyController.inflight !== null) {
      return EnergyController.inflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        const fetchResult: FetchResult<EnergyInfo> = await EnergySession.getElectricityInfo();
        EnergyController.result = fetchResult;
        EnergyController.syncHistory(fetchResult);
        AppStorage.setOrCreate('energyVersion', (AppStorage.get<number>('energyVersion') ?? 0) + 1);
      } finally {
        EnergyController.inflight = null;
      }
    })();
    EnergyController.inflight = task;
    return task;
  }
}
