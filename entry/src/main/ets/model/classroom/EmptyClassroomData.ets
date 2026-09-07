/**
 * 空闲教室数据模型（对应 Dart model/xidian_ids/empty_classroom.dart）。
 * EmptyClassroomData.name 中 「(容量/类型)」 已按原版规则拆为换行分段展示。
 */
export class EmptyClassroomPlace {
  readonly code: string;
  readonly name: string;

  constructor(code: string, name: string) {
    this.code = code;
    this.name = name;
  }
}

export class EmptyClassroomData {
  readonly name: string;
  /** 11 节占用状态（JCx 含 "1_" 即占用），长度恒为 11。 */
  readonly isUsed: boolean[];

  constructor(name: string, isUsed: boolean[]) {
    this.name = name;
    this.isUsed = isUsed;
  }

  /** 名称行（原版把 "(" 换成换行去掉 ")"，首段为教室名）。 */
  nameLines(): string[] {
    return this.name.split('\n');
  }
}
