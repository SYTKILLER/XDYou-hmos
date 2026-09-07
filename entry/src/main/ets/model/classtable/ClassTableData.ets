/**
 * 课程表数据模型（对应 Dart model/xidian_ids/classtable.dart）。
 * 缓存 JSON 字段名与 Dart json_serializable 输出保持一致（week_list / source 枚举字符串），
 * 便于对照与人工排查。
 */

/** 排课来源：empty=未排课占位，school=教务系统。 */
export enum ClassSource {
  Empty = 'empty',
  School = 'school'
}

/** 调课类型：change=调课，stop=停课，patch=补课。 */
export enum ChangeType {
  Change = 'change',
  Stop = 'stop',
  Patch = 'patch'
}

export class ClassDetail {
  name: string;
  code: string;
  number: string;

  constructor(name: string, code: string = '', number: string = '') {
    this.name = name;
    this.code = code;
    this.number = number;
  }

  /** Dart == 仅比较 name（同课程名视为同一课程）。 */
  equalsByName(other: ClassDetail): boolean {
    return this.name === other.name;
  }
}

export class NotArrangementClassDetail {
  name: string;
  code: string;
  number: string;
  teacher: string;

  constructor(name: string, code: string = '', number: string = '', teacher: string = '') {
    this.name = name;
    this.code = code;
    this.number = number;
    this.teacher = teacher;
  }
}

/** 一条排课：index 指向 ClassDetail，weekList 为 01 串解析出的布尔周次。 */
export class TimeArrangement {
  index: number;
  weekList: boolean[];
  teacher: string;
  day: number;
  start: number;
  stop: number;
  source: ClassSource;
  classroom: string;

  constructor(source: ClassSource, index: number, weekList: boolean[], day: number, start: number, stop: number,
    teacher: string = '', classroom: string = '') {
    this.source = source;
    this.index = index;
    this.weekList = weekList;
    this.teacher = teacher;
    this.day = day;
    this.start = start;
    this.stop = stop;
    this.classroom = classroom;
  }

  step(): number {
    return this.stop - this.start;
  }
}

/** 调/停/补课单条记录（对应 Dart ClassChange；originalWeek/newWeek 的 -1 对应 Dart null）。 */
export class ClassChange {
  type: ChangeType;
  classCode: string;
  classNumber: string;
  className: string;
  originalAffectedWeeks: boolean[] | null;
  newAffectedWeeks: boolean[] | null;
  originalTeacherData: string;
  newTeacherData: string;
  originalClassRange: number[];
  newClassRange: number[];
  originalWeek: number;
  newWeek: number;
  originalClassroom: string;
  newClassroom: string;

  constructor(type: ChangeType, classCode: string, classNumber: string, className: string,
    originalAffectedWeeks: boolean[] | null, newAffectedWeeks: boolean[] | null,
    originalTeacherData: string, newTeacherData: string,
    originalClassRange: number[], newClassRange: number[],
    originalWeek: number, newWeek: number, originalClassroom: string, newClassroom: string) {
    this.type = type;
    this.classCode = classCode;
    this.classNumber = classNumber;
    this.className = className;
    this.originalAffectedWeeks = originalAffectedWeeks;
    this.newAffectedWeeks = newAffectedWeeks;
    this.originalTeacherData = originalTeacherData;
    this.newTeacherData = newTeacherData;
    this.originalClassRange = originalClassRange;
    this.newClassRange = newClassRange;
    this.originalWeek = originalWeek;
    this.newWeek = newWeek;
    this.originalClassroom = originalClassroom;
    this.newClassroom = newClassroom;
  }

  /** 原/新周次中为 true 的下标列表（Dart originalAffectedWeeksList / newAffectedWeeksList）。 */
  originalAffectedWeeksList(): number[] {
    return ClassChange.trueIndices(this.originalAffectedWeeks);
  }

  newAffectedWeeksList(): number[] {
    return ClassChange.trueIndices(this.newAffectedWeeks);
  }

  private static trueIndices(weeks: boolean[] | null): number[] {
    const result: number[] = [];
    if (weeks !== null) {
      for (let i = 0; i < weeks.length; i++) {
        if (weeks[i]) {
          result.push(i);
        }
      }
    }
    return result;
  }

