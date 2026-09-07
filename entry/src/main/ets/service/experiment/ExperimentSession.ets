import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { AppContext } from '../AppContext';
import { HtmlParser, HtmlNode } from '../../utils/html/HtmlParser';
import { ImageHasher } from '../../utils/media/ImageHasher';
import { scoreLabelByHash } from '../../model/experiment/ScoreHashes';
import {
  ExperimentData, ExperimentJson, ExperimentTimeRange, RecognitionResult,
  experimentFromJson, experimentToJson
} from '../../model/experiment/ExperimentData';
import { FetchResult } from '../../model/FetchResult';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状 ----

interface ReportRow {
  '2'?: string | null;
  '3'?: string | null;
}

interface ReportDataResp {
  rows?: ReportRow[] | null;
  success?: boolean | null;
}

const WLSY_BASE: string = 'http://wlsy.xidian.edu.cn';
const PHYEWS_LOGIN_URL: string = `${WLSY_BASE}/PhyEws/default.aspx`;
const PHYEWS_SELECT_URL: string = `${WLSY_BASE}/PhyEws/student/select.aspx`;
const PHYEWS_COURSE_URL: string = `${WLSY_BASE}/PhyEws/student/course.aspx`;
const REPORT_INIT_URL: string = `${WLSY_BASE}/wgyreport/wgyreport.dll/?id=stu`;
const REPORT_EVENT_URL: string = `${WLSY_BASE}/wgyreport/wgyreport.dll/HandleEvent`;
const CHROME_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
const FAKE_STU_NAME_COOKIE: string = 'PhyEws_StuName=waterfloatinggenderly; ';
/** 原版硬编码的 ASP.NET WebForms 回传串（VIEWSTATE/EVENTVALIDATION 为写死值）。 */
const LOGIN_FORM_PREFIX: string =
  '__EVENTTARGET=&__EVENTARGUMENT=&' +
  '__VIEWSTATE=%2FwEPDwUKMTEzNzM0MjM0OWQYAQUeX19D' +
  'b250cm9sc1JlcXVpcmVQb3N0QmFja0tleV9fFgEFD2xvZ2luMSRidG5Mb2dpbkOuzGVaztce4Ict7jsIJ0F5pUDb%2BsmSbCCrNVSBlPML&' +
  '__VIEWSTATEGENERATOR=EE008CD9&' +
  '__EVENTVALIDATION=%2FwEdAAcKecdPGDB%2BfW8Tyghx' +
  '7AeSpOzeiNZ7aaEg5p6LqSa9cODI2bZwNtRxUKPkisVLf8l' +
  '8Vv4WhRVIIhZlyYNJO%2BySrDKOhP%2B%2FYMNbVIh74hA2r' +
  'CYnBBSTsX9SjxiYNNk%2B5kglM%2B6pGIq22Oi5mNu6u6eC2W' +
  'EBfKAmATKwSpsOL%2FPNcRyi9l8Dnp6JamksyAzjhW4%3D&';

/**
 * 物理实验会话（对应 Dart repository/experiment_session/physics_experiment_session.dart
 * 与 experiment_report_session.dart / image_recognition.dart）。
 * 独立账号体系：账号=学号，密码=实验平台密码（明文表单提交，成功判定为 302）。
 * Cookie 按 Dart 手工规则构建（PhyEws_StuName 用固定伪造值、跳过 HttpOnly 项），
 * 每次请求后清空容器避免与手工 Cookie 头重复注入。
 * 成绩通过 wgyreport 报告系统拉取图片后以 FNV-1a 像素哈希精确匹配（kScoreHashes 表）。
 */
export class ExperimentSession {
  static readonly CACHE_FILE: string = 'PhysicsExperiment.json';
  private static selectInfo: Map<string, string> = new Map<string, string>();
  private static wlsyCookie: string = '';

  private static session(): NetworkSession {
    return SessionManager.get('experiment');
  }

  private static account(): string {
    return PreferenceService.getString('idsAccount', '');
  }

  private static password(): string {
    return PreferenceService.getString('experimentPassword', '');
  }

  /** 每次请求后清容器：wlsy Cookie 完全由手工串管理（对齐 Dart 行为）。 */
  private static async fetch(opts: SessionOptions, method: string, url: string, body?: string): Promise<SessionResponse> {
    const session: NetworkSession = ExperimentSession.session();
    const resp: SessionResponse = body !== undefined
      ? await session.postRaw(url, opts.contentType.length > 0 ? opts.contentType : 'application/x-www-form-urlencoded', body, opts)
      : await session.get(url, opts);
    session.cookies.clear();
    return resp;
  }

