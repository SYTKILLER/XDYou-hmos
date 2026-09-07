import { DateUtil } from '../../utils/date/DateUtil';

/**
 * 考试安排模型（对应 Dart model/xidian_ids/exam.dart）。
 * 时间串解析失败（无法参加/未安排时间）时 startTimeStr/endTimeStr 置 "cancel_exam"（照搬原版哨兵值）。
 */
export class Subject {
  subject: string;
  typeStr: string;
  startTimeStr: string;
  endTimeStr: string;
  time: string;
  place: string;
  seat: string;

  constructor(subject: string, typeStr: string, startTimeStr: string, endTimeStr: string,
    time: string, place: string, seat: string) {
    this.subject = subject;
    this.typeStr = typeStr;
    this.startTimeStr = startTimeStr;
    this.endTimeStr = endTimeStr;
    this.time = time;
    this.place = place;
    this.seat = seat;
  }

  // 正则照搬 Dart（命名组改为编号组：ArkTS 禁字符串下标访问 groups）。
  // 本科 "2025-1-10 14:00-16:00"：[1]年[2]月[3]日[4]时[6]分[7]止时[9]止分
  private static readonly UNDER_RE: RegExp =
    /^(\d+)-(\d+)-(\d+) (\d+)(::?)(\d+)-(\d+)(::?)(\d+)/;
  // 研究生 "2025-01-10 星期五(14:00-16:00)"：[1]年[2]月[3]日[5]时[7]分[8]止时[10]止分
  private static readonly POST_RE: RegExp =
    /^(\d{4})-(\d{2})-(\d{2}) (.{3})\((\d{2})(::?)(\d{2})-(\d{2})(::?)(\d{2})\)/;

  /** [年,月,日,时,分,止时,止分]；两个正则都不匹配返回 null。 */
  private static matchTime(time: string): number[] | null {
    let m: RegExpExecArray | null = Subject.UNDER_RE.exec(time);
    if (m !== null) {
      return [Number(m[1]), Number(m[2]), Number(m[3]), Number(m[4]), Number(m[6]), Number(m[7]), Number(m[9])];
    }
    m = Subject.POST_RE.exec(time);
    if (m !== null) {
      return [Number(m[1]), Number(m[2]), Number(m[3]), Number(m[5]), Number(m[7]), Number(m[8]), Number(m[10])];
    }
    return null;
  }

  /** 考试类型归类（对应 Dart type getter）。 */
  type(): string {
    if (this.typeStr.includes('期末考试')) {
      return '期末考试';
    }
    if (this.typeStr.includes('期中考试')) {
      return '期中考试';
    }
    if (this.typeStr.includes('结课考试')) {
      return '结课考试';
    }
    if (this.typeStr.includes('入学')) {
      return '入学考试';
    }
    return this.typeStr;
  }

  startTime(): Date | null {
    return DateUtil.parseDateTime(this.startTimeStr);
  }

  stopTime(): Date | null {
    return DateUtil.parseDateTime(this.endTimeStr);
  }

  static generate(subject: string, typeStr: string, time: string, place: string, seat: string): Subject {
    const s: Subject = new Subject(subject, typeStr, '', '', time, place, seat);
    const parts: number[] | null = Subject.matchTime(time);
    if (parts !== null) {
      const start: Date = new Date(parts[0], parts[1] - 1, parts[2], parts[3], parts[4]);
      const stop: Date = new Date(parts[0], parts[1] - 1, parts[2], parts[5], parts[6]);
      s.startTimeStr = DateUtil.formatFull(start);
      s.endTimeStr = DateUtil.formatFull(stop);
    } else {
      s.startTimeStr = 'cancel_exam';
      s.endTimeStr = 'cancel_exam';
    }
    return s;
  }
}

/** 已选课但考试尚未安排的课程（对应 Dart ToBeArranged）。 */
export class ToBeArranged {
  subject: string;
  id: string;

  constructor(subject: string, id: string) {
    this.subject = subject;
    this.id = id;
  }
}

export class ExamData {
  subject: Subject[] = [];
  toBeArranged: ToBeArranged[] = [];

  static fromCacheJson(p: ExamDataJson): ExamData {
    const data: ExamData = new ExamData();
    const subjects: SubjectJson[] = p.subject !== undefined ? p.subject : [];
    subjects.forEach((s: SubjectJson): void => {
      data.subject.push(new Subject(
        s.subject ?? '', s.typeStr ?? '', s.startTimeStr ?? '', s.endTimeStr ?? '',
        s.time ?? '', s.place ?? '', s.seat ?? ''));
    });
    const tba: ToBeArrangedJson[] = p.toBeArranged !== undefined ? p.toBeArranged : [];
    tba.forEach((t: ToBeArrangedJson): void => {
      data.toBeArranged.push(new ToBeArranged(t.subject ?? '', t.id ?? ''));
    });
    return data;
  }

  toCacheJson(): ExamDataJson {
    const subjects: SubjectJson[] = [];
    this.subject.forEach((s: Subject): void => {
      subjects.push({
        subject: s.subject, typeStr: s.typeStr, startTimeStr: s.startTimeStr, endTimeStr: s.endTimeStr,
        time: s.time, place: s.place, seat: s.seat
      });
    });
    const tba: ToBeArrangedJson[] = [];
    this.toBeArranged.forEach((t: ToBeArranged): void => {
      tba.push({ subject: t.subject, id: t.id });
    });
    return { subject: subjects, toBeArranged: tba };
  }
}

// ---- 缓存 JSON 形状（与 Dart json_serializable 输出一致） ----

interface SubjectJson {
  subject?: string;
  typeStr?: string;
  startTimeStr?: string;
  endTimeStr?: string;
  time?: string;
  place?: string;
  seat?: string;
}

interface ToBeArrangedJson {
  subject?: string;
  id?: string;
}

export interface ExamDataJson {
  subject?: SubjectJson[];
  toBeArranged?: ToBeArrangedJson[];
}