  /** 去掉教师工号中的字母/数字/斜杠，仅留中文名（正则字符类照搬 Dart 原文含 [A-z] 笔误）。 */
  originalTeacher(): string {
    return this.originalTeacherData.replace(/(\/|[0-9a-zA-z])/g, '');
  }

  newTeacher(): string {
    return this.newTeacherData.replace(/(\/|[0-9a-zA-z])/g, '');
  }

  /** 教师是否更换：比较双方含数字的工号段（Dart isTeacherChanged）。 */
  isTeacherChanged(): boolean {
    const originalCodes: string[] = ClassChange.teacherCodes(this.originalTeacherData);
    const newCodes: string[] = ClassChange.teacherCodes(this.newTeacherData);
    if (originalCodes.length !== newCodes.length) {
      return true;
    }
    for (let i = 0; i < originalCodes.length; i++) {
      if (originalCodes[i] !== newCodes[i]) {
        return true;
      }
    }
    return false;
  }

  private static teacherCodes(raw: string): string[] {
    const parts: string[] = raw.replace(/ /g, '').split(/,|\//);
    const codes: string[] = [];
    parts.forEach((part: string): void => {
      if (/[0-9]/.test(part)) {
        codes.push(part);
      }
    });
    return codes;
  }
}

// ---- 缓存 JSON 形状（与 Dart json_serializable 输出一致） ----

export interface ClassDetailJson {
  name?: string;
  code?: string;
  number?: string;
}

export interface NotArrangedJson {
  name?: string;
  code?: string;
  number?: string;
  teacher?: string;
}

export interface TimeArrangementJson {
  index?: number;
  week_list?: boolean[];
  teacher?: string;
  day?: number;
  start?: number;
  stop?: number;
  source?: string;
  classroom?: string;
}

export interface ClassChangeJson {
  type?: string;
  classCode?: string;
  classNumber?: string;
  className?: string;
  originalAffectedWeeks?: boolean[] | null;
  newAffectedWeeks?: boolean[] | null;
  originalTeacherData?: string;
  newTeacherData?: string;
  originalClassRange?: number[];
  newClassRange?: number[];
  originalWeek?: number | null;
  newWeek?: number | null;
  originalClassroom?: string;
  newClassroom?: string;
}

export interface ClassTableJson {
  semesterLength?: number;
  semesterCode?: string;
  termStartDay?: string;
  classDetail?: ClassDetailJson[];
  notArranged?: NotArrangedJson[];
  timeArrangement?: TimeArrangementJson[];
  classChanges?: ClassChangeJson[];
}

export class ClassTableData {
  semesterLength: number = 1;
  semesterCode: string = '';
  termStartDay: string = '';
  classDetail: ClassDetail[] = [];
  notArranged: NotArrangementClassDetail[] = [];
  timeArrangement: TimeArrangement[] = [];
  classChanges: ClassChange[] = [];

  /** 仅 source=school 的排课可查（对应 Dart getClassDetail）。 */
  getClassDetail(t: TimeArrangement): ClassDetail {
    if (t.index >= 0 && t.index < this.classDetail.length) {
      return this.classDetail[t.index];
    }
    return new ClassDetail('');
  }

  colorIndex(t: TimeArrangement): number {
    const detail: ClassDetail = this.getClassDetail(t);
    for (let i = 0; i < this.classDetail.length; i++) {
      if (this.classDetail[i] === detail) {
        return i;
      }
    }
    return 0;
  }

