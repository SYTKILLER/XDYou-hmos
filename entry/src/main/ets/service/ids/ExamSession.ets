import { IdsSession } from './IdsSession';
import { backgroundSliderHandler } from './BackgroundSlider';
import { AppContext } from '../AppContext';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { FetchResult } from '../../model/FetchResult';
import { ExamData, Subject, ToBeArranged, ExamDataJson } from '../../model/exam/ExamData';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状 ----

interface ExtParams {
  code?: string | number;
  msg?: string | number;
}

interface EhallExamRow {
  KCM?: string;
  KSMC?: string | null;
  KSSJMS?: string | null;
  JASMC?: string | null;
  ZWH?: string | null;
}

interface EhallWdksapSection {
  extParams?: ExtParams;
  rows?: EhallExamRow[] | null;
}

interface EhallWdksapDatas {
  wdksap?: EhallWdksapSection;
}

interface EhallWdksapResp {
  code?: string | number;
  datas?: EhallWdksapDatas;
}

interface EhallTbaRow {
  KCM?: string;
  KCH?: string;
}

interface EhallTbaSection {
  extParams?: ExtParams;
  rows?: EhallTbaRow[] | null;
}

interface EhallTbaDatas {
  cxyxkwapkwdkc?: EhallTbaSection;
}

interface EhallTbaResp {
  code?: string | number;
  datas?: EhallTbaDatas;
}

interface YjsptExamRow {
  KCMC?: string;
  KSLXDM_DISPLAY?: string;
  KSSJMS?: string;
  JASMC?: string;
}

interface YjsptExamSection {
  rows?: YjsptExamRow[] | null;
}

interface YjsptExamDatas {
  wdksxxcx?: YjsptExamSection;
}

interface YjsptExamResp {
  datas?: YjsptExamDatas;
}

const EHALL_EXAM_APP_URL: string = 'https://ehall.xidian.edu.cn/appShow?appId=4768687067472349';
const EHALL_WDKSAP_URL: string =
  'https://ehall.xidian.edu.cn/jwapp/sys/studentWdksapApp/modules/wdksap/wdksap.do';
const EHALL_TBA_URL: string =
  'https://ehall.xidian.edu.cn/jwapp/sys/studentWdksapApp/modules/wdksap/cxyxkwapkwdkc.do';
const YJSPT_EXAM_INDEX_URL: string = 'https://yjspt.xidian.edu.cn/gsapp/sys/wdksapp/*default/index.do';
const YJSPT_EXAM_URL: string = 'https://yjspt.xidian.edu.cn/gsapp/sys/wdksapp/modules/ksxxck/wdksxxcx.do';

/**
 * 考试安排抓取（对应 Dart repository/ids_session/exam_session.dart）。
 * 本科 ehall wdksap（含"已选课未安排考务"查询）；研究生 yjspt wdksxxcx（querySetting JSON 过滤已发布）。
 * 注意 dio queryParameters 是拼 URL 查询串，ArkTS 侧同样拼 URL（不进表单体）。失败回退 exam.json 缓存。
 */
export class ExamSession {
  static readonly CACHE_FILE: string = 'exam.json';