  private static baseOptions(charset: string): SessionOptions {
    const opts: SessionOptions = new SessionOptions();
    opts.charset = charset;
    opts.headers.set('cookie', ExperimentSession.wlsyCookie);
    opts.headers.set('host', 'wlsy.xidian.edu.cn');
    return opts;
  }

  /** 校园网检测：notice 页（GB18030）不含"校外访问"才视为在校。 */
  static async isInSchool(): Promise<boolean> {
    const opts: SessionOptions = new SessionOptions();
    opts.charset = 'gb18030';
    const resp: SessionResponse = await ExperimentSession.session().get('https://notice.xidian.edu.cn', opts);
    ExperimentSession.session().cookies.clear();
    return !resp.bodyText.includes('校外访问');
  }

  // ---- 登录 ----

  private static async login(): Promise<void> {
    if (ExperimentSession.account().length === 0 || ExperimentSession.password().length === 0) {
      throw new Error('实验平台密码未配置');
    }
    const body: string = LOGIN_FORM_PREFIX +
      `login1%24StuLoginID=${ExperimentSession.account()}` +
      `&login1%24StuPassword=${ExperimentSession.password()}` +
      '&login1%24UserRole=Student&login1%24btnLogin.x=28&login1%24btnLogin.y=14';
    const opts: SessionOptions = new SessionOptions();
    opts.charset = 'gb18030';
    opts.headers.set('host', 'wlsy.xidian.edu.cn');
    const resp: SessionResponse = await ExperimentSession.fetch(opts, 'POST', PHYEWS_LOGIN_URL, body);
    if (resp.statusCode !== 302) {
      const root: HtmlNode = HtmlParser.parse(resp.bodyText);
      const label: HtmlNode | null = HtmlParser.getElementById(root, 'login1_Label1');
      const msg: string = label !== null ? label.textContent().trim() : '实验平台登录失败';
      throw new Error(msg.length > 0 ? msg : '实验平台登录失败，请检查实验平台密码');
    }
    // 手工 Cookie 串：伪造 PhyEws_StuName、跳过 HttpOnly 项（原版逐字对拍）。
    ExperimentSession.wlsyCookie = '';
    resp.setCookies.forEach((cookie: string): void => {
      if (cookie.includes('PhyEws_StuName')) {
        ExperimentSession.wlsyCookie += FAKE_STU_NAME_COOKIE;
      } else if (cookie.includes('HttpOnly')) {
        return;
      } else {
        ExperimentSession.wlsyCookie += `${cookie.split(';')[0]}; `;
      }
    });
    Log.info(`[ExperimentSession] cookie built: ${ExperimentSession.wlsyCookie}`);
  }

  // ---- 已选实验列表 ----

