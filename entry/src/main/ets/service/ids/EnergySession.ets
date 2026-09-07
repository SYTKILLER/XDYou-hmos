import { IdsSession } from './IdsSession';
import { backgroundSliderHandler } from './BackgroundSlider';
import { AppContext } from '../AppContext';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { FetchResult } from '../../model/FetchResult';
import { EnergyInfo, ElectricityHistoryInfo, MeterInfo,
  EnergyInfoJson, ElectricityHistoryJson } from '../../model/energy/EnergyData';
import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { DateUtil } from '../../utils/date/DateUtil';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状（字段名为 ignypt 接口原文，注意 ResData 在不同接口下是数组或对象） ----

interface SignatureData {
  timestamp?: string | number;
  signature?: string;
}

interface SignatureResp {
  data?: SignatureData;
}

interface NodeInfo {
  NodeID?: string;
}

interface NodeArrayResp {
  ResData?: NodeInfo[];
}

interface MeterListRow {
  MediumCode?: string | number;
  LastNum?: string | number;
  MetID?: string;
  LastReadDate?: string;
}

interface MeterListData {
  rows?: MeterListRow[];
}

interface MeterListResp {
  ResData?: MeterListData;
}

interface MetReadRow {
  ReadTime?: string;
  ReadNum?: string | number;
  StartNum?: string | number;
  EndNum?: string | number;
}

interface MetReadData {
  rows?: MetReadRow[];
}

interface MetReadResp {
  ResData?: MetReadData;
}

interface OauthReq {
  CODE: string;
}

interface LoginReq {
  UserID: string;
  Pwd: string;
  IsCehckPwd: number;
  NodeID: string;
}

interface NodeReq {
  NodeID: string;
}

interface MetReadReq {
  MetID: string;
  ReadTimeS: string;
  ReadTimeE: string;
  ReadNum: string;
}

const XXCAPP_OAUTH_URL: string =
  'https://xxcapp.xidian.edu.cn/uc/api/oauth/index?redirect=https://ignypt.xidian.edu.cn/revenueH5/login?opcode=MPAY&appid=200260318155520600&state=12312312312312&qrcode=0';
const SIGNATURE_URL: string = 'https://ignypt.xidian.edu.cn/baseNew/api/User/GetSignature';
const OAUTH_USER_INFO_URL: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/OauthGetUserInfo';
const LOGIN_URL: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/H5UserIDLogIn';
const METER_LIST_URL: string = 'https://ignypt.xidian.edu.cn/estManage/api/wechat/v2/H5QueryMeterList';
const MET_READ_URL: string = 'https://ignypt.xidian.edu.cn/estManage/api/WeChat/V2/GetMetRead';

/**
 * 电费/能耗抓取（对应 Dart repository/ids_session/energy_session.dart，2026-04 新能耗系统）。
 * 协议要点：
 * 1. 仅校园网环境可访问 ignypt.xidian.edu.cn；
 * 2. 每个请求先 POST GetSignature 换 timestamp/signature 塞请求头（OpCode=MPAY）；
 * 3. 业务参数 JSON 序列化后 AES-128-CBC-PKCS7（key=iv="1234567812345678"）加密，
 *    GET 走 ?content=<urlencoded base64>，POST 走 JSON 体 {"content": ...}；
 * 4. CAS → xxcapp oauth 续跳落地页 URL 的 code 参数换登录态。
 * 缓存：EnergyInfo.json 快照 + ElectricityHistory.json 本地余量历史（最多 15 条，同日去重）。
 * 待真机验证点：GET 的 content 编码层次（Dart dio 对已 encodeComponent 的值可能二次编码，若失败试双重编码）。
 */
export class EnergySession {
  static readonly CACHE_FILE: string = 'EnergyInfo.json';
  static readonly HISTORY_FILE: string = 'ElectricityHistory.json';
  private static readonly AES_KEY: string = '1234567812345678';
  private static readonly AES_IV: string = '1234567812345678';