  static async getExamInfo(semester: string, isPostgraduate: boolean): Promise<FetchResult<ExamData>> {
    try {
      const data: ExamData = isPostgraduate
        ? await ExamSession.getYjspt(semester)
        : await ExamSession.getEhall(semester);
      AppContext.writeCacheText(ExamSession.CACHE_FILE, JSON.stringify(data.toCacheJson()));
      return FetchResult.fresh<ExamData>(data);
    } catch (e) {
      const cached: ExamData | null = ExamSession.getCacheData();
      if (cached !== null) {
        Log.warn(`getExamInfo failed, fallback cache: ${e}`);
        return FetchResult.cached<ExamData>(cached, ExamSession.cacheFetchTime(), 'exam.cache_hint_network_failed');
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new Error(`${e}`);
    }
  }

  static getCacheData(): ExamData | null {
    const text: string | null = AppContext.readCacheText(ExamSession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return null;
    }
    try {
      return ExamData.fromCacheJson(JSON.parse(text) as ExamDataJson);
    } catch (e) {
      Log.warn(`exam cache parse failed: ${e}`);
      return null;
    }
  }

  static cacheFetchTime(): number {
    return AppContext.cacheModifiedMs(ExamSession.CACHE_FILE);
  }

  static deleteCache(): void {
    AppContext.deleteCache(ExamSession.CACHE_FILE);
  }

  private static account(): string {
    return PreferenceService.getString('idsAccount', '');
  }

  private static async loginAndFollow(target: string): Promise<void> {
    const slider = backgroundSliderHandler();
    const location: string = await IdsSession.checkAndLogin(target, slider);
    await IdsSession.followRedirects(location);
  }

  /** 本科：ehall wdksap + cxyxkwapkwdkc。 */
  private static async getEhall(semester: string): Promise<ExamData> {
    const session: NetworkSession = SessionManager.ids();
    await ExamSession.loginAndFollow(EHALL_EXAM_APP_URL);

    const wdksapUrl: string =
      `${EHALL_WDKSAP_URL}?XNXQDM=${encodeURIComponent(semester)}&*order=${encodeURIComponent('-KSRQ,-KSSJMS')}`;
    const resp: SessionResponse = await session.postForm(wdksapUrl, new Map<string, string>());
    const parsed: EhallWdksapResp = JSON.parse(resp.bodyText) as EhallWdksapResp;
    const section: EhallWdksapSection | undefined =
      parsed.datas !== undefined ? parsed.datas.wdksap : undefined;
    if (`${parsed.code ?? ''}` !== '0' || section === undefined || section.rows === null
      || section.rows === undefined) {
      const msg: string = section !== undefined && section.extParams !== undefined
        && section.extParams.msg !== undefined && section.extParams.msg !== null
        ? `${section.extParams.msg}` : '';
      if (msg.length > 0) {
        throw new Error(`未安排考试信息获取失败：${msg}`);
      }
      throw new Error('考试信息获取失败：无法解析数据');
    }
    const subject: Subject[] = [];
    section.rows.forEach((row: EhallExamRow): void => {
      subject.push(Subject.generate(
        row.KCM !== undefined ? row.KCM : '',
        row.KSMC !== undefined && row.KSMC !== null ? row.KSMC : '未知类型考试',
        row.KSSJMS !== undefined && row.KSSJMS !== null ? row.KSSJMS : '未知考试时间',
        row.JASMC !== undefined && row.JASMC !== null ? row.JASMC : '尚无安排',
        row.ZWH !== undefined && row.ZWH !== null ? row.ZWH : '未知座位'
      ));
    });

    const tbaUrl: string = `${EHALL_TBA_URL}?XNXQDM=${encodeURIComponent(semester)}`;
    const tbaResp: SessionResponse = await session.postForm(tbaUrl, new Map<string, string>());
    const tbaParsed: EhallTbaResp = JSON.parse(tbaResp.bodyText) as EhallTbaResp;
    const tbaSection: EhallTbaSection | undefined =
      tbaParsed.datas !== undefined ? tbaParsed.datas.cxyxkwapkwdkc : undefined;
    if (`${tbaParsed.code ?? ''}` !== '0' || tbaSection === undefined || tbaSection.rows === null
      || tbaSection.rows === undefined) {
      const msg: string = tbaSection !== undefined && tbaSection.extParams !== undefined
        && tbaSection.extParams.msg !== undefined && tbaSection.extParams.msg !== null
        ? `${tbaSection.extParams.msg}` : '';
      if (msg.length > 0) {
        throw new Error(`未安排考试信息获取失败：${msg}`);
      }
      throw new Error('未安排考试信息获取失败：无法解析数据');
    }
    const toBeArranged: ToBeArranged[] = [];
    tbaSection.rows.forEach((row: EhallTbaRow): void => {
      toBeArranged.push(new ToBeArranged(row.KCM !== undefined ? row.KCM : '', row.KCH !== undefined ? row.KCH : ''));
    });

    const data: ExamData = new ExamData();
    data.subject = subject;
    data.toBeArranged = toBeArranged;
    return data;
  }

  /** 研究生：yjspt wdksxxcx（querySetting 过滤 SFFBKSAP=1）。 */
  private static async getYjspt(semester: string): Promise<ExamData> {
    const session: NetworkSession = SessionManager.ids();
    await ExamSession.loginAndFollow(YJSPT_EXAM_INDEX_URL);

    const querySetting: string = '['
      + '{"name":"XNXQDM","caption":"学年学期代码","builder":"equal","linkOpt":"AND","value":"' + semester + '"},'
      + '{"name":"SFFBKSAP","caption":"是否发布考试安排","builder":"equal","linkOpt":"AND","value":"1"},'
      + '{"name":"XH","caption":"学号","builder":"equal","linkOpt":"AND","value":"' + ExamSession.account() + '"},'
      + '{"name":"KSAPWID","caption":"考试安排WID","builder":"notEqual","linkOpt":"AND","value":null}'
      + ']';
    const url: string = `${YJSPT_EXAM_URL}?querySetting=${encodeURIComponent(querySetting)}`
      + `&pageSize=${1000}&pageNumber=${1}`;
    const resp: SessionResponse = await session.postForm(url, new Map<string, string>());
    const parsed: YjsptExamResp = JSON.parse(resp.bodyText) as YjsptExamResp;
    let rows: YjsptExamRow[] = [];
    if (parsed.datas !== undefined && parsed.datas.wdksxxcx !== undefined
      && parsed.datas.wdksxxcx.rows !== undefined && parsed.datas.wdksxxcx.rows !== null) {
      rows = parsed.datas.wdksxxcx.rows;
    }

    const data: ExamData = new ExamData();
    rows.forEach((row: YjsptExamRow): void => {
      data.subject.push(Subject.generate(
        row.KCMC !== undefined ? row.KCMC : '',
        row.KSLXDM_DISPLAY !== undefined ? row.KSLXDM_DISPLAY : '',
        row.KSSJMS !== undefined ? row.KSSJMS : '',
        row.JASMC !== undefined ? row.JASMC : '',
        ''));
    });
    Log.info(`[ExamSession][yjspt] fetched ${data.subject.length} subject(s)`);
    return data;
  }
}
