import { IdsSession } from './IdsSession';
import { backgroundSliderHandler } from './BackgroundSlider';
import { AppContext } from '../AppContext';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { FetchResult } from '../../model/FetchResult';
import { Score, ComposeDetail, ScoreJson, scoreFromJson, scoreToJson } from '../../model/score/ScoreData';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状 ----

interface ExtParams {
  code?: string | number;
  msg?: string | number;
}

interface EhallScoreRow {
  XSKCM?: string;
  ZCJ?: string | number | null;
  XNXQDM?: string;
  XF?: string | number;
  XGXKLBDM_DISPLAY?: string | null;
  KCXZDM_DISPLAY?: string | null;
  KCLBDM_DISPLAY?: string | null;
  CXCKDM_DISPLAY?: string | null;
  DJCJLXDM?: string | number;
  DJCJMC?: string | null;
  SFJG?: string | number | null;
  JXBID?: string | null;
  XM?: string | null;
}

interface EhallScoreSection {
  extParams?: ExtParams;
  rows?: EhallScoreRow[];
}

interface EhallScoreDatas {
  xscjcx?: EhallScoreSection;
}

interface EhallScoreResp {
  datas?: EhallScoreDatas;
}

interface YjsptScoreRow {
  KCMC?: string;
  DYBFZCJ?: string | number | null;
  XNXQDM_DISPLAY?: string;
  XF?: string | number;
  KCLBMC?: string;
  CJFZDM?: string | number;
  CJXSZ?: string | null;
  SFJG?: string | number | null;
  KCDM?: string | null;
  KSXZDM_DISPLAY?: string;
  XM?: string | null;
}

interface YjsptScoreSection {
  extParams?: ExtParams;
  rows?: YjsptScoreRow[];
}

interface YjsptScoreDatas {
  xscjcx?: YjsptScoreSection;
}

interface YjsptScoreResp {
  datas?: YjsptScoreDatas;
}

interface ComposeRow {
  GCXKHLRCJGS?: string | null;
  KCGCXKHLRCJ?: string | null;
}

interface ComposeSection {
  rows?: ComposeRow[];
}

interface ComposeDatas {
  cxkckgcxlrcj?: ComposeSection;
}

interface ComposeResp {
  datas?: ComposeDatas;
}

const EHALL_SCORE_APP_URL: string = 'https://ehall.xidian.edu.cn/appShow?appId=4768574631264620';
const EHALL_SCORE_URL: string = 'https://ehall.xidian.edu.cn/jwapp/sys/cjcx/modules/cjcx/xscjcx.do';
const EHALL_COMPOSE_URL: string =
  'https://ehall.xidian.edu.cn/jwapp/sys/cjcx/modules/cjcx/cxkckgcxlrcj.do';
const YJSPT_SCORE_INDEX_URL: string = 'https://yjspt.xidian.edu.cn/gsapp/sys/wdcjapp/*default/index.do';
const YJSPT_SCORE_URL: string = 'https://yjspt.xidian.edu.cn/gsapp/sys/wdcjapp/modules/wdcj/xscjcx.do';

/**
 * 成绩抓取（对应 Dart repository/ids_session/score_session.dart）。
 * 本科 ehall cjcx/xscjcx.do（POST 表单体，querySetting 过滤 SFYX=1）；研究生 yjspt wdcj/xscjcx.do；
 * 另有单科成绩组成查询 cxkckgcxlrcj.do（教学班公式 + 明细解析）。
 * 缓存策略：先读 scores.json，失败回退（与 Dart 相同）。
 */
export class ScoreSession {
  static readonly CACHE_FILE: string = 'scores.json';

