import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { SportClassItem, SportItems, SportScore, SportScoreOfYear } from '../../model/sport/SportModels';
import { FetchResult } from '../../model/FetchResult';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状 ----

interface SportTotalRow {
  totalScore?: string | number | null;
  rank?: string | number | null;
  gradeType?: string | null;
  graduationStatus?: string | number | null;
  year?: string | null;
  meaScoreId?: string | number | null;
}

interface SportTotalResp {
  returnCode?: string | number;
  returnMsg?: string | null;
  data?: SportTotalRow[] | null;
}

interface SportDetailRow {
  examName?: string | null;
  examunit?: string | null;
  actualScore?: string | number | null;
  score?: string | number | null;
  rank?: string | number | null;
}

interface SportDetailResp {
  returnCode?: string | number;
  returnMsg?: string | null;
  data?: SportDetailRow[] | null;
}

interface TermRow {
  id?: string | number;
  score?: string | number | null;
  type?: string | number | null;
}

interface TermResp {
  returnCode?: string | number;
  returnMsg?: string | null;
  data?: TermRow[] | null;
}

interface SportClassData {
  teacherCurriculumSysTermName?: string | null;
  teacherCurriculumTeachingCurriculumName?: string | null;
  teacherCurriculumSysUserName?: string | null;
  teacherCurriculumTeachingSchoolTimeName?: string | null;
  teacherCurriculumTeachingAddressName?: string | null;
}

interface SportClassResp {
  returnCode?: string | number;
  returnMsg?: string | null;
  data?: SportClassData[] | null;
}

interface SportLoginData {
  id?: string | number;
  token?: string;
}

interface SportLoginResp {
  returnCode?: string | number;
  returnMsg?: string | null;
  data?: SportLoginData;
}

/** 内部鉴权失败信号（触发清态重登重试一次）。 */
class SportAuthExpiredError extends Error {
}

/** 密码未配置 / 账号密码错误（不再自动重试）。 */
export class SportCredentialError extends Error {
}

const BASE_URL: string = 'http://tybjxgl.xidian.edu.cn/app/';
/** 注意：原版 dio baseUrl 语义下 '/h5/login' 经 Uri.resolve 落在站点根路径（丢弃 /app/）。 */
const LOGIN_URL: string = 'http://tybjxgl.xidian.edu.cn/h5/login';
const WRONG_PASSWORD_KEYWORDS: string[] = ['用户名', '账号', '密码'];
const AUTH_FAILURE_KEYWORDS: string[] = ['未登录', '登录失效', '自动登录失效', 'token失效', '重新登录'];
/** 2048 位 RSA 公钥（原版内嵌 PEM）。 */
const RSA_PUBLIC_KEY: string = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAq4laolA7zAk7jzsqDb3Oa5pS/uCPlZfASK8Soh/NzEmry77QDZ2koyr96M5Wx+A9cxwewQMHzi8RoOfb3UcQO4UDQlMUImLuzUnfbk3TTppijSLH+PU88XQxcgYm2JTa546c7JdZSI6dBeXOJH20quuxWyzgLk9jAlt3ytYygPQ7C6o6ZSmjcMgE3xgLaHGvixEVpOjL/pdVLzXhrMqWVAnB/snMjpCqesDVTDe5c6OOmj2q5J8n+tzIXtnvrkxQSDaUp8DWF8meMwyTErmYklMXzKic2rjdYZpHh4x98Fg0Q28sp6i2ZoWiGrJDKW29mntVQQiDNhKDawb4B45zUwIDAQAB';

/**
 * 体育平台会话（对应 Dart repository/miscellaneous_session/xidian_sport_session.dart）。
 * 独立登录态：账号=学号，密码 RSA-PKCS1 加密后 POST /h5/login 换 token；
 * 每请求头 channel/version/type/token/timestamp/sign（sign=按 key 排序的 &k=v 串去首字符取 MD5）；
 * returnCode 401/402 或消息含失效关键词 → 清 token+cookie 强制重登并重试一次。
 * commonSignParams 原版签名计算未使用，忠实不移植。
 */
