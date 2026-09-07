/**
 * 成绩图片哈希表与节次时间表（移植自 Dart generated/score_hashes.g.dart 与 model/time_list.dart）。
 * kScoreHashes：分数标签 → 50×20 区域内不透明像素 RGB 序列的 FNV-1a 32 位哈希。
 */

const SCORE_HASH_MAP: Map<string, number> = new Map<string, number>([
  ['0', 3531432063],
  ['10', 2759386880],
  ['4', 314909311],
  ['5', 3417863369],
  ['5.5', 1879675493],
  ['6', 1633340036],
  ['6.5', 406889604],
  ['7', 923381590],
  ['7.5', 3679241944],
  ['8', 957817480],
  ['8.5', 4210302206],
  ['9', 3501829210],
  ['9.5', 4187815228],
  ['已上传', 4077928038],
  ['未上传', 843703430]
]);

export function scoreLabelByHash(hash: number): string | null {
  const entries: IterableIterator<[string, number]> = SCORE_HASH_MAP.entries();
  let step: IteratorResult<[string, number]> = entries.next();
  while (!step.done) {
    if (step.value[1] === hash) {
      return step.value[0];
    }
    step = entries.next();
  }
  return null;
}

/** 节次时间表（偶数下标=上课，奇数下标=下课），13 节。 */
const TIME_LIST: string[] = [
  '08:30', '09:15',
  '09:20', '10:05',
  '10:25', '11:10',
  '11:15', '12:00',
  '14:00', '14:45',
  '14:50', '15:35',
  '15:55', '16:40',
  '16:45', '17:30',
  '19:00', '19:45',
  '19:55', '20:35',
  '20:40', '21:25'
];

export function timeListStart(classIndex: number): string {
  return TIME_LIST[(classIndex - 1) * 2];
}

export function timeListEnd(classIndex: number): string {
  return TIME_LIST[(classIndex - 1) * 2 + 1];
}