  toCacheJson(): ClassTableJson {
    const details: ClassDetailJson[] = [];
    this.classDetail.forEach((c: ClassDetail): void => {
      details.push({ name: c.name, code: c.code, number: c.number });
    });
    const notArranged: NotArrangedJson[] = [];
    this.notArranged.forEach((c: NotArrangementClassDetail): void => {
      notArranged.push({ name: c.name, code: c.code, number: c.number, teacher: c.teacher });
    });
    const times: TimeArrangementJson[] = [];
    this.timeArrangement.forEach((t: TimeArrangement): void => {
      times.push({
        index: t.index,
        week_list: t.weekList.slice(),
        teacher: t.teacher,
        day: t.day,
        start: t.start,
        stop: t.stop,
        source: t.source,
        classroom: t.classroom
      });
    });
    const changes: ClassChangeJson[] = [];
    this.classChanges.forEach((c: ClassChange): void => {
      changes.push({
        type: c.type,
        classCode: c.classCode,
        classNumber: c.classNumber,
        className: c.className,
        originalAffectedWeeks: c.originalAffectedWeeks === null ? null : c.originalAffectedWeeks.slice(),
        newAffectedWeeks: c.newAffectedWeeks === null ? null : c.newAffectedWeeks.slice(),
        originalTeacherData: c.originalTeacherData,
        newTeacherData: c.newTeacherData,
        originalClassRange: c.originalClassRange.slice(),
        newClassRange: c.newClassRange.slice(),
        originalWeek: c.originalWeek < 0 ? null : c.originalWeek,
        newWeek: c.newWeek < 0 ? null : c.newWeek,
        originalClassroom: c.originalClassroom,
        newClassroom: c.newClassroom
      });
    });
    return {
      semesterLength: this.semesterLength,
      semesterCode: this.semesterCode,
      termStartDay: this.termStartDay,
      classDetail: details,
      notArranged: notArranged,
      timeArrangement: times,
      classChanges: changes
    };
  }

  static fromCacheJson(p: ClassTableJson): ClassTableData {
    const data: ClassTableData = new ClassTableData();
    data.semesterLength = p.semesterLength !== undefined ? p.semesterLength : 1;
    data.semesterCode = p.semesterCode !== undefined ? p.semesterCode : '';
    data.termStartDay = p.termStartDay !== undefined ? p.termStartDay : '';
    const details: ClassDetailJson[] = p.classDetail !== undefined ? p.classDetail : [];
    details.forEach((c: ClassDetailJson): void => {
      data.classDetail.push(new ClassDetail(c.name !== undefined ? c.name : '', c.code ?? '', c.number ?? ''));
    });
    const notArranged: NotArrangedJson[] = p.notArranged !== undefined ? p.notArranged : [];
    notArranged.forEach((c: NotArrangedJson): void => {
      data.notArranged.push(new NotArrangementClassDetail(c.name ?? '', c.code ?? '', c.number ?? '', c.teacher ?? ''));
    });
    const times: TimeArrangementJson[] = p.timeArrangement !== undefined ? p.timeArrangement : [];
    times.forEach((t: TimeArrangementJson): void => {
      data.timeArrangement.push(new TimeArrangement(
        t.source === 'empty' ? ClassSource.Empty : ClassSource.School,
        t.index ?? 0,
        t.week_list !== undefined ? t.week_list : [],
        t.day ?? 0,
        t.start ?? 0,
        t.stop ?? 0,
        t.teacher ?? '',
        t.classroom ?? ''
      ));
    });
    const changes: ClassChangeJson[] = p.classChanges !== undefined ? p.classChanges : [];
    changes.forEach((c: ClassChangeJson): void => {
      data.classChanges.push(new ClassChange(
        c.type === 'stop' ? ChangeType.Stop : (c.type === 'change' ? ChangeType.Change : ChangeType.Patch),
        c.classCode ?? '',
        c.classNumber ?? '',
        c.className ?? '',
        c.originalAffectedWeeks === undefined ? null : c.originalAffectedWeeks,
        c.newAffectedWeeks === undefined ? null : c.newAffectedWeeks,
        c.originalTeacherData ?? '',
        c.newTeacherData ?? '',
        ClassChangeJsonHelper.rangeOf(c.originalClassRange),
        ClassChangeJsonHelper.rangeOf(c.newClassRange),
        c.originalWeek === undefined || c.originalWeek === null ? -1 : c.originalWeek,
        c.newWeek === undefined || c.newWeek === null ? -1 : c.newWeek,
        c.originalClassroom ?? '',
        c.newClassroom ?? ''
      ));
    });
    return data;
  }
}

/** ClassChangeJson 辅助：区间字段保证两个元素。 */
class ClassChangeJsonHelper {
  static rangeOf(range: number[] | undefined): number[] {
    if (range !== undefined && range.length >= 2) {
      return [range[0], range[1]];
    }
    return [-1, -1];
  }
}