export class SportSession {
  static readonly SCORE_CACHE_HINT_CREDENTIAL: string = 'sport.cache_hint_credential_invalid';
  static readonly SCORE_CACHE_HINT_MISSING: string = 'sport.cache_hint_missing_password';
  static readonly SCORE_CACHE_HINT_MAINTAIN: string = 'sport.cache_hint_maintain';
  static readonly SCORE_CACHE_HINT_NETWORK: string = 'sport.cache_hint_network';
  static readonly SCORE_CACHE_HINT_UNKNOWN: string = 'sport.cache_hint_unknown';

  private static userId: string = '';
  private static token: string = '';
  private static authTail: Promise<void> = Promise.resolve();

  private static session(): NetworkSession {
    return SessionManager.sport();
  }

  private static toStr(v: string | number | null | undefined): string {
    return v === undefined || v === null ? '' : `${v}`;
  }

  private static authExpiredMessage(message: string): boolean {
    return AUTH_FAILURE_KEYWORDS.some((k: string): boolean => message.includes(k));
  }

  private static isAuthFailure(resp: SportTotalResp | SportDetailResp | TermResp | SportClassResp): boolean {
    const code: string = SportSession.toStr(resp.returnCode);
    if (code === '401' || code === '402') {
      return true;
    }
    const msg: string = resp.returnMsg ?? '';
    return SportSession.authExpiredMessage(msg);
  }

  /** 手工构建 JSON 请求体（数字保持数字字面量，与 Dart jsonEncode 行为一致）。 */
  private static jsonBody(entries: Map<string, string | number>): string {
    const parts: string[] = [];
    entries.forEach((value: string | number, key: string): void => {
      const encoded: string = typeof value === 'number' ? `${value}` : JSON.stringify(value);
      parts.push(`${JSON.stringify(key)}:${encoded}`);
    });
    return `{${parts.join(',')}}`;
  }

  /** sign：body 参数 + timestamp 按 key 排序拼 &k=v，去首字符取 MD5 hex。 */
  private static async getSign(params: Map<string, string | number>): Promise<string> {
    const keys: string[] = Array.from(params.keys()).sort();
    let toCalculate: string = '';
    keys.forEach((key: string): void => {
      toCalculate += `&${key}=${params.get(key)}`;
    });
    return CryptoUtil.md5HexOfText(toCalculate.substring(1));
  }

  private static async requestHeaders(payload: Map<string, string | number>): Promise<SessionOptions> {
    const opts: SessionOptions = new SessionOptions();
    opts.maxHops = 5;
    opts.headers.set('channel', 'H5');
    opts.headers.set('version', '99999');
    opts.headers.set('type', '0');
    opts.headers.set('token', SportSession.token);
    const timestamp: string = `${Date.now()}`;
    opts.headers.set('timestamp', timestamp);
    const forSign: Map<string, string | number> = new Map<string, string | number>();
    payload.forEach((value: string | number, key: string): void => {
      forSign.set(key, value);
    });
    forSign.set('timestamp', timestamp);
    opts.headers.set('sign', await SportSession.getSign(forSign));
    opts.contentType = 'application/json';
    return opts;
  }

  /** 业务请求：POST JSON，返回解析后的 JSON（HTTP 401/402 视为鉴权失败）。 */
  private static async require(subWebsite: string, payload: Map<string, string | number>): Promise<Object> {
    const opts: SessionOptions = await SportSession.requestHeaders(payload);
    const url: string = subWebsite.startsWith('http') ? subWebsite : `${BASE_URL}${subWebsite}`;
    const resp: SessionResponse = await SportSession.session()
      .postRaw(url, 'application/json', SportSession.jsonBody(payload), opts);
    if (resp.statusCode === 401 || resp.statusCode === 402) {
      throw new SportAuthExpiredError();
    }
    if (resp.statusCode !== 200) {
      throw new Error(`体育平台请求失败（HTTP ${resp.statusCode}）`);
    }
    return JSON.parse(resp.bodyText) as Object;
  }

