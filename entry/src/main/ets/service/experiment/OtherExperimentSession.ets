import { IdsSession } from '../ids/IdsSession';
import { backgroundSliderHandler } from '../ids/BackgroundSlider';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { AppContext } from '../AppContext';
import { HtmlParser, HtmlNode } from '../../utils/html/HtmlParser';
import { timeListEnd, timeListStart } from '../../model/experiment/ScoreHashes';
import { ExperimentData, ExperimentJson, ExperimentTimeRange, experimentFromJson, experimentToJson } from '../../model/experiment/ExperimentData';
import { FetchResult } from '../../model/FetchResult';
import { Log } from '../../utils/Log';

// ---- JSON 形状 ----

interface LoginJson {
  username: string;
  password: string;
}

interface WeekBody {
  weeks: number;
}

const SYSJ_BASE: string = 'https://sysj.xidian.edu.cn';
const NAME_MARK: string = '???student.timetable.course???：';
const CLASSROOM_MARK: string = '???schedule.course.lab???：';
const TEACHER_MARK: string = '???student.timetable.teacher???：';

/**
 * 其他实验/上机实践会话（对应 Dart repository/ids_session/sysj_session.dart）。
 * 复用主 IDS 会话：sysj OAuth 六步链（test→uaa login→ids authorize→uaa authorize 取 code→
 * callback 取页面 JS 动态密码→webapp/login）→ 周次 1..25 循环拉课表 → 表格解析合并连续节次。
 * 校验：仅校园网可用；缓存 OtherExperiment.json。
 */
export class OtherExperimentSession {
  static readonly CACHE_FILE: string = 'OtherExperiment.json';

  private static session(): NetworkSession {
    return SessionManager.ids();
  }

  private static async formPost(url: string, body: string): Promise<SessionResponse> {
    const opts: SessionOptions = new SessionOptions();
    opts.contentType = 'application/x-www-form-urlencoded';
    return OtherExperimentSession.session().postRaw(url, 'application/x-www-form-urlencoded', body, opts);
  }

  private static queryParamOf(source: string, key: string): string {
    const queryIndex: number = source.indexOf('?');
    const query: string = queryIndex >= 0 ? source.substring(queryIndex + 1) : source;
    const pairs: string[] = query.split('&');
    for (const pair of pairs) {
      const eq: number = pair.indexOf('=');
      if (eq < 0) {
        continue;
      }
      if (pair.substring(0, eq) === key) {
        try {
          return decodeURIComponent(pair.substring(eq + 1));
        } catch (e) {
          return pair.substring(eq + 1);
        }
      }
    }
    return '';
  }

  private static async isInSchool(): Promise<boolean> {
    const opts: SessionOptions = new SessionOptions();
    opts.charset = 'gb18030';
    const resp: SessionResponse = await OtherExperimentSession.session().get('https://notice.xidian.edu.cn', opts);
    return !resp.bodyText.includes('校外访问');
  }

  /** sysj OAuth 登录链（对齐 Dart _getDataFromSysj 前半段）。 */
  private static async oauthLogin(): Promise<void> {
    const session: NetworkSession = OtherExperimentSession.session();
    let resp: SessionResponse = await session.get(`${SYSJ_BASE}/xidian/test`);
    if (!resp.isRedirect) {
      throw new Error('sysj 实验平台无重定向响应');
    }
    resp = await session.get(resp.location);
    const redirectUrl: string = resp.location;
    const state: string = OtherExperimentSession.queryParamOf(redirectUrl, 'state');
    if (state.length === 0) {
      throw new Error('sysj 实验平台缺少 state 参数');
    }
    await session.get(redirectUrl);

    await session.get(`${SYSJ_BASE}/uaa/xidian/login?redirect_uri=${encodeURIComponent('https://sysj.xidian.edu.cn/xidian/webapp/callback')}` +
      `&state=${encodeURIComponent(state)}&client_id=GvsunLims&response_type=code` +
      `&authorize_uri=${encodeURIComponent('https://sysj.xidian.edu.cn/uaa/oauth/authorize')}`);

    const hrefIds: string = 'https://ids.xidian.edu.cn/authserver/oauth2.0/authorize' +
      `?redirect_uri=${encodeURIComponent('https://sysj.xidian.edu.cn/uaa/xidian/callback')}` +
      `&response_type=code&state=${encodeURIComponent(state)}&client_id=1387116615722893312`;
    resp = await session.get(hrefIds);
    const location: string = resp.location.length > 0 ? resp.location : hrefIds;

    let authLocation: string;
    if (!location.includes('sysj')) {
      Log.info('[OtherExperimentSession] jump not have sysj, treat as new login');
      const slider = backgroundSliderHandler();
      const service: string = OtherExperimentSession.queryParamOf(location, 'service');
      authLocation = await IdsSession.checkAndLogin(service.length > 0 ? service : location, slider);
    } else {
      authLocation = location;
    }
    await IdsSession.followRedirects(authLocation);

    const authorizeBody: string = await session.get(`${SYSJ_BASE}/uaa/oauth/authorize` +
      `?redirect_uri=${encodeURIComponent('https://sysj.xidian.edu.cn/xidian/webapp/callback')}` +
      `&state=${encodeURIComponent(state)}&client_id=GvsunLims&response_type=code`)
      .then((r: SessionResponse): string => r.bodyText);
    const codeMatch: RegExpExecArray | null = /\?code=(.*)&/.exec(authorizeBody);
    if (codeMatch === null) {
      throw new Error('sysj 授权码获取失败');
    }
    const code: string = codeMatch[1];

    const callbackBody: string = await session.get(`${SYSJ_BASE}/xidian/webapp/callback?code=${encodeURIComponent(code)}&state=${encodeURIComponent(state)}`)
      .then((r: SessionResponse): string => r.bodyText);
    const pwdMatch: RegExpExecArray | null = /var password = '(.*)';/.exec(callbackBody);
    if (pwdMatch === null) {
      throw new Error('sysj 动态密码获取失败');
    }
    const body: LoginJson = { username: PreferenceService.getString('idsAccount', ''), password: pwdMatch[1] };
    const loginResp: SessionResponse = await OtherExperimentSession.formPost(`${SYSJ_BASE}/xidian/webapp/login`,
      NetworkSession.formEncode(OtherExperimentSession.formEntries(body)));
    if (loginResp.isRedirect && loginResp.location.length > 0) {
      await session.get(loginResp.location);
    }
  }

