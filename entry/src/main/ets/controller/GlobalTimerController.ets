import { Log } from '../utils/Log';

/**
 * 全局整分定时器（对应 Dart controller/global_timer_controller.dart）：
 * 每次触发后重算到下一个整分的间隔（+100ms）保持对齐，驱动 AppStorage 'nowTick'
 *（毫秒时间戳）——日程卡"结束即切下一条"、21:25 换天等时间相关 UI 全部依赖它重算。
 */
export class GlobalTimerController {
  private static timerId: number = -1;

  /** 登录后主框架出现时启动（幂等）。 */
  static start(): void {
    if (GlobalTimerController.timerId >= 0) {
      return;
    }
    GlobalTimerController.scheduleNext();
    Log.info('GlobalTimer started');
  }

  private static scheduleNext(): void {
    const now: Date = new Date();
    const next: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate(),
      now.getHours(), now.getMinutes() + 1);
    const delay: number = next.getTime() - now.getTime() + 100;
    GlobalTimerController.timerId = setTimeout((): void => {
      AppStorage.setOrCreate('nowTick', Date.now());
      GlobalTimerController.scheduleNext();
    }, delay);
  }

  static stop(): void {
    if (GlobalTimerController.timerId >= 0) {
      clearTimeout(GlobalTimerController.timerId);
      GlobalTimerController.timerId = -1;
    }
  }

  /** 回前台立即补算一次（EntryAbility.onForeground 调用），避免锁屏期间日程显示过期。 */
  static poke(): void {
    AppStorage.setOrCreate('nowTick', Date.now());
  }
}
