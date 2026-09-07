import { DateUtil } from '../utils/date/DateUtil';

/**
 * 首页日程聚合条目（对应 Dart model/home_arrangement.dart）。
 * 课程 / 考试 / 实验等统一转成本模型进首页日程卡；时间格式 "yyyy-MM-dd HH:mm:ss"。
 */
export class HomeArrangement {
  /** 条目类型：'course' 课程 / 'exam' 考试（后续实验并入再加 'experiment'）。 */
  type: string;
  name: string;
  teacher: string;
  place: string;
  seat: string;
  colorIndex: number;
  startTimeStr: string;
  endTimeStr: string;

  constructor(name: string, startTimeStr: string, endTimeStr: string, teacher: string = '',
    place: string = '', seat: string = '', colorIndex: number = -1, type: string = 'course') {
    this.type = type;
    this.name = name;
    this.teacher = teacher;
    this.place = place;
    this.seat = seat;
    this.colorIndex = colorIndex;
    this.startTimeStr = startTimeStr;
    this.endTimeStr = endTimeStr;
  }

  startTime(): Date {
    const parsed: Date | null = DateUtil.parseDateTime(this.startTimeStr);
    return parsed !== null ? parsed : new Date(0);
  }

  endTime(): Date {
    const parsed: Date | null = DateUtil.parseDateTime(this.endTimeStr);
    return parsed !== null ? parsed : new Date(0);
  }
}

/** 按开始时间升序（对应 Dart Comparable 实现）。 */
export function compareHomeArrangement(a: HomeArrangement, b: HomeArrangement): number {
  return a.startTime().getTime() - b.startTime().getTime();
}