  private static formEntries(body: LoginJson): Map<string, string> {
    const map: Map<string, string> = new Map<string, string>();
    map.set('username', body.username);
    map.set('password', body.password);
    return map;
  }

  /** 课表抓取与解析（tables[1]，do-labReservation 定位，连续相同单元格合并时长）。 */
  private static async getDataFromSysj(): Promise<ExperimentData[]> {
    if (!(await OtherExperimentSession.isInSchool())) {
      throw new Error('实验系统仅校园网环境下可用');
    }
    await OtherExperimentSession.oauthLogin();

    const session: NetworkSession = OtherExperimentSession.session();
    const experimentData: ExperimentData[] = [];

    for (let week: number = 1; week <= 25; week++) {
      const weekBody: WeekBody = { weeks: week };
      const resp: SessionResponse = await OtherExperimentSession.formPost(
        `${SYSJ_BASE}/xidian/StudentCurrWeekTimetable`, `weeks=${week}`);
      const root: HtmlNode = HtmlParser.parse(resp.bodyText.trim());
      const tables: HtmlNode[] = HtmlParser.getElementsByTagName(root, 'table');
      if (tables.length < 2) {
        Log.info(`[OtherExperimentSession] no tables at week ${week}`);
        continue;
      }
      const table: HtmlNode = tables[1];

      // 表头日期：th 内 <br> 之后的文本（等价 Dart innerHtml.split('<br>')[1]）。
      const weekdays: string[] = [];
      const ths: HtmlNode[] = HtmlParser.getElementsByTagName(table, 'th');
      ths.forEach((th: HtmlNode): void => {
        const date: string = OtherExperimentSession.textAfterBr(th);
        if (date.length > 0) {
          weekdays.push(date);
        }
      });

      // 单元格内容 Map：'weekDay,classIndex' → textContent。
      const cells: Map<string, string> = new Map<string, string>();
      HtmlParser.getElementsByTagName(table, 'td').forEach((td: HtmlNode): void => {
        const key: string = td.attr('do-labReservation');
        if (key.length > 0) {
          cells.set(key, td.textContent());
        }
      });

      for (let weekDay: number = 1; weekDay <= 7; weekDay++) {
        for (let classIndex: number = 1; classIndex <= 13; classIndex++) {
          const cellContent: string = cells.get(`${weekDay},${classIndex}`) ?? '';
          if (cellContent.length === 0 || !cellContent.includes(NAME_MARK)
            || !cellContent.includes(CLASSROOM_MARK) || !cellContent.includes(TEACHER_MARK)) {
            continue;
          }

          const name: string = OtherExperimentSession.between(cellContent, NAME_MARK, CLASSROOM_MARK);
          const classroom: string = OtherExperimentSession.between(cellContent, CLASSROOM_MARK, TEACHER_MARK);
          const teacher: string = OtherExperimentSession.after(cellContent, TEACHER_MARK);

          if (weekDay - 1 >= weekdays.length) {
            continue;
          }
          const dateNums: string[] = weekdays[weekDay - 1].split('-');
          if (dateNums.length < 3) {
            continue;
          }
          const year: number = parseInt(dateNums[0], 10);
          const month: number = parseInt(dateNums[1], 10);
          const day: number = parseInt(dateNums[2], 10);
          const startParts: string[] = timeListStart(classIndex).split(':');
          let endTimeStr: string = timeListEnd(classIndex);
          const startTime: number =
            new Date(year, month - 1, day, parseInt(startParts[0], 10), parseInt(startParts[1], 10)).getTime();

          // 连续相同内容合并（对齐 Dart while classIndex < 13 内层循环）。
          let mergedIndex: number = classIndex;
          while (mergedIndex < 13) {
            const nextContent: string = cells.get(`${weekDay},${mergedIndex + 1}`) ?? '';
            if (nextContent !== cellContent) {
              break;
            }
            endTimeStr = timeListEnd(mergedIndex + 1);
            mergedIndex++;
          }
          const endParts: string[] = endTimeStr.split(':');
          const endTime: number =
            new Date(year, month - 1, day, parseInt(endParts[0], 10), parseInt(endParts[1], 10)).getTime();

          const dataWithSameInfoIndex: number = experimentData.findIndex((e: ExperimentData): boolean =>
            e.name === name && e.classroom === classroom && e.teacher === teacher);
          if (experimentData.length === 0 || dataWithSameInfoIndex === -1) {
            experimentData.push(new ExperimentData('others', name, null, classroom,
              [new ExperimentTimeRange(startTime, endTime)], teacher, ''));
          } else {
            const existing: ExperimentData = experimentData[dataWithSameInfoIndex];
            const ranges: ExperimentTimeRange[] = existing.timeRanges.concat([new ExperimentTimeRange(startTime, endTime)]);
            experimentData[dataWithSameInfoIndex] = new ExperimentData(existing.type, existing.name,
              existing.score, existing.classroom, ranges, existing.teacher, existing.reference);
          }
          // 跳过已合并的节次。
          classIndex = mergedIndex;
        }
      }
    }
    return experimentData;
  }

