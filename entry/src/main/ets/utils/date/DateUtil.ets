/**
 * 日期工具：与 Dart DateTime/intl 行为对齐的最小集。
 * 学期周次与日程过滤大量依赖"本地时区自然日"语义，统一在此实现避免散落。
 */
export class DateUtil {
  static readonly MS_PER_DAY: number = 86400000;

  /**
   * 解析 "yyyy-MM-dd HH:mm:ss"（兼容仅日期 "yyyy-MM-dd"）。
   * 不用 new Date(string)：空格分隔格式在不同运行时解析行为不一，手工拆分最稳。
   */
  static parseDateTime(text: string): Date | null {
    if (text.length < 10) {
      return null;
    }
    const datePart: string[] = text.substring(0, 10).split('-');
    if (datePart.length !== 3) {
      return null;
    }
    const year: number = Number(datePart[0]);
    const month: number = Number(datePart[1]);
    const day: number = Number(datePart[2]);
    let hour: number = 0;
    let minute: number = 0;
    let second: number = 0;
    if (text.length >= 19) {
      const timePart: string[] = text.substring(11, 19).split(':');
      if (timePart.length === 3) {
        hour = Number(timePart[0]);
        minute = Number(timePart[1]);
        second = Number(timePart[2]);
      }
    }
    const date: Date = new Date(year, month - 1, day, hour, minute, second);
    return isNaN(date.getTime()) ? null : date;
  }

  /** yyyyMMdd（对应 Dart DateFormat("yyyyMMdd")，queryRcap 入参）。 */
  static formatCompactDate(date: Date): string {
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}${month}${day}`;
  }

  /** yyyy-MM-dd（GetMetRead 时间区间格式）。 */
  static formatDash(date: Date): string {
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  /** "yyyy-MM-dd HH:mm:ss"（HomeArrangement 存储格式 / termStartDay 格式）。 */
  static formatFull(date: Date): string {
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${date.getDate()}`.padStart(2, '0');
    const hour: string = `${date.getHours()}`.padStart(2, '0');
    const minute: string = `${date.getMinutes()}`.padStart(2, '0');
    const second: string = `${date.getSeconds()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}:${second}`;
  }

  /** "MM-dd HH:mm"（缓存时间等界面短格式）。 */
  static formatShort(date: Date): string {
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${date.getDate()}`.padStart(2, '0');
    const hour: string = `${date.getHours()}`.padStart(2, '0');
    const minute: string = `${date.getMinutes()}`.padStart(2, '0');
    return `${month}-${day} ${hour}:${minute}`;
  }

  /** Dart DateTime.weekday：周一=1 … 周日=7（JS getDay 周日=0）。 */
  static weekday(date: Date): number {
    const day: number = date.getDay();
    return day === 0 ? 7 : day;
  }

  /** 同一自然日判断（本地时区，对应 Dart isAtSameDayAs）。 */
  static isSameDay(a: Date, b: Date): boolean {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  }

  /**
   * 月份平移（对应 Dart time 包 DateTime.shift(months:)）：日超出目标月天数时钳制到月末。
   */
  static shiftMonths(date: Date, months: number): Date {
    const rawMonth: number = date.getMonth() + months;
    const targetYear: number = date.getFullYear() + Math.floor(rawMonth / 12);
    const targetMonth: number = ((rawMonth % 12) + 12) % 12;
    const lastDay: number = new Date(targetYear, targetMonth + 1, 0).getDate();
    return new Date(targetYear, targetMonth, Math.min(date.getDate(), lastDay));
  }
}