  private static async getData(): Promise<ExperimentData[]> {
    if (!(await ExperimentSession.isInSchool())) {
      throw new Error('实验系统仅校园网环境下可用');
    }
    await ExperimentSession.login();

    const opts: SessionOptions = ExperimentSession.baseOptions('gb18030');
    const resp: SessionResponse = await ExperimentSession.fetch(opts, 'GET', PHYEWS_SELECT_URL);
    const root: HtmlNode = HtmlParser.parse(resp.bodyText);
    const table: HtmlNode | null = HtmlParser.getElementById(root, 'Orders_ctl00');
    const trs: HtmlNode[] = table !== null ? HtmlParser.getElementsByTagName(table, 'tr') : [];

    const scoreResults: Map<string, RecognitionResult> = new Map<string, RecognitionResult>();
    try {
      const recognized: Map<string, RecognitionResult> = await ExperimentSession.recognizeAllScores();
      recognized.forEach((v: RecognitionResult, k: string): void => {
        scoreResults.set(k, v);
      });
    } catch (e) {
      Log.warn(`[ExperimentSession] score recognition skipped: ${e}`);
    }

    const toReturn: ExperimentData[] = [];
    for (const tr of trs) {
      const tds: HtmlNode[] = HtmlParser.getElementsByTagName(tr, 'td');
      if (tds.length === 0) {
        continue;
      }
      const spansOf = (td: HtmlNode): string => {
        const spans: HtmlNode[] = HtmlParser.getElementsByTagName(td, 'span');
        return spans.length > 0 ? spans[0].textContent().trim() : '';
      };
      const dateText: string = spansOf(tds[4]);
      const dateNums: string[] = dateText.split('/');
      const timeStr: string = spansOf(tds[3]);
      if (dateNums.length < 3) {
        continue;
      }
      const year: number = parseInt(dateNums[2], 10);
      const month: number = parseInt(dateNums[0], 10);
      const day: number = parseInt(dateNums[1], 10);
      const timeRange: ExperimentTimeRange = timeStr.includes('15')
        ? new ExperimentTimeRange(new Date(year, month - 1, day, 15, 55, 0).getTime(),
          new Date(year, month - 1, day, 18, 10, 0).getTime())
        : new ExperimentTimeRange(new Date(year, month - 1, day, 18, 30, 0).getTime(),
          new Date(year, month - 1, day, 20, 45, 0).getTime());

      const rawName: string = tds.length > 1 ? HtmlParser.getElementsByClassName(tds[1], 'linkSmallBold')[0]?.textContent().trim() ?? '' : '';
      const name: string = rawName.replace(/（3学时）/g, '');
      if (name.length === 0) {
        continue;
      }
      const classroom: string = tds.length > 5 ? spansOf(tds[5]) : '';
      const reference: string = tds.length > 9 ? spansOf(tds[9]) : '';
      let teacher: string = '';
      try {
        teacher = await ExperimentSession.getTeacher(timeStr, name);
      } catch (e) {
        Log.warn(`[ExperimentSession] teacher not found for ${name}: ${e}`);
      }
      toReturn.push(new ExperimentData('physics', name,
        scoreResults.get(name) !== undefined ? scoreResults.get(name) as RecognitionResult : null,
        classroom, [timeRange], teacher, reference));
    }
    return toReturn;
  }

  // ---- 任课老师 ----

  /** 任课老师查询（course.aspx：select#plan1_ExpeList 选科回传 + TimeN/Teacher span 配对）。 */
  private static async getTeacher(time: string, subject: string): Promise<string> {
    const opts: SessionOptions = ExperimentSession.baseOptions('gb18030');
    let page: string = (await ExperimentSession.fetch(opts, 'GET', PHYEWS_COURSE_URL)).bodyText;

    if (ExperimentSession.selectInfo.size === 0) {
      const root: HtmlNode = HtmlParser.parse(page);
      const select: HtmlNode | null = HtmlParser.getElementById(root, 'plan1_ExpeList');
      if (select === null) {
        throw new Error('未找到实验科目列表');
      }
      select.children.forEach((option: HtmlNode): void => {
        const label: string = option.textContent().trim();
        const value: string = option.attr('value');
        if (label.length > 0) {
          ExperimentSession.selectInfo.set(label, value);
        }
      });
    }

    const values: string[] = Array.from(ExperimentSession.selectInfo.values());
    const target: string | undefined = ExperimentSession.selectInfo.get(subject);
    if (target !== undefined && (values.length === 0 || target !== values[0])) {
      const fields: Map<string, string> = new Map<string, string>();
      HtmlParser.getElementsByTagName(HtmlParser.parse(page), 'input').forEach((input: HtmlNode): void => {
        fields.set(input.id(), input.attr('value'));
      });
      fields.set('__EVENTTARGET', 'plan1$ExpeList');
      fields.set('plan1$ExpeList', target);
      const postOpts: SessionOptions = ExperimentSession.baseOptions('gb18030');
      page = (await ExperimentSession.fetch(postOpts, 'POST', PHYEWS_COURSE_URL,
        NetworkSession.formEncode(fields))).bodyText;
    }

    const weekPattern: RegExp = /<span id="plan1_PlanGrid_TimeN_[0-9]{1,2}">(.*)<\/span>/g;
    const teacherPattern: RegExp = /<span id="plan1_PlanGrid_Teacher_[0-9]{1,2}">(.*)<\/span>/g;
    const weeks: RegExpExecArray[] = ExperimentSession.allMatches(weekPattern, page);
    const teachers: RegExpExecArray[] = ExperimentSession.allMatches(teacherPattern, page);
    for (let i: number = 0; i < weeks.length; i++) {
      if (weeks[i].length > 1 && weeks[i][1].includes(time) && i < teachers.length && teachers[i].length > 1) {
        return teachers[i][1];
      }
    }
    throw new Error('未找到任课老师');
  }