  static async getScore(isPostgraduate: boolean): Promise<FetchResult<Score[]>> {
    const cache: Score[] = ScoreSession.getCacheData();
    try {
      const fresh: Score[] = isPostgraduate ? await ScoreSession.getYjspt() : await ScoreSession.getEhall();
      ScoreSession.writeCache(fresh);
      return FetchResult.fresh<Score[]>(fresh);
    } catch (e) {
      if (cache.length > 0) {
        Log.warn(`getScore failed, fallback cache: ${e}`);
        return FetchResult.cached<Score[]>(cache, ScoreSession.cacheFetchTime(), 'score.cache_hint_network_failed');
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new Error(`${e}`);
    }
  }

  static getCacheData(): Score[] {
    const text: string | null = AppContext.readCacheText(ScoreSession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return [];
    }
    try {
      const arr: ScoreJson[] = JSON.parse(text) as ScoreJson[];
      const list: Score[] = [];
      arr.forEach((j: ScoreJson, index: number): void => {
        list.push(scoreFromJson(j, index));
      });
      return list;
    } catch (e) {
      Log.warn(`score cache parse failed: ${e}`);
      return [];
    }
  }

  private static writeCache(list: Score[]): void {
    const arr: ScoreJson[] = [];
    list.forEach((s: Score): void => {
      arr.push(scoreToJson(s));
    });
    AppContext.writeCacheText(ScoreSession.CACHE_FILE, JSON.stringify(arr));
  }

  static cacheFetchTime(): number {
    return AppContext.cacheModifiedMs(ScoreSession.CACHE_FILE);
  }

  static deleteCache(): void {
    AppContext.deleteCache(ScoreSession.CACHE_FILE);
  }

  private static toStr(v: string | number | null | undefined): string {
    return v === undefined || v === null ? '' : `${v}`;
  }

  private static toNum(v: string | number | null | undefined): number | null {
    if (v === undefined || v === null) {
      return null;
    }
    if (typeof v === 'number') {
      return v;
    }
    const parsed: number = parseFloat(v);
    return isNaN(parsed) ? null : parsed;
  }

  private static account(): string {
    return PreferenceService.getString('idsAccount', '');
  }

  private static async loginAndFollow(target: string): Promise<void> {
    const slider = backgroundSliderHandler();
    const location: string = await IdsSession.checkAndLogin(target, slider);
    await IdsSession.followRedirects(location);
  }

  /** 响应中带学生姓名则尽力写入 displayName（成绩模块补充本科生姓名来源）。 */
  private static tryExtractName(name: string | null | undefined): void {
    const value: string = ScoreSession.toStr(name);
    if (value.length > 0) {
      PreferenceService.putString('displayName', value);
    }
  }

  private static async getEhall(): Promise<Score[]> {
    const session: NetworkSession = SessionManager.ids();
    await ScoreSession.loginAndFollow(EHALL_SCORE_APP_URL);

    const fields: Map<string, string> = new Map();
    fields.set('*json', '1');
    fields.set('querySetting',
      '{"name":"SFYX","value":"1","linkOpt":"and","builder":"m_value_equal"}');
    fields.set('*order', '+XNXQDM,KCH,KXH');
    fields.set('pageSize', '1000');
    fields.set('pageNumber', '1');
    const resp: SessionResponse = await session.postForm(EHALL_SCORE_URL, fields);
    const parsed: EhallScoreResp = JSON.parse(resp.bodyText) as EhallScoreResp;
    const section: EhallScoreSection | undefined =
      parsed.datas !== undefined ? parsed.datas.xscjcx : undefined;
    if (section === undefined || section.extParams === undefined
      || `${section.extParams.code ?? ''}` !== '1' || section.rows === undefined || section.rows === null) {
      const msg: string = section !== undefined && section.extParams !== undefined
        ? ScoreSession.toStr(section.extParams.msg) : '';
      throw new Error(msg.length > 0 ? msg : '成绩信息获取失败：无法解析数据');
    }

    const toReturn: Score[] = [];
    let mark: number = 0;
    section.rows.forEach((row: EhallScoreRow): void => {
      ScoreSession.tryExtractName(row.XM);
      const xgxk: string = ScoreSession.toStr(row.XGXKLBDM_DISPLAY);
      toReturn.push(new Score(
        mark,
        ScoreSession.toStr(row.XSKCM),
        ScoreSession.toNum(row.ZCJ),
        ScoreSession.toStr(row.XNXQDM),
        ScoreSession.toNum(row.XF) ?? 0,
        xgxk.length === 0 ? ScoreSession.toStr(row.KCXZDM_DISPLAY) : `选修 ${xgxk}`,
        ScoreSession.toStr(row.KCLBDM_DISPLAY),
        ScoreSession.toStr(row.CXCKDM_DISPLAY),
        ScoreSession.toInt(ScoreSession.toStr(row.DJCJLXDM)),
        ScoreSession.toStr(row.DJCJMC),
        ScoreSession.toStr(row.SFJG),
        ScoreSession.toStr(row.JXBID)
      ));
      mark++;
    });
    return toReturn;
  }

  private static toInt(text: string): number {
    const parsed: number = parseInt(text, 10);
    return isNaN(parsed) ? 0 : parsed;
  }

  private static async getYjspt(): Promise<Score[]> {
    const session: NetworkSession = SessionManager.ids();
    await ScoreSession.loginAndFollow(YJSPT_SCORE_INDEX_URL);

    const fields: Map<string, string> = new Map();
    fields.set('querySetting', '[]');
    fields.set('pageSize', '1000');
    fields.set('pageNumber', '1');
    const resp: SessionResponse = await session.postForm(YJSPT_SCORE_URL, fields);
    const parsed: YjsptScoreResp = JSON.parse(resp.bodyText) as YjsptScoreResp;
    const section: YjsptScoreSection | undefined =
      parsed.datas !== undefined ? parsed.datas.xscjcx : undefined;
    if (section === undefined || section.extParams === undefined
      || `${section.extParams.code ?? ''}` !== '1' || section.rows === undefined || section.rows === null) {
      const msg: string = section !== undefined && section.extParams !== undefined
        ? ScoreSession.toStr(section.extParams.msg) : '';
      throw new Error(msg.length > 0 ? msg : '成绩信息获取失败：无法解析数据');
    }

    const toReturn: Score[] = [];
    let mark: number = 0;
    section.rows.forEach((row: YjsptScoreRow): void => {
      ScoreSession.tryExtractName(row.XM);
      const fjdm: string = ScoreSession.toStr(row.CJFZDM);
      toReturn.push(new Score(
        mark,
        ScoreSession.toStr(row.KCMC),
        ScoreSession.toNum(row.DYBFZCJ),
        ScoreSession.toStr(row.XNXQDM_DISPLAY),
        ScoreSession.toNum(row.XF) ?? 0,
        ScoreSession.toStr(row.KCLBMC),
        ScoreSession.toStr(row.KCLBMC),
        ScoreSession.toStr(row.KSXZDM_DISPLAY),
        ScoreSession.toInt(fjdm),
        fjdm !== '0' ? ScoreSession.toStr(row.CJXSZ) : '',
        ScoreSession.toStr(row.SFJG),
        ScoreSession.toStr(row.KCDM)
      ));
      mark++;
    });
    return toReturn;
  }

  /**
   * 单科成绩组成（对应 Dart getDetail）：
   * GCXKHLRCJGS 公式（"平时成绩 * 0.3 + ... = 总评成绩"）与 KCGCXKHLRCJ 明细（"平时成绩:90,..."）配对。
   * 教学班为空或查询失败返回占位条目（照搬 Dart 行为）。
   */
  static async getDetail(classID: string, semesterCode: string, needRelogin: boolean): Promise<ComposeDetail[]> {
    if (classID.length === 0) {
      return [new ComposeDetail('教学班编号', '未知', '无法查询')];
    }
    try {
      const session: NetworkSession = SessionManager.ids();
      if (needRelogin) {
        await ScoreSession.loginAndFollow(EHALL_SCORE_APP_URL);
      }
      const fields: Map<string, string> = new Map();
      fields.set('JXBID', classID);
      fields.set('XH', ScoreSession.account());
      fields.set('XNXQDM', semesterCode);
      fields.set('CKLY', '1');
      const resp: SessionResponse = await session.postForm(EHALL_COMPOSE_URL, fields);
      const parsed: ComposeResp = JSON.parse(resp.bodyText) as ComposeResp;
      const rows: ComposeRow[] =
        parsed.datas !== undefined && parsed.datas.cxkckgcxlrcj !== undefined
        && parsed.datas.cxkckgcxlrcj.rows !== undefined ? parsed.datas.cxkckgcxlrcj.rows : [];
      if (rows.length === 0 || rows[0].GCXKHLRCJGS === null || rows[0].GCXKHLRCJGS === undefined) {
        return [];
      }

      const formula: string[] = rows[0].GCXKHLRCJGS.split(/ \+ |\*| = /);
      const detailList: string[] = ScoreSession.toStr(rows[0].KCGCXKHLRCJ).split(',');
      const detail: Map<string, string> = new Map();
      detailList.forEach((v: string): void => {
        const kv: string[] = v.split(':');
        if (kv.length >= 2) {
          detail.set(kv[0], kv[1]);
        }
      });

      const toReturn: ComposeDetail[] = [];
      let i: number = 0;
      while (i < formula.length) {
        if (formula[i] === '总评成绩') {
          i++;
          continue;
        }
        if (i + 1 >= formula.length) {
          break;
        }
        toReturn.push(new ComposeDetail(
          formula[i],
          `${Math.round(ScoreSession.parseRatio(formula[i + 1]) * 1000) / 10}%`,
          detail.get(formula[i]) !== undefined ? detail.get(formula[i]) as string : '未登记'
        ));
        i += 2;
      }
      return toReturn;
    } catch (e) {
      Log.warn(`score getDetail failed: ${e}`);
      return [new ComposeDetail('', '获取详情失败', '')];
    }
  }

  /** 占比解析（parseFloat 失败按 0）。 */
  private static parseRatio(text: string): number {
    const parsed: number = parseFloat(text);
    return isNaN(parsed) ? 0 : parsed;
  }
}