  static async getElectricityInfo(): Promise<FetchResult<EnergyInfo>> {
    const cache: EnergyInfo | null = EnergySession.getCacheData();
    try {
      const fresh: EnergyInfo = await EnergySession.requestNewEnergyInfo();
      AppContext.writeCacheText(EnergySession.CACHE_FILE, JSON.stringify(fresh.toCacheJson()));
      return FetchResult.fresh<EnergyInfo>(fresh);
    } catch (e) {
      if (cache !== null) {
        Log.warn(`getElectricityInfo failed, fallback cache: ${e}`);
        return FetchResult.cached<EnergyInfo>(cache, EnergySession.cacheFetchTime(),
          EnergySession.hintFromError(`${e}`));
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new Error(`${e}`);
    }
  }

  static getCacheData(): EnergyInfo | null {
    const text: string | null = AppContext.readCacheText(EnergySession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return null;
    }
    try {
      return EnergyInfo.fromCacheJson(JSON.parse(text) as EnergyInfoJson);
    } catch (e) {
      Log.warn(`energy cache parse failed: ${e}`);
      return null;
    }
  }

  static cacheFetchTime(): number {
    return AppContext.cacheModifiedMs(EnergySession.CACHE_FILE);
  }

  static deleteCache(): void {
    AppContext.deleteCache(EnergySession.CACHE_FILE);
  }

  private static hintFromError(message: string): string {
    if (message.includes('校园网') || message.includes('不得访问') || message.includes('拒绝')) {
      return 'electricity.not_school_network';
    }
    if (message.includes('用户名或密码')) {
      return 'electricity.cache_hint_password_wrong';
    }
    if (message.includes('验证码')) {
      return 'electricity.cache_hint_captcha_failed';
    }
    return 'electricity.cache_hint_network_failed';
  }

  // ---- 本地余量历史 ----

  static getHistory(): ElectricityHistoryInfo[] {
    const text: string | null = AppContext.readCacheText(EnergySession.HISTORY_FILE);
    const list: ElectricityHistoryInfo[] = [];
    if (text === null || text.length === 0) {
      return list;
    }
    try {
      const arr: ElectricityHistoryJson[] = JSON.parse(text) as ElectricityHistoryJson[];
      arr.forEach((j: ElectricityHistoryJson): void => {
        const day: Date | null = DateUtil.parseDateTime(j.fetchDay !== undefined ? j.fetchDay : '');
        if (day !== null) {
          list.push(new ElectricityHistoryInfo(day, j.remain !== undefined ? j.remain : ''));
        }
      });
      list.sort((a: ElectricityHistoryInfo, b: ElectricityHistoryInfo): number =>
        a.fetchDay.getTime() - b.fetchDay.getTime());
    } catch (e) {
      Log.warn(`energy history parse failed: ${e}`);
    }
    return list;
  }

  static saveHistory(list: ElectricityHistoryInfo[]): void {
    const arr: ElectricityHistoryJson[] = [];
    list.forEach((h: ElectricityHistoryInfo): void => {
      arr.push({ fetchDay: DateUtil.formatFull(h.fetchDay), remain: h.remain });
    });
    AppContext.writeCacheText(EnergySession.HISTORY_FILE, JSON.stringify(arr));
  }

  static clearHistory(): void {
    AppContext.deleteCache(EnergySession.HISTORY_FILE);
  }

  // ---- 协议 ----

  private static async loginAndFollow(target: string): Promise<SessionResponse> {
    const slider = backgroundSliderHandler();
    const location: string = await IdsSession.checkAndLogin(target, slider);
    return IdsSession.followRedirects(location);
  }

  /** URL 查询参数提取（followRedirects 落地页取 oauth code）。 */
  private static queryParam(url: string, key: string): string {
    let rest: string = url;
    const hashIdx: number = rest.indexOf('#');
    if (hashIdx >= 0) {
      rest = rest.substring(0, hashIdx);
    }
    const qIdx: number = rest.indexOf('?');
    if (qIdx < 0) {
      return '';
    }
    const pairs: string[] = rest.substring(qIdx + 1).split('&');
    for (let i = 0; i < pairs.length; i++) {
      const eq: number = pairs[i].indexOf('=');
      if (eq <= 0) {
        continue;
      }
      if (pairs[i].substring(0, eq) === key) {
        try {
          return decodeURIComponent(pairs[i].substring(eq + 1));
        } catch (e) {
          return pairs[i].substring(eq + 1);
        }
      }
    }
    return '';
  }

  private static toNum(v: string | number | null | undefined): number {
    if (typeof v === 'number') {
      return v;
    }
    const parsed: number = parseFloat(v === undefined || v === null ? '' : v);
    return isNaN(parsed) ? 0 : parsed;
  }

  /**
   * ignypt 通用请求（对应 Dart _request）：GetSignature 换头 + AES-CBC-PKCS7 加密 content。
   */
  private static async request(session: NetworkSession, url: string, data: object,
    isGetMethod: boolean): Promise<SessionResponse> {
    const signBody: string = JSON.stringify({ data: '', access_token: '', OpCode: 'MPAY', RequestID: '' });
    const signResp: SessionResponse =
      await session.postRaw(SIGNATURE_URL, 'application/json', signBody, new SessionOptions());
    const signParsed: SignatureResp = JSON.parse(signResp.bodyText) as SignatureResp;
    const timestamp: string =
      signParsed.data !== undefined && signParsed.data.timestamp !== undefined ? `${signParsed.data.timestamp}` : '';
    const signature: string =
      signParsed.data !== undefined && signParsed.data.signature !== undefined ? signParsed.data.signature : '';

    const payload: string = JSON.stringify(data);
    const encrypted: Uint8Array = await CryptoUtil.aesCbcEncryptPkcs7(
      CryptoUtil.utf8Bytes(EnergySession.AES_KEY),
      CryptoUtil.utf8Bytes(EnergySession.AES_IV),
      CryptoUtil.utf8Bytes(payload));
    const content: string = CryptoUtil.base64Encode(encrypted);

    const options: SessionOptions = new SessionOptions();
    options.headers.set('timestamp', timestamp);
    options.headers.set('signature', signature);
    options.headers.set('OpCode', 'MPAY');
    options.headers.set('OrgId', '');
    options.headers.set('RequestID', '');
    if (isGetMethod) {
      return session.get(`${url}?content=${encodeURIComponent(content)}`, options);
    }
    options.hasBody = true;
    options.body = JSON.stringify({ content: content });
    options.contentType = 'application/json';
    return session.postRaw(url, 'application/json', options.body, options);
  }

  private static async requestNewEnergyInfo(): Promise<EnergyInfo> {
    const session: NetworkSession = SessionManager.ids();
    const landing: SessionResponse =
      await EnergySession.loginAndFollow(XXCAPP_OAUTH_URL);
    const code: string = EnergySession.queryParam(landing.finalUrl, 'code');
    if (code.length === 0) {
      throw new Error('能耗系统登录失败：未获取到授权码（该系统仅校园网环境可用）');
    }
    Log.info('[EnergySession] oauth code received');

    const oauthReq: OauthReq = { CODE: code };
    await EnergySession.request(session, OAUTH_USER_INFO_URL, oauthReq, true);

    const loginReq: LoginReq = { UserID: EnergySession.account(), Pwd: '', IsCehckPwd: 1, NodeID: '' };
    const loginResp: SessionResponse =
      await EnergySession.request(session, LOGIN_URL, loginReq, false);
    const loginParsed: NodeArrayResp = JSON.parse(loginResp.bodyText) as NodeArrayResp;
    const nodes: NodeInfo[] = loginParsed.ResData !== undefined ? loginParsed.ResData : [];
    if (nodes.length === 0 || nodes[0].NodeID === undefined) {
      throw new Error('能耗系统登录失败：响应缺少 NodeID');
    }
    const nodeID: string = nodes[0].NodeID;

    const meterReq: NodeReq = { NodeID: nodeID };
    const meterResp: SessionResponse =
      await EnergySession.request(session, METER_LIST_URL, meterReq, true);
    const meterParsed: MeterListResp = JSON.parse(meterResp.bodyText) as MeterListResp;
    const rows: MeterListRow[] =
      meterParsed.ResData !== undefined && meterParsed.ResData.rows !== undefined
        ? meterParsed.ResData.rows : [];
    if (rows.length === 0) {
      throw new Error('未查询到表计信息');
    }

    // 电表下标：rows[0].MediumCode == '2' 则电表在下标 0，否则在下标 1（照搬 Dart）。
    const electricityIndex: number = `${rows[0].MediumCode ?? ''}` === '2' ? 0 : 1;
    if (electricityIndex >= rows.length) {
      throw new Error('未查询到电表信息');
    }
    const electricityRemain: number = EnergySession.toNum(rows[electricityIndex].LastNum);
    const electricityMetID: string = rows[electricityIndex].MetID !== undefined ? rows[electricityIndex].MetID as string : '';
    const dateParts: string[] =
      (rows[electricityIndex].LastReadDate !== undefined ? `${rows[electricityIndex].LastReadDate}` : '').split('-');
    if (dateParts.length < 3) {
      throw new Error('能耗系统响应缺少抄表日期');
    }
    const rangeEndForElectricity: Date =
      new Date(parseInt(dateParts[0], 10), parseInt(dateParts[1], 10) - 1, parseInt(dateParts[2], 10));
    const rangeBeginForElectricity: Date = DateUtil.shiftMonths(rangeEndForElectricity, -1);

    const electricityList: MeterInfo[] = await EnergySession.fetchMeterRead(session, electricityMetID,
      DateUtil.formatDash(rangeBeginForElectricity), DateUtil.formatDash(rangeEndForElectricity));

    // 水表（近一年），失败留空（照搬 Dart try-catch）。
    let waterList: MeterInfo[] = [];
    try {
      const waterIndex: number = electricityIndex === 0 ? 1 : 0;
      if (waterIndex < rows.length && rows[waterIndex].MetID !== undefined) {
        const rangeEndForWater: Date = new Date();
        const rangeBeginForWater: Date = DateUtil.shiftMonths(rangeEndForWater, -12);
        waterList = await EnergySession.fetchMeterRead(session, rows[waterIndex].MetID as string,
          DateUtil.formatDash(rangeBeginForWater), DateUtil.formatDash(rangeEndForWater));
      }
    } catch (e) {
      Log.warn(`[EnergySession] water list fetch failed, leave blank: ${e}`);
    }

    return new EnergyInfo(rangeEndForElectricity, electricityRemain, electricityList, waterList);
  }

  private static account(): string {
    return PreferenceService.getString('idsAccount', '');
  }

  private static async fetchMeterRead(session: NetworkSession, metID: string, begin: string,
    end: string): Promise<MeterInfo[]> {
    const req: MetReadReq = { MetID: metID, ReadTimeS: begin, ReadTimeE: end, ReadNum: '' };
    const resp: SessionResponse = await EnergySession.request(session, MET_READ_URL, req, true);
    const parsed: MetReadResp = JSON.parse(resp.bodyText) as MetReadResp;
    const rows: MetReadRow[] =
      parsed.ResData !== undefined && parsed.ResData.rows !== undefined ? parsed.ResData.rows : [];
    const list: MeterInfo[] = [];
    rows.forEach((row: MetReadRow): void => {
      const time: Date | null = DateUtil.parseDateTime(row.ReadTime !== undefined ? row.ReadTime : '');
      if (time !== null) {
        list.push(new MeterInfo(time, EnergySession.toNum(row.ReadNum),
          EnergySession.toNum(row.StartNum), EnergySession.toNum(row.EndNum)));
      }
    });
    return list;
  }
}