  private static allMatches(pattern: RegExp, text: string): RegExpExecArray[] {
    const matches: RegExpExecArray[] = [];
    let match: RegExpExecArray | null = pattern.exec(text);
    while (match !== null) {
      matches.push(match);
      match = pattern.exec(text);
    }
    return matches;
  }

  // ---- wgyreport 成绩图片识别 ----

  /** wgyreport.dll 报告系统：4 步事件 + 登录点击（_fp_ 内嵌明文账密）→ rows 图片地址。 */
  private static async getScoreImageUrls(account: string, pwd: string): Promise<Map<string, string>> {
    const commonHeaders = (): SessionOptions => {
      const opts: SessionOptions = new SessionOptions();
      opts.charset = 'utf-8';
      opts.headers.set('accept-language', 'zh-CN,zh;q=0.9');
      opts.headers.set('user-agent', CHROME_UA);
      opts.headers.set('accept-encoding', 'gzip, deflate, br');
      opts.headers.set('origin', 'http://wlsy.xidian.edu.cn');
      opts.headers.set('referer', REPORT_INIT_URL);
      return opts;
    };
    const postEvent = async (body: string, cookie: string): Promise<SessionResponse> => {
      const opts: SessionOptions = commonHeaders();
      opts.headers.set('content-type', 'application/x-www-form-urlencoded; charset=UTF-8');
      opts.headers.set('x-requested-with', 'XMLHttpRequest');
      opts.headers.set('accept', '*/*');
      opts.headers.set('cookie', cookie);
      return ExperimentSession.fetch(opts, 'POST', REPORT_EVENT_URL, body);
    };

    const initOpts: SessionOptions = commonHeaders();
    initOpts.headers.set('accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    const initResp: SessionResponse = await ExperimentSession.fetch(initOpts, 'GET', REPORT_INIT_URL);
    const sid: string = initResp.headers.get('session_id') ?? '';
    let cookieStr: string = initResp.headers.get('cookie') ?? '';
    if (sid.length === 0) {
      throw new Error('未能从报告系统获取会话 ID');
    }

    await postEvent('Ajax=1&IsEvent=1&Obj=O0&Evt=cinfo&ci=br%3D33%3Bos%3D4%3Bbv%3D140%3Bww%3D2048%3Bwh%3D1018' +
      `&_S_ID=${sid}&_seq_=0&_uo_=O0`, cookieStr);
    await postEvent(`Ajax=1&IsEvent=1&Obj=O0&Evt=move&this=O0&x=868&y=381&_S_ID=${sid}&_seq_=1&_uo_=O0`, cookieStr);
    await postEvent(`Ajax=1&IsEvent=1&Obj=O0&Evt=activate&this=O0&_S_ID=${sid}&_seq_=2&_uo_=O0`, cookieStr);
    await postEvent(`Ajax=1&IsEvent=1&Obj=O0&Evt=resize&this=O0&w=311&h=255&_S_ID=${sid}&_seq_=3&_uo_=O0`, cookieStr);

    const clickBody: string = `Ajax=1&IsEvent=1&Obj=O1F&Evt=click&this=O1F&_S_ID=${sid}` +
      `&_fp_=%26O17%3D%25020%2502%2502${account}%26O1B%3D%25020%2502%2502${pwd}&_seq_=4&_uo_=O0`;
    const clickResp: SessionResponse = await postEvent(clickBody, cookieStr);
    for (const header of clickResp.setCookies) {
      if (header.startsWith('sid=')) {
        const sidValue: string = header.split(';')[0].split('=')[1];
        cookieStr = `UNI_GUI_SESSION_ID=${sid}; sid=${sidValue}`;
        break;
      }
    }

    const dataOpts: SessionOptions = commonHeaders();
    dataOpts.headers.set('x-requested-with', 'XMLHttpRequest');
    dataOpts.headers.set('uniSessionId', sid);
    dataOpts.headers.set('_S_ID', sid);
    dataOpts.headers.set('accept', '*/*');
    dataOpts.headers.set('cookie', cookieStr);
    const dataResp: SessionResponse = await ExperimentSession.fetch(dataOpts, 'GET',
      `${REPORT_EVENT_URL}?IsEvent=1&Obj=OA7&Evt=data&_dc=${Date.now()}&start=0&limit=25&options=1&page=1`);

    const result: Map<string, string> = new Map<string, string>();
    const jsonString: string = dataResp.bodyText.replace(/\\x3C/g, '<').replace(/\\x3E/g, '>');
    const parsed: ReportDataResp = JSON.parse(jsonString) as ReportDataResp;
    const rows: ReportRow[] = parsed.rows !== undefined && parsed.rows !== null ? parsed.rows : [];
    rows.forEach((row: ReportRow): void => {
      // 数字键名只能经 Record 桥接访问（ArkTS 禁止对 interface 字段做索引访问）。
      const record: Record<string, string | null> = row as Record<string, string | null>;
      const experimentName: string = record['2'] ?? '';
      const imageHtml: string = record['3'] ?? '';
      const match: RegExpExecArray | null = /src=\\?"([^"]+)\\?"/.exec(imageHtml);
      if (match !== null && experimentName.length > 0) {
        let imageUrl: string = match[1];
        if (imageUrl.startsWith('/')) {
          imageUrl = `http://wlsy.xidian.edu.cn${imageUrl}`;
        }
        result.set(experimentName, imageUrl);
      }
    });
    if (result.size === 0) {
      throw new Error('未能从报告系统解析成绩图片');
    }
    return result;
  }

  /** 下载成绩图片并做像素哈希 → 查 kScoreHashes 表（并行抓取，单张失败置未识别）。 */
  private static async recognizeAllScores(): Promise<Map<string, RecognitionResult>> {
    const account: string = ExperimentSession.account();
    const password: string = ExperimentSession.password();
    const urlMap: Map<string, string> = await ExperimentSession.getScoreImageUrls(account, password);
    const resultMap: Map<string, RecognitionResult> = new Map<string, RecognitionResult>();
    const session: NetworkSession = ExperimentSession.session();
    const tasks: Promise<void>[] = [];
    urlMap.forEach((url: string, name: string): void => {
      const opts: SessionOptions = new SessionOptions();
      opts.headers.set('user-agent', CHROME_UA);
      opts.headers.set('referer', REPORT_INIT_URL);
      const task: Promise<void> = session.get(url, opts).then((resp: SessionResponse): Promise<number> => {
        session.cookies.clear();
        if (resp.bodyBytes === null) {
          throw new Error(`成绩图片下载失败：${url}`);
        }
        return ImageHasher.fnv1aPixelHash(new Uint8Array(resp.bodyBytes));
      }).then((hash: number): void => {
        const label: string | null = scoreLabelByHash(hash);
        resultMap.set(name, new RecognitionResult(label !== null ? label : '', label !== null, url));
      }).catch((e: Object): void => {
        Log.warn(`[ExperimentSession] recognize ${name} failed: ${e}`);
        resultMap.set(name, new RecognitionResult('', false, url));
      });
      tasks.push(task);
    });
    await Promise.all(tasks);
    return resultMap;
  }

  // ---- 缓存 ----

  static getCacheData(): ExperimentData[] {
    const text: string | null = AppContext.readCacheText(ExperimentSession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return [];
    }
    try {
      const arr: ExperimentJson[] = JSON.parse(text) as ExperimentJson[];
      return arr.map((j: ExperimentJson): ExperimentData => experimentFromJson(j));
    } catch (e) {
      Log.warn(`physics experiment cache parse failed: ${e}`);
      return [];
    }
  }

  private static writeCache(list: ExperimentData[]): void {
    const arr: ExperimentJson[] = list.map((e: ExperimentData): ExperimentJson => experimentToJson(e));
    AppContext.writeCacheText(ExperimentSession.CACHE_FILE, JSON.stringify(arr));
  }

  static cacheFetchTime(): number {
    return AppContext.cacheModifiedMs(ExperimentSession.CACHE_FILE);
  }

  static deleteCache(): void {
    AppContext.deleteCache(ExperimentSession.CACHE_FILE);
  }

  /** 抓取入口：失败回退缓存（对齐 Dart _getDataOnce）。 */
  static async getDataWithCache(): Promise<FetchResult<ExperimentData[]>> {
    try {
      const data: ExperimentData[] = await ExperimentSession.getData();
      ExperimentSession.writeCache(data);
      return FetchResult.fresh<ExperimentData[]>(data);
    } catch (e) {
      const cache: ExperimentData[] = ExperimentSession.getCacheData();
      if (cache.length > 0) {
        return FetchResult.cached<ExperimentData[]>(cache, ExperimentSession.cacheFetchTime(), '');
      }
      throw e instanceof Error ? e : new Error(`${e}`);
    }
  }
}
