/**
 * 实验信息数据模型（对应 Dart model/xidian_ids/experiment.dart）。
 * type: physics=物理实验（wlsy，独立密码），others=其他实验（sysj，复用 IDS）。
 * score 为成绩图片识别结果（label/found/rawUrl），可 JSON 持久化。
 */
export class RecognitionResult {
  readonly label: string;
  readonly found: boolean;
  readonly rawUrl: string;

  constructor(label: string, found: boolean, rawUrl: string) {
    this.label = label;
    this.found = found;
    this.rawUrl = rawUrl;
  }
}

export class ExperimentTimeRange {
  readonly startMs: number;
  readonly endMs: number;

  constructor(startMs: number, endMs: number) {
    this.startMs = startMs;
    this.endMs = endMs;
  }
}

export class ExperimentData {
  readonly type: string;
  readonly name: string;
  readonly score: RecognitionResult | null;
  readonly classroom: string;
  readonly timeRanges: ExperimentTimeRange[];
  readonly teacher: string;
  readonly reference: string;

  constructor(type: string, name: string, score: RecognitionResult | null, classroom: string,
    timeRanges: ExperimentTimeRange[], teacher: string, reference: string) {
    this.type = type;
    this.name = name;
    this.score = score;
    this.classroom = classroom;
    this.timeRanges = timeRanges;
    this.teacher = teacher;
    this.reference = reference;
  }

  /** 最早开始时间（用于排序与状态判定）。 */
  firstStartMs(): number {
    let min: number = Number.MAX_VALUE;
    this.timeRanges.forEach((r: ExperimentTimeRange): void => {
      if (r.startMs < min) {
        min = r.startMs;
      }
    });
    return min === Number.MAX_VALUE ? 0 : min;
  }
}

// ---- JSON 持久化形状（缓存文件 PhysicsExperiment.json / OtherExperiment.json） ----

interface ScoreJson {
  label?: string;
  found?: boolean;
  rawUrl?: string;
}

interface TimeRangeJson {
  startMs?: number;
  endMs?: number;
}

export interface ExperimentJson {
  type?: string;
  name?: string;
  score?: ScoreJson | null;
  classroom?: string;
  timeRanges?: TimeRangeJson[];
  teacher?: string;
  reference?: string;
}

export function experimentToJson(e: ExperimentData): ExperimentJson {
  const ranges: TimeRangeJson[] = [];
  e.timeRanges.forEach((r: ExperimentTimeRange): void => {
    ranges.push({ startMs: r.startMs, endMs: r.endMs });
  });
  const score: ScoreJson | null = e.score !== null
    ? { label: e.score.label, found: e.score.found, rawUrl: e.score.rawUrl } : null;
  return {
    type: e.type, name: e.name, score: score, classroom: e.classroom,
    timeRanges: ranges, teacher: e.teacher, reference: e.reference
  };
}

export function experimentFromJson(j: ExperimentJson): ExperimentData {
  const ranges: ExperimentTimeRange[] = [];
  if (j.timeRanges !== undefined && j.timeRanges !== null) {
    j.timeRanges.forEach((r: TimeRangeJson): void => {
      if (r.startMs !== undefined && r.endMs !== undefined) {
        ranges.push(new ExperimentTimeRange(r.startMs, r.endMs));
      }
    });
  }
  let score: RecognitionResult | null = null;
  if (j.score !== undefined && j.score !== null && j.score.label !== undefined) {
    score = new RecognitionResult(j.score.label, j.score.found === true, j.score.rawUrl ?? '');
  }
  return new ExperimentData(
    j.type ?? 'physics', j.name ?? '', score, j.classroom ?? '',
    ranges, j.teacher ?? '', j.reference ?? ''
  );
}
