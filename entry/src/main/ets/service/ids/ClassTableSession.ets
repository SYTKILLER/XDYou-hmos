import { IdsSession } from './IdsSession';
import { backgroundSliderHandler } from './BackgroundSlider';
import { AppContext } from '../AppContext';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { FetchResult } from '../../model/FetchResult';
import { ClassTableData, ClassDetail, NotArrangementClassDetail, TimeArrangement,
  ClassChange, ClassSource, ChangeType, ClassTableJson } from '../../model/classtable/ClassTableData';
import { DateUtil } from '../../utils/date/DateUtil';
import { Log } from '../../utils/Log';

// ---- ehall / yjspt 响应 JSON 形状（字段名为学校接口原文） ----

interface ExtParams {
  code?: string | number;
  msg?: string | number;
}

interface EhallClassRow {
  KCM?: string | number;
  KCH?: string | number;
  KXH?: string | number;
  KSJC?: string | number;
  JSJC?: string | number;
  SKJS?: string | number;
  SKXQ?: string | number;
  SKZC?: string | number;
  JASMC?: string | number;
}

interface EhallNotArrangedRow {
  KCM?: string | number;
  KCH?: string | number;
  KXH?: string | number;
  SKJS?: string | number;
}

interface YjsptNotArrangedRow {
  KCMC?: string | number;
  KCDM?: string | number;
}

interface EhallChangeRow {
  TKLXDM?: string | number;
  KCH?: string | number;
  KXH?: string | number;
  KCM?: string | number;
  SKZC?: string | number | null;
  XSKZC?: string | number | null;
  YSKJS?: string | number;
  XSKJS?: string | number;
  KSJC?: string | number | null;
  JSJC?: string | number | null;
  XKSJC?: string | number | null;
  XJSJC?: string | number | null;
  SKXQ?: string | number | null;
  XSKXQ?: string | number | null;
  JASMC?: string | number | null;
  XJASMC?: string | number | null;
}

interface EhallSection {
  totalSize?: string | number;
  extParams?: ExtParams;
  rows?: EhallClassRow[];
}

interface EhallNotArrangedSection {
  rows?: EhallNotArrangedRow[];
}

interface EhallChangeSection {
  totalSize?: string | number;
  extParams?: ExtParams;
  rows?: EhallChangeRow[];
}

interface EhallXskcbDatas {
  xskcb?: EhallSection;
}

interface EhallXskcbResp {
  datas?: EhallXskcbDatas;
}

interface CxjcsRow {
  XQKSRQ?: string;
}

interface CxjcsSection {
  rows?: CxjcsRow[];
}

interface EhallCxjcsDatas {
  cxjcs?: CxjcsSection;
}

interface EhallCxjcsResp {
  datas?: EhallCxjcsDatas;
}

interface EhallNotArrangedDatas {
  cxxsllsywpk?: EhallNotArrangedSection;
}

interface EhallNotArrangedResp {
  datas?: EhallNotArrangedDatas;
}

interface EhallChangeDatas {
  xsdkkc?: EhallChangeSection;
}

interface EhallChangeResp {
  datas?: EhallChangeDatas;
}

interface YjsptClassRow {
  KCMC?: string | number;
  KCDM?: string | number;
  KSJCDM?: string | number;
  JSJCDM?: string | number;
  JSXM?: string | number;
  XQ?: string | number;
  ZCBH?: string | number;
  JASMC?: string | number;
}

interface YjsptSection {
  rows?: YjsptClassRow[];
}

interface YjsptClassDatas {
  xspkjgcx?: YjsptSection;
}

interface YjsptClassResp {
  code?: string | number;
  extParams?: ExtParams;
  datas?: YjsptClassDatas;
}

interface YjsptNotArrangedSection {
  rows?: YjsptNotArrangedRow[];
}

interface YjsptNotArrangedDatas {
  xswsckbkc?: YjsptNotArrangedSection;
}

interface YjsptNotArrangedResp {
  datas?: YjsptNotArrangedDatas;
}

interface YjsptRcapResp {
  xnxq?: string;
}