  private static textAfterBr(node: HtmlNode): string {
    let out: string = '';
    let afterBr: boolean = false;
    const walk = (n: HtmlNode): void => {
      if (!afterBr && n.isElement() && n.tag === 'br') {
        afterBr = true;
        return;
      }
      if (afterBr && n.isText) {
        out += n.text;
        return;
      }
      n.children.forEach((child: HtmlNode): void => {
        walk(child);
      });
    };
    walk(node);
    return out.trim();
  }

  private static between(text: string, startMark: string, endMark: string): string {
    const start: number = text.indexOf(startMark);
    const end: number = text.indexOf(endMark);
    if (start < 0 || end < 0 || end < start) {
      return '';
    }
    return text.substring(start + startMark.length, end).replace(/<br>/g, '').trim();
  }

  private static after(text: string, mark: string): string {
    const start: number = text.indexOf(mark);
    if (start < 0) {
      return '';
    }
    return text.substring(start + mark.length).replace(/<br>/g, '').trim();
  }

  // ---- 缓存 ----

  static getCacheData(): ExperimentData[] {
    const text: string | null = AppContext.readCacheText(OtherExperimentSession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return [];
    }
    try {
      const arr: ExperimentJson[] = JSON.parse(text) as ExperimentJson[];
      return arr.map((j: ExperimentJson): ExperimentData => experimentFromJson(j));
    } catch (e) {
      Log.warn(`other experiment cache parse failed: ${e}`);
      return [];
    }
  }

  private static writeCache(list: ExperimentData[]): void {
    const arr: ExperimentJson[] = list.map((e: ExperimentData): ExperimentJson => experimentToJson(e));
    AppContext.writeCacheText(OtherExperimentSession.CACHE_FILE, JSON.stringify(arr));
  }

  static cacheFetchTime(): number {
    return AppContext.cacheModifiedMs(OtherExperimentSession.CACHE_FILE);
  }

  static deleteCache(): void {
    AppContext.deleteCache(OtherExperimentSession.CACHE_FILE);
  }

  static async getDataWithCache(): Promise<FetchResult<ExperimentData[]>> {
    try {
      const data: ExperimentData[] = await OtherExperimentSession.getDataFromSysj();
      OtherExperimentSession.writeCache(data);
      return FetchResult.fresh<ExperimentData[]>(data);
    } catch (e) {
      const cache: ExperimentData[] = OtherExperimentSession.getCacheData();
      if (cache.length > 0) {
        return FetchResult.cached<ExperimentData[]>(cache, OtherExperimentSession.cacheFetchTime(), '');
      }
      throw e instanceof Error ? e : new Error(`${e}`);
    }
  }
}