  /** RSA-PKCS1 加密密码（公钥为内嵌 2048 位 base64 DER）。 */
  private static async rsaEncrypt(plain: string): Promise<string> {
    const der: Uint8Array = CryptoUtil.base64Decode(RSA_PUBLIC_KEY);
    const publicKey = await CryptoUtil.importRsaPublicKey(der, 2048);
    return CryptoUtil.base64Encode(await CryptoUtil.rsaEncryptPkcs1(publicKey, CryptoUtil.utf8Bytes(plain)));
  }

  private static async loginOnce(): Promise<void> {
    const account: string = PreferenceService.getString('idsAccount', '');
    const password: string = PreferenceService.getString('sportPassword', '');
    if (account.length === 0 || password.length === 0) {
      throw new SportCredentialError('体育平台密码未配置');
    }
    if (SportSession.userId.length > 0 && SportSession.token.length > 0) {
      return;
    }
    const body: Map<string, string | number> = new Map<string, string | number>();
    body.set('uname', account);
    body.set('pwd', await SportSession.rsaEncrypt(password));
    body.set('openid', '');
    const resp: SportLoginResp = await SportSession.require(LOGIN_URL, body) as SportLoginResp;
    const code: string = SportSession.toStr(resp.returnCode);
    if (code !== '200') {
      const msg: string = resp.returnMsg ?? '';
      if (WRONG_PASSWORD_KEYWORDS.some((k: string): boolean => msg.includes(k))) {
        throw new SportCredentialError('账号或密码有误，请在「设置 → 平台账号 → 体育平台」检查密码');
      }
      throw new Error(msg.length > 0 ? msg : '体育平台登录失败');
    }
    SportSession.userId = SportSession.toStr(resp.data?.id);
    SportSession.token = resp.data?.token ?? '';
  }

  private static ensureAuthenticated(): Promise<void> {
    const task: Promise<void> = (async (): Promise<void> => {
      await SportSession.loginOnce();
    })();
    SportSession.authTail = SportSession.authTail.then((): Promise<void> => task, (): Promise<void> => task);
    return task;
  }

  /** 鉴权失败后：清 token + 清 sport cookie，强制重登并重试一次（对齐 Dart _retryAfterReAuth）。 */
  private static async retryAfterReAuth(subWebsite: string, payload: Map<string, string | number>): Promise<Object> {
    Log.warn('[SportSession] auth expired, re-login and retry once');
    SportSession.userId = '';
    SportSession.token = '';
    SessionManager.clearStore('sport');
    await SportSession.ensureAuthenticated();
    const resp: Object = await SportSession.require(subWebsite, payload);
    if (SportSession.isAuthFailure(resp as SportTotalResp)) {
      throw new SportCredentialError('体育平台登录已失效，请检查密码后重试');
    }
    return resp;
  }

  private static async authenticatedRequire(subWebsite: string, payload: Map<string, string | number>): Promise<Object> {
    try {
      await SportSession.ensureAuthenticated();
      const resp: Object = await SportSession.require(subWebsite, payload);
      if (SportSession.isAuthFailure(resp as SportTotalResp)) {
        throw new SportAuthExpiredError();
      }
      return resp;
    } catch (e) {
      if (e instanceof SportAuthExpiredError) {
        return SportSession.retryAfterReAuth(subWebsite, payload);
      }
      throw e instanceof Error ? e : new Error(`${e}`);
    }
  }

  private static hintFromError(e: Object): string {
    if (e instanceof SportCredentialError) {
      return e.message.includes('未配置')
        ? SportSession.SCORE_CACHE_HINT_MISSING : SportSession.SCORE_CACHE_HINT_CREDENTIAL;
    }
    if (e instanceof Error && e.message.includes('维护')) {
      return SportSession.SCORE_CACHE_HINT_MAINTAIN;
    }
    if (e instanceof TypeError) {
      return SportSession.SCORE_CACHE_HINT_UNKNOWN;
    }
    return SportSession.SCORE_CACHE_HINT_NETWORK;
  }

