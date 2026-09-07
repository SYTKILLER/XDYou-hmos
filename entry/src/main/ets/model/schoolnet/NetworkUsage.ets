import { PreferenceService } from '../../service/preference/PreferenceService';

/**
 * 校园网模型（对应 Dart model/network_usage.dart）。
 * GeneralNetworkUsage = zfw 自助服务 HTML 抓取的用量汇总；
 * CurrentUserNetInfo = w.xidian.edu.cn rad_user_info 的当前在线信息（字段名保持接口原文）。
 */

/** 在线设备行（Dart 元组 (ip, online_time, used_t) 的显式化）。 */
export class IpUsageRow {
  ip: string;
  onlineTime: string;
  used: string;

  constructor(ip: string, onlineTime: string, used: string) {
    this.ip = ip;
    this.onlineTime = onlineTime;
    this.used = used;
  }
}

export class GeneralNetworkUsage {
  ipList: IpUsageRow[];
  used: string;
  rest: string;
  charged: string;

  constructor(ipList: IpUsageRow[], used: string, rest: string, charged: string) {
    this.ipList = ipList;
    this.used = used;
    this.rest = rest;
    this.charged = charged;
  }

  toCacheJson(): GeneralNetworkUsageJson {
    const rows: IpUsageRowJson[] = [];
    this.ipList.forEach((r: IpUsageRow): void => {
      rows.push({ ip: r.ip, onlineTime: r.onlineTime, used: r.used });
    });
    return { ipList: rows, used: this.used, rest: this.rest, charged: this.charged };
  }

  static fromCacheJson(p: GeneralNetworkUsageJson): GeneralNetworkUsage {
    const rows: IpUsageRow[] = [];
    if (p.ipList !== undefined) {
      p.ipList.forEach((j: IpUsageRowJson): void => {
        rows.push(new IpUsageRow(
          j.ip !== undefined ? j.ip : '',
          j.onlineTime !== undefined ? j.onlineTime : '',
          j.used !== undefined ? j.used : ''
        ));
      });
    }
    return new GeneralNetworkUsage(rows,
      p.used !== undefined ? p.used : '',
      p.rest !== undefined ? p.rest : '',
      p.charged !== undefined ? p.charged : '');
  }
}

// ---- 缓存 JSON 形状 ----

export interface IpUsageRowJson {
  ip?: string;
  onlineTime?: string;
  used?: string;
}

export interface GeneralNetworkUsageJson {
  ipList?: IpUsageRowJson[];
  used?: string;
  rest?: string;
  charged?: string;
}

/**
 * 当前在线信息（rad_user_info）。Dart 模型字段全为 late 非空——离线时接口返回结构不完整会崩，
 * ArkTS 侧改为全可选 + 默认值，error 非空按"未在线"呈现（判空语义：有值才算有）。
 */
export class CurrentUserNetInfo {
  readonly error: string;
  readonly realName: string;
  readonly userName: string;
  readonly onlineIp: string;
  readonly productsName: string;
  readonly billingName: string;
  readonly allBytes: number;
  readonly sumBytes: number;
  readonly remainBytes: number;
  readonly bytesIn: number;
  readonly bytesOut: number;
  readonly userBalance: number;

  constructor(error: string, realName: string, userName: string, onlineIp: string, productsName: string,
    billingName: string, allBytes: number, sumBytes: number, remainBytes: number, bytesIn: number,
    bytesOut: number, userBalance: number) {
    this.error = error;
    this.realName = realName;
    this.userName = userName;
    this.onlineIp = onlineIp;
    this.productsName = productsName;
    this.billingName = billingName;
    this.allBytes = allBytes;
    this.sumBytes = sumBytes;
    this.remainBytes = remainBytes;
    this.bytesIn = bytesIn;
    this.bytesOut = bytesOut;
    this.userBalance = userBalance;
  }

  /** 磁盘缓存序列化（snake_case 与接口原文同形，用 fromJson 还原）。 */
  toCacheJson(): CurrentUserNetInfoJson {
    return {
      error: this.error, real_name: this.realName, user_name: this.userName, online_ip: this.onlineIp,
      products_name: this.productsName, billing_name: this.billingName,
      all_bytes: this.allBytes, sum_bytes: this.sumBytes, remain_bytes: this.remainBytes,
      bytes_in: this.bytesIn, bytes_out: this.bytesOut, user_balance: this.userBalance
    };
  }

  static fromJson(j: CurrentUserNetInfoJson): CurrentUserNetInfo {
    return new CurrentUserNetInfo(
      str(j.error), str(j.real_name), str(j.user_name), str(j.online_ip),
      str(j.products_name), str(j.billing_name),
      num(j.all_bytes), num(j.sum_bytes), num(j.remain_bytes), num(j.bytes_in), num(j.bytes_out),
      num(j.user_balance)
    );
  }

  /** 本计费周期总流量 = 已用 + 剩余（Dart CurrentNetInfoPage 同口径）。 */
  periodTotalBytes(): number {
    return this.sumBytes + this.remainBytes;
  }

  isOnline(): boolean {
    return this.error.length === 0;
  }

  /** realName 写入 displayName 偏好（本科生姓名来源之一）。 */
  syncDisplayName(): void {
    if (this.realName.length > 0) {
      PreferenceService.putString('displayName', this.realName);
    }
  }
}

function str(v: string | number | null | undefined): string {
  return v === undefined || v === null ? '' : `${v}`;
}

function num(v: string | number | null | undefined): number {
  if (typeof v === 'number') {
    return v;
  }
  const parsed: number = parseFloat(v === undefined || v === null ? '' : v);
  return isNaN(parsed) ? 0 : parsed;
}

export interface CurrentUserNetInfoJson {
  ServerFlag?: string | number | null;
  error?: string | null;
  real_name?: string | null;
  user_name?: string | null;
  online_ip?: string | null;
  products_name?: string | null;
  billing_name?: string | null;
  all_bytes?: string | number | null;
  sum_bytes?: string | number | null;
  remain_bytes?: string | number | null;
  bytes_in?: string | number | null;
  bytes_out?: string | number | null;
  user_balance?: string | number | null;
}

/**
 * 字节量人性化展示。校园网计费为 GB 单位 1000 进制（原版 CurrentNetInfoPage 同口径），
 * 正数统一两位小数（B 级除外），与原版 toStringAsFixed(2) 对齐。
 */
export function formatBytes(bytes: number): string {
  if (!(bytes > 0)) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value: number = bytes;
  let index: number = 0;
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000;
    index++;
  }
  return index === 0 ? `${Math.round(value)} ${units[index]}` : `${value.toFixed(2)} ${units[index]}`;
}
