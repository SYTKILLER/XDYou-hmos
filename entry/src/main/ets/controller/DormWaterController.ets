import { DormWaterSession } from '../service/dormwater/DormWaterSession';
import { DormWaterDevice } from '../model/dormwater/DormWaterData';
import { Log } from '../utils/Log';

/**
 * 宿舍水机控制器：内存态设备列表（无文件缓存，原版仅内存），dormWaterVersion 通知 UI。
 * 设备页 onShown / 扫码添加 / 登录返回后调用 refreshDevices()。
 */
export class DormWaterController {
  private static devices: DormWaterDevice[] = [];
  private static inflight: Promise<void> | null = null;
  private static loading: boolean = false;
  private static errorMsg: string = '';

  static hasData(): boolean {
    return DormWaterController.devices.length > 0;
  }

  static data(): DormWaterDevice[] {
    return DormWaterController.devices;
  }

  static isLoading(): boolean {
    return DormWaterController.loading;
  }

  static error(): string {
    return DormWaterController.errorMsg;
  }

  static clearError(): void {
    DormWaterController.errorMsg = '';
  }

  private static bumpVersion(): void {
    AppStorage.setOrCreate('dormWaterVersion', (AppStorage.get<number>('dormWaterVersion') ?? 0) + 1);
  }

  /** 拉取设备列表；未登录直接置空并提示（页面负责拉起登录页）。 */
  static refreshDevices(): Promise<void> {
    if (DormWaterController.inflight !== null) {
      return DormWaterController.inflight;
    }
    if (!DormWaterSession.isLoggedIn()) {
      DormWaterController.devices = [];
      DormWaterController.errorMsg = '';
      DormWaterController.bumpVersion();
      return Promise.resolve();
    }
    DormWaterController.loading = true;
    DormWaterController.errorMsg = '';
    DormWaterController.bumpVersion();
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        DormWaterController.devices = await DormWaterSession.getDeviceList();
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : `${e}`;
        DormWaterController.errorMsg = msg;
        Log.warn(`dormWater refreshDevices failed: ${e}`);
      } finally {
        DormWaterController.loading = false;
        DormWaterController.inflight = null;
        DormWaterController.bumpVersion();
      }
    })();
    DormWaterController.inflight = task;
    return task;
  }

  /** 本地移除（收藏取消成功后同步内存列表）。 */
  static removeLocal(deviceId: string): void {
    const index: number = DormWaterController.devices.findIndex((d: DormWaterDevice): boolean => d.id === deviceId);
    if (index >= 0) {
      DormWaterController.devices.splice(index, 1);
      DormWaterController.bumpVersion();
    }
  }

  /** 登录成功后由登录页调用：刷新设置副标题与设备页。 */
  static onLoginStateChanged(): void {
    AppStorage.setOrCreate('settingsVersion', (AppStorage.get<number>('settingsVersion') ?? 0) + 1);
    DormWaterController.bumpVersion();
  }
}
