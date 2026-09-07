/**
 * 成绩模型（对应 Dart model/xidian_ids/score.dart）。
 * scoreTypeCode：1/3=三级成绩、2=五级成绩（显示 level），0/其他=百分制；
 * isPassedStr：''（Dart null）未出分 / '1' 及格 / '0' 不及格。
 */
export class Score {
  mark: number;
  name: string;
  score: number | null;
  semesterCode: string;
  credit: number;
  classStatus: string;
  classType: string;
  scoreStatus: string;
  scoreTypeCode: number;
  level: string;
  isPassedStr: string;
  classID: string;

  constructor(mark: number, name: string, score: number | null, semesterCode: string, credit: number,
    classStatus: string, classType: string, scoreStatus: string, scoreTypeCode: number,
    level: string, isPassedStr: string, classID: string) {
    this.mark = mark;
    this.name = name;
    this.score = score;
    this.semesterCode = semesterCode;
    this.credit = credit;
    this.classStatus = classStatus;
    this.classType = classType;
    this.scoreStatus = scoreStatus;
    this.scoreTypeCode = scoreTypeCode;
    this.level = level;
    this.isPassedStr = isPassedStr;
    this.classID = classID;
  }

  /** null=未出分（对应 Dart isPassed getter）。 */
  isPassed(): boolean | null {
    if (this.isPassedStr.length === 0 || this.isPassedStr === 'null') {
      return null;
    }
    return this.isPassedStr === '1';
  }

  isFinish(): boolean {
    return this.isPassed() !== null && this.score !== null;
  }

  /** 展示成绩：等级制显示等级；百分制取整；未出分按及格状态细分（照搬 Dart scoreStr）。 */
  scoreStr(): string {
    if (this.score !== null) {
      if (this.scoreTypeCode === 1 || this.scoreTypeCode === 2 || this.scoreTypeCode === 3) {
        return this.level;
      }
      return `${Math.trunc(this.score)}`;
    }
    if (this.isPassedStr.length === 0 || this.isPassedStr === 'null') {
      return '暂无';
    }
    if (this.isPassedStr.includes('0')) {
      return '暂无但未及格';
    }
    return '暂无但及格';
  }

  /** 绩点映射（照搬 Dart gpa getter）。 */
  gpa(): number {
    if (!this.isFinish()) {
      return 0.0;
    }
    if (this.scoreTypeCode === 1 || this.scoreTypeCode === 3) {
      if (this.level === '优秀') {
        return 4.0;
      }
      return this.level === '通过' ? 3.2 : 0.0;
    }
    if (this.scoreTypeCode === 2) {
      if (this.level === '优秀') {
        return 4.0;
      }
      if (this.level === '良好') {
        return 3.8;
      }
      if (this.level === '中等') {
        return 3.2;
      }
      return this.level === '及格' ? 2.4 : 0.0;
    }
    const s: number = this.score as number;
    if (s >= 95) {
      return 4.0;
    }
    if (s >= 90) {
      return 3.9;
    }
    if (s >= 84) {
      return 3.8;
    }
    if (s >= 80) {
      return 3.6;
    }
    if (s >= 76) {
      return 3.4;
    }
    if (s >= 73) {
      return 3.2;
    }
    if (s >= 70) {
      return 3.0;
    }
    if (s >= 67) {
      return 2.7;
    }
    if (s >= 64) {
      return 2.4;
    }
    if (s >= 62) {
      return 2.2;
    }
    return s >= 60 ? 2.0 : 0.0;
  }
}

/** 成绩组成明细（对应 Dart ComposeDetail，来自过观课过程成绩查询）。 */
export class ComposeDetail {
  content: string;
  ratio: string;
  score: string;

  constructor(content: string, ratio: string, score: string) {
    this.content = content;
    this.ratio = ratio;
    this.score = score;
  }
}

// ---- 缓存 JSON 形状（scores.json 为数组，字段与 Dart json_serializable 一致） ----

export interface ScoreJson {
  mark?: number;
  name?: string;
  score?: number | null;
  semesterCode?: string;
  credit?: number;
  classStatus?: string;
  classType?: string;
  scoreStatus?: string;
  scoreTypeCode?: number;
  level?: string | null;
  isPassedStr?: string | null;
  classID?: string | null;
}

export function scoreFromJson(j: ScoreJson, mark: number): Score {
  return new Score(
    j.mark !== undefined ? j.mark : mark,
    j.name ?? '',
    j.score !== undefined && j.score !== null ? j.score : null,
    j.semesterCode ?? '',
    j.credit !== undefined && j.credit !== null ? j.credit : 0,
    j.classStatus ?? '',
    j.classType ?? '',
    j.scoreStatus ?? '',
    j.scoreTypeCode !== undefined && j.scoreTypeCode !== null ? j.scoreTypeCode : 0,
    j.level !== undefined && j.level !== null ? j.level : '',
    j.isPassedStr !== undefined && j.isPassedStr !== null ? j.isPassedStr : '',
    j.classID !== undefined && j.classID !== null ? j.classID : ''
  );
}

export function scoreToJson(s: Score): ScoreJson {
  return {
    mark: s.mark,
    name: s.name,
    score: s.score,
    semesterCode: s.semesterCode,
    credit: s.credit,
    classStatus: s.classStatus,
    classType: s.classType,
    scoreStatus: s.scoreStatus,
    scoreTypeCode: s.scoreTypeCode,
    level: s.level,
    isPassedStr: s.isPassedStr,
    classID: s.classID
  };
}
