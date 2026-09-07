import { ClassTableController } from './ClassTableController';
import { ExamController } from './ExamController';
import { SemesterController } from './SemesterController';
import { EnergyController } from './EnergyController';
import { LibraryController } from './LibraryController';
import { SchoolnetController } from './SchoolnetController';
import { IdsSession } from '../service/ids/IdsSession';
import { backgroundSliderHandler } from '../service/ids/BackgroundSlider';
import { HomeArrangement, compareHomeArrangement } from '../model/HomeArrangement';
import { DateUtil } from '../utils/date/DateUtil';
import { Log } from '../utils/Log';

/** 首页日程视图模型：targetDay 为日程所属日（21:25 后为明天），items 已过滤已结束。 */
export interface HomepageSchedule {
  isTomorrow: boolean;
  targetDay: Date;
  items: HomeArrangement[];
}

/**
 * 首页聚合控制器（对应 Dart controller/homepage_controller.dart 的 M4 范围）。
 * 日程聚合 = 课程表 + 考试（自定义事项/物理实验/其他实验随后续里程碑并入）；
 * 换天阈值与过滤语义照搬：21:25 后展示明天；今天列表过滤 endTime ≤ now（结束即切下一条）。
 */
export class HomepageController {
  /** 21:25（分钟数），对应 Dart isTomorrowComputedSignal。 */
  static readonly TOMORROW_SWITCH_MINUTES: number = 21 * 60 + 25;

  private static inflight: Promise<void> | null = null;
  /** 角色重判定每进程一次（冷启动自愈历史版本误存的 role 偏好）。 */
  private static roleRechecked: boolean = false;

  static isTomorrow(now: Date): boolean {
    return now.getHours() * 60 + now.getMinutes() > HomepageController.TOMORROW_SWITCH_MINUTES;
  }

  /** 某天完整日程（课程+考试），按开始时间升序。 */
  static arrangementOfDay(day: Date): HomeArrangement[] {
    const list: HomeArrangement[] = [];
    ClassTableController.getArrangementOfDay(day).forEach((a: HomeArrangement): void => {
      list.push(a);
    });
    ExamController.examsOfDay(day).forEach((a: HomeArrangement): void => {
      list.push(a);
    });
    list.sort(compareHomeArrangement);
    return list;
  }

  /** 当前应展示的日程：21:25 后为明天（不过滤），今天过滤已结束。 */
  static currentSchedule(now: Date): HomepageSchedule {
    const isTomorrow: boolean = HomepageController.isTomorrow(now);
    const targetDay: Date =
      new Date(now.getTime() + (isTomorrow ? 1 : 0) * DateUtil.MS_PER_DAY);
    const all: HomeArrangement[] = HomepageController.arrangementOfDay(targetDay);
    const items: HomeArrangement[] = [];
    if (isTomorrow) {
      return { isTomorrow: isTomorrow, targetDay: targetDay, items: all };
    }
    for (let i = 0; i < all.length; i++) {
      if (all[i].endTime().getTime() <= now.getTime()) {
        continue;
      }
      items.push(all[i]);
    }
    return { isTomorrow: isTomorrow, targetDay: targetDay, items: items };
  }

  /** 卡片头文案（对应 Dart "今天还有 N 件事/明天有 N 件事/今天已结束"）。 */
  static scheduleTitle(now: Date): string {
    const schedule: HomepageSchedule = HomepageController.currentSchedule(now);
    if (schedule.isTomorrow) {
      return `明天有 ${schedule.items.length} 件事`;
    }
    if (schedule.items.length > 0) {
      return `今天还有 ${schedule.items.length} 件事`;
    }
    return '今天已结束';
  }

  /**
   * 全量刷新：学期一次 → 课表/考试/电费/图书/校园网并行；单源失败不阻断另一源
   * （allSettled，失败记日志，由各控制器缓存/错误态呈现）。并发调用共享同一 in-flight。
   * 校园网瓦片取 rad_user_info（免登录态、校外可达，成功后快照落盘供冷启动直读）；
   * zfw 自助用量需验证码交互，仅由校园网页面拉取。
   */
  static refreshAll(): Promise<void> {
    if (HomepageController.inflight !== null) {
      return HomepageController.inflight;
    }
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        if (!HomepageController.roleRechecked) {
          HomepageController.roleRechecked = true;
          try {
            // 旧版本曾把"res 存在但为 null"误判为研究生写入偏好，冷启动重判定纠正。
            await IdsSession.checkWhetherPostgraduate(backgroundSliderHandler());
          } catch (e) {
            Log.warn(`role recheck skipped: ${e}`);
          }
        }
        await SemesterController.ensureSemester();
        const results: PromiseSettledResult<void>[] = await Promise.allSettled([
          ClassTableController.refreshData(),
          ExamController.refreshData(),
          EnergyController.refreshData(),
          LibraryController.refreshBorrowList(),
          SchoolnetController.refreshUserInfo()
        ]);
        for (let i = 0; i < results.length; i++) {
          const r: PromiseSettledResult<void> = results[i];
          if (r.status === 'rejected') {
            Log.warn(`homepage refresh source[${i}] failed: ${r.reason}`);
          }
        }
        AppStorage.setOrCreate('homepageVersion', (AppStorage.get<number>('homepageVersion') ?? 0) + 1);
      } finally {
        HomepageController.inflight = null;
      }
    })();
    HomepageController.inflight = task;
    return task;
  }
}
