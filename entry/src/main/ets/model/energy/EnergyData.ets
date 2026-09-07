import { DateUtil } from '../../utils/date/DateUtil';

/**
 * 能耗模型（对应 Dart model/xidian_ids/energy.dart）。
 * MeterInfo = 单条抄表记录；EnergyInfo = 一次成功抓取的完整快照；
 * ElectricityHistoryInfo = 本地余量历史（每次成功刷新追加，供趋势展示）。
 */
export class MeterInfo {
  readTime: Date;
  readNum: number;
  startNum: number;
  endNum: number;

  constructor(readTime: Date, readNum: number, startNum: number, endNum: number) {
    this.readTime = readTime;
    this.readNum = readNum;
    this.startNum = startNum;
    this.endNum = endNum;
  }
}

export class ElectricityHistoryInfo {
  fetchDay: Date;
  remain: string;

  constructor(fetchDay: Date, remain: string) {
    this.fetchDay = fetchDay;
    this.remain = remain;
  }
}

export class EnergyInfo {
  lastReadDate: Date;
  electricityRemain: number;
  electricityMeterList: MeterInfo[];
  waterMeterList: MeterInfo[];

  constructor(lastReadDate: Date, electricityRemain: number,
    electricityMeterList: MeterInfo[], waterMeterList: MeterInfo[]) {
    this.lastReadDate = lastReadDate;
    this.electricityRemain = electricityRemain;
    this.electricityMeterList = electricityMeterList;
    this.waterMeterList = waterMeterList;
  }

  toCacheJson(): EnergyInfoJson {
    return {
      lastReadDate: DateUtil.formatFull(this.lastReadDate),
      electricityRemain: this.electricityRemain,
      electricityMeterList: MeterInfoJsonHelper.listToJson(this.electricityMeterList),
      waterMeterList: MeterInfoJsonHelper.listToJson(this.waterMeterList)
    };
  }

  static fromCacheJson(p: EnergyInfoJson): EnergyInfo {
    const lastRead: Date | null = DateUtil.parseDateTime(p.lastReadDate !== undefined ? p.lastReadDate : '');
    const meters: MeterInfo[] = MeterInfoJsonHelper.listFromJson(p.electricityMeterList);
    const waters: MeterInfo[] = MeterInfoJsonHelper.listFromJson(p.waterMeterList);
    return new EnergyInfo(
      lastRead !== null ? lastRead : new Date(0),
      p.electricityRemain !== undefined ? p.electricityRemain : 0,
      meters, waters
    );
  }
}

// ---- 缓存 JSON 形状 ----

export interface MeterInfoJson {
  readTime?: string;
  readNum?: number;
  startNum?: number;
  endNum?: number;
}

export interface EnergyInfoJson {
  lastReadDate?: string;
  electricityRemain?: number;
  electricityMeterList?: MeterInfoJson[];
  waterMeterList?: MeterInfoJson[];
}

export interface ElectricityHistoryJson {
  fetchDay?: string;
  remain?: string;
}

class MeterInfoJsonHelper {
  static listToJson(list: MeterInfo[]): MeterInfoJson[] {
    const out: MeterInfoJson[] = [];
    list.forEach((m: MeterInfo): void => {
      out.push({
        readTime: DateUtil.formatFull(m.readTime),
        readNum: m.readNum,
        startNum: m.startNum,
        endNum: m.endNum
      });
    });
    return out;
  }

  static listFromJson(list: MeterInfoJson[] | undefined): MeterInfo[] {
    const out: MeterInfo[] = [];
    if (list === undefined) {
      return out;
    }
    list.forEach((j: MeterInfoJson): void => {
      const time: Date | null = DateUtil.parseDateTime(j.readTime !== undefined ? j.readTime : '');
      if (time !== null) {
        out.push(new MeterInfo(time, j.readNum ?? 0, j.startNum ?? 0, j.endNum ?? 0));
      }
    });
    return out;
  }
}