const EHALL_APP_SHOW_URL: string = 'https://ehall.xidian.edu.cn/appShow?appId=4770397878132218';
const EHALL_CXJCS_URL: string = 'https://ehall.xidian.edu.cn/jwapp/sys/wdkb/modules/jshkcb/cxjcs.do';
const EHALL_XSKCB_URL: string = 'https://ehall.xidian.edu.cn/jwapp/sys/wdkb/modules/xskcb/xskcb.do';
const EHALL_NOT_ARRANGED_URL: string =
  'https://ehall.xidian.edu.cn/jwapp/sys/wdkb/modules/xskcb/cxxsllsywpk.do';
const EHALL_CHANGE_URL: string = 'https://ehall.xidian.edu.cn/jwapp/sys/wdkb/modules/xskcb/xsdkkc.do';
const YJSPT_INDEX_URL: string = 'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/*default/index.do#/xskcb';
const YJSPT_RCAP_URL: string = 'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/portal/queryRcap.do';
const YJSPT_CLASS_URL: string = 'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/xspkjgcx.do';
const YJSPT_NOT_ARRANGED_URL: string =
  'https://yjspt.xidian.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/xswsckbkc.do';

/**
 * 课程表抓取（对应 Dart repository/ids_session/classtable_session.dart）。
 * 本科 ehall（含调课/停课/补课合并算法），研究生 yjspt（连续节次合并）；
 * 全部为 JSON POST；失败回退本地缓存 ClassTable.json。
 *
 * 简化说明：未移植 Dart SingleFlight/过期请求丢弃（_isLatestRequest）——
 * 当前入口（页面打开/下拉刷新/学期同步）均为串行触发，控制器以单一 in-flight Promise 去重。
 */
export class ClassTableSession {
  static readonly CACHE_FILE: string = 'ClassTable.json';

  static async getClassTable(semesterCode: string, isPostgraduate: boolean): Promise<FetchResult<ClassTableData>> {
    try {
      const data: ClassTableData = isPostgraduate
        ? await ClassTableSession.getYjspt(semesterCode)
        : await ClassTableSession.getEhall(semesterCode);
      AppContext.writeCacheText(ClassTableSession.CACHE_FILE, JSON.stringify(data.toCacheJson()));
      return FetchResult.fresh<ClassTableData>(data);
    } catch (e) {
      const cached: ClassTableData | null = ClassTableSession.getCacheData();
      if (cached !== null) {
        Log.warn(`getClassTable failed, fallback cache: ${e}`);
        return FetchResult.cached<ClassTableData>(cached, ClassTableSession.cacheFetchTime(),
          ClassTableSession.hintFromError(e));
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new Error(`${e}`);
    }
  }

  static getCacheData(): ClassTableData | null {
    const text: string | null = AppContext.readCacheText(ClassTableSession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return null;
    }
    try {
      const parsed: ClassTableJson = JSON.parse(text) as ClassTableJson;
      return ClassTableData.fromCacheJson(parsed);
    } catch (e) {
      Log.warn(`classtable cache parse failed: ${e}`);
      return null;
    }
  }

  static cacheFetchTime(): number {
    return AppContext.cacheModifiedMs(ClassTableSession.CACHE_FILE);
  }

  static deleteCache(): void {
    AppContext.deleteCache(ClassTableSession.CACHE_FILE);
  }

  private static hintFromError(error: Object): string {
    const message: string = `${error}`;
    if (message.includes('密码')) {
      return 'classtable.cache_hint_password_wrong';
    }
    if (message.includes('登录')) {
      return 'classtable.cache_hint_login_failed';
    }
    return 'classtable.cache_hint_network_failed';
  }

  private static toStr(value: string | number | null | undefined): string {
    return value === undefined || value === null ? '' : `${value}`;
  }

  private static toInt(value: string | number | null | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return value;
    }
    if (value === undefined || value === null) {
      return fallback;
    }
    const parsed: number = parseInt(value, 10);
    return isNaN(parsed) ? fallback : parsed;
  }

  /** 01 串 → 布尔周次列表（对应 Dart List<bool>.generate(length, (i) => s[i] == '1')）。 */
  private static weekListOf(value: string | number | null | undefined): boolean[] {
    const text: string = ClassTableSession.toStr(value);
    const list: boolean[] = [];
    for (let i = 0; i < text.length; i++) {
      list.push(text[i] === '1');
    }
    return list;
  }