  /** 体测成绩：总览（含 graduationStatus 项）+ 每年度明细。 */
  static async getScore(): Promise<FetchResult<SportScore>> {
    const toReturn: SportScore = new SportScore();
    try {
      const resp: Object = await SportSession.authenticatedRequire('measure/getStuTotalScore',
        new Map<string, string | number>([['userId', SportSession.userId]]));
      const rows: SportTotalRow[] = (resp as SportTotalResp).data ?? [];
      for (const i of rows) {
        // 键存在性判定：JSON null 解析为 null 而非 undefined，与 Dart keys.contains 等价。
        if (i.graduationStatus !== undefined) {
          toReturn.total = SportSession.toStr(i.totalScore);
          toReturn.detail = i.gradeType ?? '';
          toReturn.rank = SportSession.toStr(i.rank);
        } else {
          const toAdd: SportScoreOfYear = new SportScoreOfYear(
            SportSession.toStr(i.year), SportSession.toStr(i.totalScore), SportSession.toStr(i.rank), i.gradeType ?? '');
          const detail: Object = await SportSession.authenticatedRequire('measure/getStuScoreDetail',
            new Map<string, string | number>([['meaScoreId', i.meaScoreId ?? '']]));
          const detailResp: SportDetailResp = detail as SportDetailResp;
          if (SportSession.toStr(detailResp.returnCode) !== '200') {
            toAdd.moreinfo += SportSession.toStr(detailResp.returnMsg);
          } else {
            const detailRows: SportDetailRow[] = detailResp.data ?? [];
            for (const d of detailRows) {
              toAdd.details.push(new SportItems(
                d.examName ?? '', d.examunit ?? '', SportSession.toStr(d.actualScore) || '0',
                d.score === undefined || d.score === null ? 0.0 : Number(d.score),
                d.rank === undefined || d.rank === null ? '不及格' : SportSession.toStr(d.rank)
              ));
            }
          }
          toReturn.list.push(toAdd);
        }
      }
      return FetchResult.fresh<SportScore>(toReturn);
    } catch (e) {
      Log.warn(`SportSession.getScore failed: ${e}`);
      throw e instanceof Error ? e : new Error(`${e}`);
    }
  }

  /** 体育课成绩：学期列表 + 每学期课程详情（解析失败的单条跳过，对齐 Dart continue）。 */
  static async getClass(): Promise<FetchResult<SportClassItem[]>> {
    const toReturn: SportClassItem[] = [];
    const resp: Object = await SportSession.authenticatedRequire('stuTermScore/uidSelect',
      new Map<string, string | number>([
        ['uid', SportSession.userId], ['pageIndex', '1'], ['pageSize', '100']
      ]));
    const rows: TermRow[] = (resp as TermResp).data ?? [];
    for (const i of rows) {
      try {
        const detail: Object = await SportSession.authenticatedRequire('stuTeacherCurriculum/selstuTeacherCurriculum',
          new Map<string, string | number>([
            ['stuid', SportSession.userId], ['stuTermScoreid', i.id ?? '']
          ]));
        const classRows: SportClassData[] = (detail as SportClassResp).data ?? [];
        const classData: SportClassData | undefined = classRows[0];
        if (classData === undefined) {
          continue;
        }
        toReturn.push(SportClassItem.fromData(
          classData.teacherCurriculumSysTermName ?? '',
          classData.teacherCurriculumTeachingCurriculumName ?? '',
          SportSession.toStr(i.score),
          SportSession.toStr(i.type),
          classData.teacherCurriculumSysUserName ?? '',
          classData.teacherCurriculumTeachingSchoolTimeName ?? '',
          classData.teacherCurriculumTeachingAddressName ?? ''
        ));
      } catch (e) {
        Log.warn(`sport class item skipped: ${e}`);
        continue;
      }
    }
    return FetchResult.fresh<SportClassItem[]>(toReturn);
  }

  static cacheHint(e: Object): string {
    return SportSession.hintFromError(e);
  }
}
