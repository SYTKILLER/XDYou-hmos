/**
 * 体育信息数据模型（对应 Dart model/xidian_sport/sport_score.dart 与 sport_class.dart）。
 * SportClassItem 的学期/时间正则解析与星期映射 1:1 对拍原版。
 */

/** 单项体测明细（某年度下的一项测试）。 */
export class SportItems {
  readonly examName: string;
  readonly examunit: string;
  readonly actualScore: string;
  readonly score: number;
  readonly rank: string;

  constructor(examName: string, examunit: string, actualScore: string, score: number, rank: string) {
    this.examName = examName;
    this.examunit = examunit;
    this.actualScore = actualScore;
    this.score = score;
    this.rank = rank;
  }
}

/** 学年体测成绩。 */
export class SportScoreOfYear {
  readonly year: string;
  readonly totalScore: string;
  readonly rank: string;
  readonly gradeType: string;
  moreinfo: string = '';
  details: SportItems[] = [];

  constructor(year: string, totalScore: string, rank: string, gradeType: string) {
    this.year = year;
    this.totalScore = totalScore;
    this.rank = rank;
    this.gradeType = gradeType;
  }
}

/** 体测成绩汇总（毕业总览 + 年度列表）。 */
export class SportScore {
  total: string = '0.0';
  rank: string = '';
  detail: string = '';
  list: SportScoreOfYear[] = [];

  isQualified(): boolean {
    return !this.rank.includes('不');
  }
}

/** 体育课成绩条目（term 正则 `^(\d{4})-(\d{4}).*(\d)$` 切学期，时间正则 `^星期(.)(\d)(\d)` 切节次）。 */
export class SportClassItem {
  readonly termToShow: string;
  readonly score: string;
  readonly type: string;
  readonly term: string;
  readonly name: string;
  readonly teacher: string;
  readonly week: number;
  readonly start: number;
  readonly stop: number;
  readonly place: string;

  constructor(termToShow: string, score: string, type: string, term: string, name: string,
    teacher: string, week: number, start: number, stop: number, place: string) {
    this.termToShow = termToShow;
    this.score = score;
    this.type = type;
    this.term = term;
    this.name = name;
    this.teacher = teacher;
    this.week = week;
    this.start = start;
    this.stop = stop;
    this.place = place;
  }

  static weekOfDay(ch: string): number {
    if (ch === '一') {
      return 1;
    }
    if (ch === '二') {
      return 2;
    }
    if (ch === '三') {
      return 3;
    }
    if (ch === '四') {
      return 4;
    }
    if (ch === '五') {
      return 5;
    }
    if (ch === '六') {
      return 6;
    }
    if (ch === '日') {
      return 7;
    }
    return 0;
  }

  static fromData(termName: string, name: string, score: string, type: string,
    teacher: string, time: string, place: string): SportClassItem {
    const termDealer: RegExp = /^(\d{4})-(\d{4}).*(\d{1})/;
    const timeDealer: RegExp = /^星期(.{1})(\d{1})(\d{1})/;
    const termMatch: RegExpExecArray | null = termDealer.exec(termName);
    const timeMatch: RegExpExecArray | null = timeDealer.exec(time);
    if (termMatch === null || timeMatch === null) {
      throw new Error(`体育课数据解析失败：${termName} / ${time}`);
    }
    const week: number = SportClassItem.weekOfDay(timeMatch[1]);
    const start: number = parseInt(timeMatch[2], 10);
    const stop: number = parseInt(timeMatch[3], 10);
    const term: string = `${termMatch[1]}-${termMatch[2]}-${termMatch[3]}`;
    return new SportClassItem(termName, score, type, term, name, teacher, week, start, stop, place);
  }
}