  private static async loginAndFollow(target: string): Promise<void> {
    const slider = backgroundSliderHandler();
    const location: string = await IdsSession.checkAndLogin(target, slider);
    await IdsSession.followRedirects(location);
  }

  private static account(): string {
    return PreferenceService.getString('idsAccount', '');
  }

  private static listEquals(a: number[], b: number[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  // ================= 研究生链路（yjspt） =================

  private static async getYjspt(semesterCode: string): Promise<ClassTableData> {
    const session: NetworkSession = SessionManager.ids();
    await ClassTableSession.loginAndFollow(YJSPT_INDEX_URL);

    const now: Date = new Date();
    const rcap: SessionResponse =
      await session.postForm(YJSPT_RCAP_URL, ClassTableSession.dayFields(now));
    if (!rcap.bodyText.includes('xnxq')) {
      Log.warn('[getYjspt] queryRcap without xnxq, empty table');
      return new ClassTableData();
    }
    const rcapParsed: YjsptRcapResp = JSON.parse(rcap.bodyText) as YjsptRcapResp;
    const xnxqText: string = rcapParsed.xnxq !== undefined ? rcapParsed.xnxq : '';
    const weekMatch: RegExpMatchArray | null = xnxqText.match(/[0-9]+/);
    const currentWeekText: string = weekMatch !== null ? weekMatch[0] : '';
    if (currentWeekText.length === 0) {
      Log.warn('[getYjspt] queryRcap week parse failed');
      return new ClassTableData();
    }
    const currentWeek: number = parseInt(currentWeekText, 10);

    // 用当前周反推开学日：now + (1 - week)*7 - (weekday-1)（对应 Dart 反推公式）。
    const termStartDate: Date = new Date(now.getTime()
      + ((1 - currentWeek) * 7 - (DateUtil.weekday(now) - 1)) * DateUtil.MS_PER_DAY);
    const termStartDay: string = DateUtil.formatFull(termStartDate);
    Log.info(`[getYjspt] week=${currentWeek}, termStartDay=${termStartDay}`);

    const classResp: SessionResponse =
      await session.postForm(YJSPT_CLASS_URL, ClassTableSession.semesterFields(semesterCode, false));
    const classParsed: YjsptClassResp = JSON.parse(classResp.bodyText) as YjsptClassResp;
    if (`${classParsed.code ?? ''}` !== '0') {
      const msg: string = classParsed.extParams !== undefined ? ClassTableSession.toStr(classParsed.extParams.msg) : '';
      if (msg.includes('查询学年学期的课程未发布')) {
        Log.warn('[getYjspt] classtable not released');
        const skeleton: ClassTableData = new ClassTableData();
        skeleton.semesterCode = semesterCode;
        skeleton.termStartDay = termStartDay;
        return skeleton;
      }
      throw new Error(msg.length > 0 ? msg : '课程表获取失败');
    }

    const rows: YjsptClassRow[] =
      classParsed.datas !== undefined && classParsed.datas.xspkjgcx !== undefined
      && classParsed.datas.xspkjgcx.rows !== undefined ? classParsed.datas.xspkjgcx.rows : [];

    const toReturn: ClassTableData = new ClassTableData();
    toReturn.semesterCode = semesterCode;
    toReturn.termStartDay = termStartDay;

    for (let i = 0; i < rows.length; i++) {
      const row: YjsptClassRow = rows[i];
      const toDeal: ClassDetail = new ClassDetail(ClassTableSession.toStr(row.KCMC), ClassTableSession.toStr(row.KCDM));
      let index: number = -1;
      for (let k = 0; k < toReturn.classDetail.length; k++) {
        if (toReturn.classDetail[k].equalsByName(toDeal)) {
          index = k;
          break;
        }
      }
      if (index < 0) {
        toReturn.classDetail.push(toDeal);
        index = toReturn.classDetail.length - 1;
      }
      toReturn.timeArrangement.push(new TimeArrangement(
        ClassSource.School, index,
        ClassTableSession.weekListOf(row.ZCBH),
        ClassTableSession.toInt(row.XQ, 0),
        ClassTableSession.toInt(row.KSJCDM, 0),
        ClassTableSession.toInt(row.JSJCDM, 0),
        ClassTableSession.toStr(row.JSXM),
        ClassTableSession.toStr(row.JASMC)
      ));
      const zcLength: number = ClassTableSession.toStr(row.ZCBH).length;
      if (zcLength > toReturn.semesterLength) {
        toReturn.semesterLength = zcLength;
      }
    }

    // 连续节次合并（对应 Dart getYjspt 的 "Post deal" 段）。
    toReturn.timeArrangement = ClassTableSession.mergeConsecutiveSections(toReturn);

    const notResp: SessionResponse =
      await session.postForm(YJSPT_NOT_ARRANGED_URL, ClassTableSession.semesterFields(semesterCode, true));
    const notParsed: YjsptNotArrangedResp = JSON.parse(notResp.bodyText) as YjsptNotArrangedResp;
    const notRows: YjsptNotArrangedRow[] =
      notParsed.datas !== undefined && notParsed.datas.xswsckbkc !== undefined
      && notParsed.datas.xswsckbkc.rows !== undefined ? notParsed.datas.xswsckbkc.rows : [];
    notRows.forEach((row: YjsptNotArrangedRow): void => {
      toReturn.notArranged.push(new NotArrangementClassDetail(
        ClassTableSession.toStr(row.KCMC), ClassTableSession.toStr(row.KCDM)));
    });
    return toReturn;
  }

  // ================= 本科链路（ehall） =================

  private static async getEhall(semesterCode: string): Promise<ClassTableData> {
    const session: NetworkSession = SessionManager.ids();
    await ClassTableSession.loginAndFollow(EHALL_APP_SHOW_URL);

    const parts: string[] = semesterCode.split('-');
    if (parts.length < 3) {
      throw new Error(`学期代码格式异常：${semesterCode}`);
    }
    const xn: string = `${parts[0]}-${parts[1]}`;
    const xq: string = parts[2];

    const cxjcsFields: Map<string, string> = new Map();
    cxjcsFields.set('XN', xn);
    cxjcsFields.set('XQ', xq);
    const cxjcsResp: SessionResponse = await session.postForm(EHALL_CXJCS_URL, cxjcsFields);
    const cxjcsParsed: EhallCxjcsResp = JSON.parse(cxjcsResp.bodyText) as EhallCxjcsResp;
    const cxjcsRows: CxjcsRow[] =
      cxjcsParsed.datas !== undefined && cxjcsParsed.datas.cxjcs !== undefined
      && cxjcsParsed.datas.cxjcs.rows !== undefined ? cxjcsParsed.datas.cxjcs.rows : [];
    if (cxjcsRows.length === 0 || cxjcsRows[0].XQKSRQ === undefined) {
      throw new Error('开学日期获取失败');
    }
    const termStartDay: string = cxjcsRows[0].XQKSRQ;
    Log.info(`[getEhall] ${semesterCode} starts at ${termStartDay}`);

    const classResp: SessionResponse =
      await session.postForm(EHALL_XSKCB_URL, ClassTableSession.semesterFields(semesterCode, true));
    const classParsed: EhallXskcbResp = JSON.parse(classResp.bodyText) as EhallXskcbResp;
    const section: EhallSection | undefined =
      classParsed.datas !== undefined ? classParsed.datas.xskcb : undefined;
    if (section === undefined) {
      throw new Error('课程表获取失败：响应缺少数据');
    }
    const extParams: ExtParams | undefined = section.extParams;
    if (extParams === undefined || `${extParams.code ?? ''}` !== '1') {
      const msg: string = extParams !== undefined ? ClassTableSession.toStr(extParams.msg) : '';
      if (msg.includes('查询学年学期的课程未发布')) {
        Log.warn('[getEhall] classtable not released');
        const skeleton: ClassTableData = new ClassTableData();
        skeleton.semesterCode = semesterCode;
        skeleton.termStartDay = termStartDay;
        return skeleton;
      }
      throw new Error(msg.length > 0 ? msg : '课程表获取失败');
    }
    const rows: EhallClassRow[] = section.rows !== undefined ? section.rows : [];

    const preliminaryData: ClassTableData = new ClassTableData();
    preliminaryData.semesterCode = semesterCode;
    preliminaryData.termStartDay = termStartDay;

    for (let i = 0; i < rows.length; i++) {
      const row: EhallClassRow = rows[i];
      const toDeal: ClassDetail = new ClassDetail(
        ClassTableSession.toStr(row.KCM), ClassTableSession.toStr(row.KCH), ClassTableSession.toStr(row.KXH));
      let index: number = -1;
      for (let k = 0; k < preliminaryData.classDetail.length; k++) {
        if (preliminaryData.classDetail[k].equalsByName(toDeal)) {
          index = k;
          break;
        }
      }
      if (index < 0) {
        preliminaryData.classDetail.push(toDeal);
        index = preliminaryData.classDetail.length - 1;
      }
      preliminaryData.timeArrangement.push(new TimeArrangement(
        ClassSource.School, index,
        ClassTableSession.weekListOf(row.SKZC),
        ClassTableSession.toInt(row.SKXQ, 0),
        ClassTableSession.toInt(row.KSJC, 0),
        ClassTableSession.toInt(row.JSJC, 0),
        ClassTableSession.toStr(row.SKJS),
        ClassTableSession.toStr(row.JASMC)
      ));
      const zcLength: number = ClassTableSession.toStr(row.SKZC).length;
      if (zcLength > preliminaryData.semesterLength) {
        preliminaryData.semesterLength = zcLength;
      }
    }

    const notResp: SessionResponse =
      await session.postForm(EHALL_NOT_ARRANGED_URL, ClassTableSession.semesterFields(semesterCode, true));
    const notParsed: EhallNotArrangedResp = JSON.parse(notResp.bodyText) as EhallNotArrangedResp;
    const notRows: EhallNotArrangedRow[] =
      notParsed.datas !== undefined && notParsed.datas.cxxsllsywpk !== undefined
      && notParsed.datas.cxxsllsywpk.rows !== undefined ? notParsed.datas.cxxsllsywpk.rows : [];
    notRows.forEach((row: EhallNotArrangedRow): void => {
      preliminaryData.notArranged.push(new NotArrangementClassDetail(
        ClassTableSession.toStr(row.KCM), ClassTableSession.toStr(row.KCH), ClassTableSession.toStr(row.KXH),
        ClassTableSession.toStr(row.SKJS)));
    });

    // ---- 调课/停课/补课（对应 Dart xsdkkc 段与合并算法，逐行为照搬） ----
    const changeFields: Map<string, string> = new Map();
    changeFields.set('XNXQDM', semesterCode);
    changeFields.set('*order', '-SQSJ');
    const changeResp: SessionResponse = await session.postForm(EHALL_CHANGE_URL, changeFields);
    const changeParsed: EhallChangeResp = JSON.parse(changeResp.bodyText) as EhallChangeResp;
    const changeSection: EhallChangeSection | undefined =
      changeParsed.datas !== undefined ? changeParsed.datas.xsdkkc : undefined;
    if (changeSection !== undefined && changeSection.extParams !== undefined
      && `${changeSection.extParams.code ?? ''}` !== '1') {
      Log.warn(`[getEhall] xsdkkc: ${ClassTableSession.toStr(changeSection.extParams.msg)}`);
    }
    const changeRows: EhallChangeRow[] =
      changeSection !== undefined && changeSection.rows !== undefined ? changeSection.rows : [];

    const totalSize: number = changeSection !== undefined ? ClassTableSession.toInt(changeSection.totalSize, 0) : 0;
    if (totalSize > 0) {
      changeRows.forEach((row: EhallChangeRow): void => {
        preliminaryData.classChanges.push(new ClassChange(
          ClassTableSession.changeTypeOf(ClassTableSession.toStr(row.TKLXDM)),
          ClassTableSession.toStr(row.KCH),
          ClassTableSession.toStr(row.KXH),
          ClassTableSession.toStr(row.KCM),
          row.SKZC === undefined || row.SKZC === null ? null : ClassTableSession.weekListOf(row.SKZC),
          row.XSKZC === undefined || row.XSKZC === null ? null : ClassTableSession.weekListOf(row.XSKZC),
          ClassTableSession.toStr(row.YSKJS),
          ClassTableSession.toStr(row.XSKJS),
          [ClassTableSession.toInt(row.KSJC, -1), ClassTableSession.toInt(row.JSJC, -1)],
          [ClassTableSession.toInt(row.XKSJC, -1), ClassTableSession.toInt(row.XJSJC, -1)],
          row.SKXQ === undefined || row.SKXQ === null ? -1 : ClassTableSession.toInt(row.SKXQ, -1),
          row.XSKXQ === undefined || row.XSKXQ === null ? -1 : ClassTableSession.toInt(row.XSKXQ, -1),
          row.JASMC === undefined || row.JASMC === null ? '' : ClassTableSession.toStr(row.JASMC),
          row.XJASMC === undefined || row.XJASMC === null ? '' : ClassTableSession.toStr(row.XJASMC)
        ));
      });
    }

    Log.info(`[getEhall] dealing class change with ${preliminaryData.classChanges.length} info(s).`);
    ClassTableSession.mergeClassChanges(preliminaryData);
    return preliminaryData;
  }

  private static changeTypeOf(tklxdm: string): ChangeType {
    if (tklxdm === '01') {
      return ChangeType.Change;
    }
    if (tklxdm === '02') {
      return ChangeType.Stop;
    }
    return ChangeType.Patch;
  }

  /** 通用学期请求体：XNXQDM（+是否附学号 XH）。 */
  private static semesterFields(semesterCode: string, withAccount: boolean): Map<string, string> {
    const map: Map<string, string> = new Map();
    map.set('XNXQDM', semesterCode);
    if (withAccount) {
      map.set('XH', ClassTableSession.account());
    }
    return map;
  }

  private static dayFields(now: Date): Map<string, string> {
    const map: Map<string, string> = new Map();
    map.set('day', DateUtil.formatCompactDate(now));
    return map;
  }

  /**
   * 调课合并主算法（对应 Dart _getEhall 后半段 while 循环，逐行为照搬，含其处理顺序quirk）：
   * - 补课：在主课表中找到课程则追加一条排课；找不到则新建 ClassDetail。
   * - 停课：把原排课在受影响周次置 false。
   * - 调课：原排课受影响周次置 false 后追加新时段；跨条目配对（cache）防止重复添加。
   * - 一轮无进展即 break，防接口脏数据死循环。
   */
  private static mergeClassChanges(preliminaryData: ClassTableData): void {
    let toDeal: ClassChange[] = preliminaryData.classChanges.slice();
    const cache: ClassChange[] = [];

    while (toDeal.length > 0) {
      const previousLength: number = toDeal.length;
      const toBeRemovedIndex: number[] = [];
      for (let ei = 0; ei < toDeal.length; ei++) {
        const e: ClassChange = toDeal[ei];

        // 先找课程（接口不稳定，课程可能同名多班级号，因此是列表）。
        const indexClassDetailList: number[] = [];
        for (let i = 0; i < preliminaryData.classDetail.length; i++) {
          if (preliminaryData.classDetail[i].code === e.classCode) {
            indexClassDetailList.push(i);
          }
        }

        // 主课表中没有该课程：补课则新建条目，否则跳过。
        if (indexClassDetailList.length === 0) {
          if (e.type === ChangeType.Patch) {
            preliminaryData.classDetail.push(new ClassDetail(e.className, e.classCode, e.classNumber));
            const newIndex: number = preliminaryData.classDetail.length - 1;
            preliminaryData.timeArrangement.push(new TimeArrangement(
              ClassSource.School, newIndex,
              e.newAffectedWeeks !== null ? e.newAffectedWeeks : (e.originalAffectedWeeks !== null ? e.originalAffectedWeeks : []),
              e.newWeek >= 0 ? e.newWeek : (e.originalWeek >= 0 ? e.originalWeek : 0),
              e.newClassRange[0], e.newClassRange[1],
              e.isTeacherChanged() ? e.newTeacher() : e.originalTeacher(),
              e.newClassroom.length > 0 ? e.newClassroom : e.originalClassroom
            ));
          } else {
            Log.warn(`[mergeClassChanges] class ${e.className} (${e.classCode}) not in schedule, type ${e.type}, skip`);
          }
          toBeRemovedIndex.push(ei);
          continue;
        }

        // 补课：找到课程即追加（照搬 Dart：此分支 continue，不从 toDeal 移除）。
        if (e.type === ChangeType.Patch) {
          preliminaryData.timeArrangement.push(new TimeArrangement(
            ClassSource.School, indexClassDetailList[0],
            e.newAffectedWeeks !== null ? e.newAffectedWeeks : (e.originalAffectedWeeks !== null ? e.originalAffectedWeeks : []),
            e.newWeek >= 0 ? e.newWeek : (e.originalWeek >= 0 ? e.originalWeek : 0),
            e.newClassRange[0], e.newClassRange[1],
            e.isTeacherChanged() ? e.newTeacher() : e.originalTeacher(),
            e.newClassroom.length > 0 ? e.newClassroom : e.originalClassroom
          ));
          continue;
        }

        // 调课/停课：找与原星期、原节次区间一致的全部排课。
        const indexOriginalTimeArrangementList: number[] = [];
        for (let ci = 0; ci < indexClassDetailList.length; ci++) {
          const currentClassIndex: number = indexClassDetailList[ci];
          for (let i = 0; i < preliminaryData.timeArrangement.length; i++) {
            const t: TimeArrangement = preliminaryData.timeArrangement[i];
            if (t.index === currentClassIndex && t.day === e.originalWeek
              && t.start === e.originalClassRange[0] && t.stop === e.originalClassRange[1]) {
              indexOriginalTimeArrangementList.push(i);
            }
          }
        }
        if (indexOriginalTimeArrangementList.length === 0) {
          toBeRemovedIndex.push(ei);
          continue;
        }

        if (e.type === ChangeType.Change) {
          let timeArrangementIndex: number = indexOriginalTimeArrangementList[0];
          for (let li = 0; li < indexOriginalTimeArrangementList.length; li++) {
            const arrangement: TimeArrangement = preliminaryData.timeArrangement[indexOriginalTimeArrangementList[li]];
            const weeks: number[] = e.originalAffectedWeeksList();
            for (let wi = 0; wi < weeks.length; wi++) {
              const weekIdx: number = weeks[wi];
              if (weekIdx >= arrangement.weekList.length) {
                while (arrangement.weekList.length < weekIdx + 1) {
                  arrangement.weekList.push(false);
                }
                if (arrangement.weekList.length > preliminaryData.semesterLength) {
                  preliminaryData.semesterLength = arrangement.weekList.length;
                }
              }
              if (arrangement.weekList[weekIdx]) {
                arrangement.weekList[weekIdx] = false;
                timeArrangementIndex = arrangement.index;
              }
            }
          }

          // 没有实际置 false 过任何周：先挂进 cache 等配对（对应 Dart 逻辑）。
          if (timeArrangementIndex === indexOriginalTimeArrangementList[0]) {
            cache.push(e);
            timeArrangementIndex = preliminaryData.timeArrangement[indexOriginalTimeArrangementList[0]].index;
          }

          // 跨条目配对：本条的"新值"与 cache 中某条的"原值"一致 → 该新时段已添加过，跳过。
          let flag: boolean = false;
          let toRemove: number = -1;
          for (let fi = 0; fi < cache.length; fi++) {
            const f: ClassChange = cache[fi];
            if (f.className === e.className && f.classCode === e.classCode
              && ClassTableSession.listEquals(f.originalClassRange, e.newClassRange)
              && ClassTableSession.listEquals(f.originalAffectedWeeksList(), e.newAffectedWeeksList())
              && f.originalWeek === e.newWeek
              && f.originalClassroom === e.newClassroom
              && f.originalTeacherData === e.newTeacherData) {
              flag = true;
              toRemove = fi;
              break;
            }
          }
          if (flag) {
            cache.splice(toRemove, 1);
            continue;
          }

          preliminaryData.timeArrangement.push(new TimeArrangement(
            ClassSource.School, timeArrangementIndex,
            e.newAffectedWeeks !== null ? e.newAffectedWeeks : (e.originalAffectedWeeks !== null ? e.originalAffectedWeeks : []),
            e.newWeek >= 0 ? e.newWeek : (e.originalWeek >= 0 ? e.originalWeek : 0),
            e.newClassRange[0], e.newClassRange[1],
            e.isTeacherChanged() ? e.newTeacher() : e.originalTeacher(),
            e.newClassroom.length > 0 ? e.newClassroom : e.originalClassroom
          ));
        } else {
          // 停课：仅清周次。
          for (let li = 0; li < indexOriginalTimeArrangementList.length; li++) {
            const arrangement: TimeArrangement = preliminaryData.timeArrangement[indexOriginalTimeArrangementList[li]];
            const weeks: number[] = e.originalAffectedWeeksList();
            for (let wi = 0; wi < weeks.length; wi++) {
              const weekIdx: number = weeks[wi];
              if (weekIdx >= arrangement.weekList.length) {
                while (arrangement.weekList.length < weekIdx + 1) {
                  arrangement.weekList.push(false);
                }
                if (arrangement.weekList.length > preliminaryData.semesterLength) {
                  preliminaryData.semesterLength = arrangement.weekList.length;
                }
              }
              if (arrangement.weekList[weekIdx]) {
                arrangement.weekList[weekIdx] = false;
              }
            }
          }
        }
        toBeRemovedIndex.push(ei);
      }

      toDeal = toDeal.filter((_value: ClassChange, index: number): boolean => !toBeRemovedIndex.includes(index));
      Log.info(`[mergeClassChanges] after this turn, ${toDeal.length} left, removed ${toBeRemovedIndex.length}.`);

      // 安全阀：一轮无进展，剩余条目无法解决，避免死循环（对应 Dart 保护）。
      if (toDeal.length === previousLength) {
        Log.warn(`[mergeClassChanges] no progress, ${toDeal.length} change(s) unresolved, break.`);
        break;
      }
    }
  }

  /**
   * 连续节次合并（对应 Dart getYjspt "Post deal"）：
   * 同课程下按 (weekList, day, classroom) 分组，节次区间首尾相接的合并为一条。
   */
  private static mergeConsecutiveSections(data: ClassTableData): TimeArrangement[] {
    const newStuff: TimeArrangement[] = [];
    for (let i = 0; i < data.classDetail.length; i++) {
      const mine: TimeArrangement[] = data.timeArrangement.filter((t: TimeArrangement): boolean => t.index === i);
      const entries: number[] = [];
      for (let j = 0; j < mine.length; j++) {
        const id: number = ClassTableSession.courseId(mine[j]);
        if (!entries.includes(id)) {
          entries.push(id);
        }
      }
      for (let j = 0; j < entries.length; j++) {
        const result: TimeArrangement[] =
          mine.filter((t: TimeArrangement): boolean => ClassTableSession.courseId(t) === entries[j])
            .sort((a: TimeArrangement, b: TimeArrangement): number => a.start - b.start);
        if (result.length === 0) {
          continue;
        }
        const proto: number[] = [];
        result.forEach((t: TimeArrangement): void => {
          proto.push(t.start);
          proto.push(t.stop);
        });
        proto.sort((a: number, b: number): number => a - b);
        const groups: number[][] = [[]];
        for (let p = 0; p < proto.length; p++) {
          const last: number[] = groups[groups.length - 1];
          if (last.length === 0 || last[last.length - 1] === proto[p] - 1) {
            last.push(proto[p]);
          } else {
            groups.push([proto[p]]);
          }
        }
        for (let g = 0; g < groups.length; g++) {
          const group: number[] = groups[g];
          newStuff.push(new TimeArrangement(
            ClassSource.School, i, result[0].weekList, result[0].day, group[0], group[group.length - 1],
            result[0].teacher, result[0].classroom
          ));
        }
      }
    }
    return newStuff;
  }

  private static courseId(t: TimeArrangement): number {
    return ClassTableSession.stringHash(`${JSON.stringify(t.weekList)}-${t.day}-${t.classroom}`);
  }

  private static stringHash(text: string): number {
    let hash: number = 0;
    for (let i = 0; i < text.length; i++) {
      hash = (hash * 31 + text.charCodeAt(i)) | 0;
    }
    return hash;
  }
}
