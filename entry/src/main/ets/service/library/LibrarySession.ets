import { IdsSession } from '../ids/IdsSession';
import { backgroundSliderHandler } from '../ids/BackgroundSlider';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import {
  BookInfo, BookLocation, BorrowData, LibrarySearchFilterOptions, LibrarySearchOption,
  bookInfoFromOpacJson, bookLocationFromOpacJson, borrowDataFromJson,
  LoanRowJson, LocationRowJson, SearchRowJson
} from '../../model/library/LibraryModels';
import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状 ----

interface FieldRow {
  searchField?: string | null;
}

interface FieldResp {
  data?: FieldRow[] | null;
}

interface CodedRow {
  code?: string | number | null;
  name?: string | null;
}

interface ConditionData {
  documentTypeList?: CodedRow[] | null;
  countryList?: CodedRow[] | null;
  languageList?: CodedRow[] | null;
}

interface ConditionResp {
  data?: ConditionData | null;
}

interface LocationRow {
  locationId?: string | number | null;
  locationName?: string | number | boolean | null;
}

interface LocationData {
  donateList?: LocationRow[] | null;
}

interface LocationResp {
  data?: LocationData | null;
}

interface SearchItemsItem {
  oper: null;
  searchField: string;
  matchMode: string;
  searchFieldContent: string;
}

interface OpacSearchBody {
  docCode: (string | null)[];
  litCode: string[];
  searchFieldContent: string;
  searchField: string;
  matchMode: string;
  resourceType: string[];
  subject: string[];
  discode1: string[];
  publisher: string[];
  locationId: number[];
  collectionName: string[];
  author: string[];
  langCode: string[];
  countryCode: string[];
  publishBegin: string | null;
  publishEnd: string | null;
  coreInclude: string[];
  ddType: string[];
  verifyStatus: string[];
  group: string[];
  sortField: string;
  sortClause: string;
  page: number;
  rows: number;
  onlyOnShelf: boolean | null;
  campusId: number[];
  curLocationId: string[];
  eCollectionIds: string[];
  kindNo: string[];
  libCode: string[];
  neweCollectionIds: string[];
  newCoreInclude: string[];
  customSub: string[];
  customSub0: string[];
  searchItems?: SearchItemsItem[] | null;
  indexSearch?: number;
  searchFieldList?: null;
}

interface SearchResultData {
  searchResult?: SearchRowJson[] | null;
}

interface SearchResp {
  data?: SearchResultData | null;
}

interface LocationBody {
  locationName: string;
  campusIds: string[];
  locationTypeCodes: string[];
  entrust: number;
  subscribe: number;
  page: number;
  rows: number;
}

interface CoverBody {
  title: string;
  isbn: string;
  recordId: number;
}

interface CoverData {
  duxiuImageUrl?: string | null;
}

interface CoverResp {
  data?: CoverData | null;
}

interface GroupItemsBody {
  page: number;
  rows: number;
  entrance: null;
  recordId: string;
  isUnify: boolean;
}

interface GroupCodeBody {
  mappingPath: string;
}

interface GroupItemsData {
  list?: LocationRowJson[] | null;
}

interface GroupItemsResp {
  data?: GroupItemsData | null;
}

interface LoanBody {
  page: number;
  rows: number;
  searchType: number;
  searchContent: string;
  sortType: number;
  startDate: null;
  endDate: null;
}

interface LoanData {
  searchResult?: LoanRowJson[] | null;
}

interface LoanResp {
  data?: LoanData | null;
}

interface RenewBody {
  loanIds: number[];
}

interface RenewData {
  result?: Record<string, string>;
  success?: number | null;
}

interface RenewResp {
  data?: RenewData | null;
  message?: string | null;
}

interface ChaoxingLoginResp {
  status?: boolean | null;
}

interface JwtPayload {
  groupCode?: string | number | null;
}

interface SearchFilterRaw {
  searchWord: string;
  searchField: string;
  matchMode: string;
  page: number;
  docCode: string | null;
  resourceType: string | null;
  locationId: number | null;
  countryCode: string | null;
  langCode: string | null;
  onlyOnShelf: boolean | null;
  publishBegin: string | null;
  publishEnd: string | null;
}

const OPAC_BASE: string = 'https://mfindxidian.libsp.cn';
const JWT_HEADER_NAME: string = 'jwtOpacAuth';
const DEFAULT_GROUP_CODE: string = '200755';
const OPAC_LOGIN_TARGET: string =
  'https://tyrzfw.chaoxing.com/auth/xidian/cas/init?isLogout=0&refer=https%3A%2F%2Fmfindxidian.libsp.cn%2Ffind%2Fsso%2Flogin%2Fxidian%2F1';

/**
 * 图书馆会话（对应 Dart repository/ids_session/library_session.dart）。
 * 认证链：IDS CAS → 超星 tyrannyfw CAS → libsp OPAC，从跳转 Location 的 query/fragment 提取 JWT（仅内存态）；
 * groupCode 从 JWT payload 解出（默认 200755）。OPAC 每请求带 Cookie: jwt=...; jwtHeader=jwtOpacAuth 等头。
 * 书目检索不要求登录；借阅列表/续借需要完整认证链。
 */
export class LibrarySession {
  private static token: string = '';
  private static groupCode: string = '';
  private static initInflight: Promise<void> | null = null;

  private static session(): NetworkSession {
    return SessionManager.ids();
  }

  private static opacOptions(): SessionOptions {
    const opts: SessionOptions = new SessionOptions();
    opts.contentType = 'application/json;charset=utf-8';
    opts.headers.set('cookie', `jwt=${LibrarySession.token}; jwtHeader=${JWT_HEADER_NAME}`);
    opts.headers.set('referer', `${OPAC_BASE}/`);
    opts.headers.set('host', 'mfindxidian.libsp.cn');
    opts.headers.set('groupCode', LibrarySession.groupCode.length === 0 ? DEFAULT_GROUP_CODE : LibrarySession.groupCode);
    opts.headers.set('mappingPath', '');
    opts.headers.set(JWT_HEADER_NAME, LibrarySession.token);
    return opts;
  }

  private static async getOpac(url: string): Promise<SessionResponse> {
    return LibrarySession.session().get(url, LibrarySession.opacOptions());
  }

  private static async postOpac(url: string, body: Object): Promise<SessionResponse> {
    return LibrarySession.session().postRaw(url, 'application/json;charset=utf-8', JSON.stringify(body),
      LibrarySession.opacOptions());
  }

  private static ensureInitialized(): Promise<void> {
    if (LibrarySession.initInflight !== null) {
      return LibrarySession.initInflight;
    }
    if (LibrarySession.token.length > 0) {
      return Promise.resolve();
    }
    const task: Promise<void> = LibrarySession.initSessionOnce().then((): void => {
      LibrarySession.initInflight = null;
    }, (e: Object): Promise<void> => {
      LibrarySession.initInflight = null;
      throw e instanceof Error ? e : new Error(`${e}`);
    });
    LibrarySession.initInflight = task;
    return task;
  }

  private static async initSessionOnce(): Promise<void> {
    Log.info('[LibrarySession] init session');
    LibrarySession.token = '';
    LibrarySession.groupCode = '';
    try {
      const slider = backgroundSliderHandler();
      const location: string = await IdsSession.checkAndLogin(OPAC_LOGIN_TARGET, slider);
      await LibrarySession.resolveOpacLogin(location);
      if (LibrarySession.token.length === 0) {
        throw new Error('未能从认证链获取图书馆凭据');
      }
      LibrarySession.loadJwtInfo(LibrarySession.token);
      await LibrarySession.warmUp();
    } catch (e) {
      LibrarySession.token = '';
      LibrarySession.groupCode = '';
      throw e instanceof Error ? e : new Error(`${e}`);
    }
  }

  /** 跟随认证跳转链直到从 Location 提取到 JWT；超星 CAS 中间页按原版正则补参续链。 */
  private static async resolveOpacLogin(firstLocation: string): Promise<void> {
    let location: string = firstLocation;
    for (let i: number = 0; i < IdsSession.MAX_AUTH_REDIRECTS; i++) {
      LibrarySession.throwIfWechatLocation(location);
      LibrarySession.tryLoadJwtFromLocation(location);
      if (LibrarySession.token.length > 0) {
        return;
      }
      const resp: SessionResponse = await LibrarySession.session().get(location);
      const nextLocation: string = resp.location;
      if (nextLocation.length > 0) {
        location = LibrarySession.resolveLocation(location, nextLocation);
        continue;
      }
      const next: string | null = await LibrarySession.tryChaoxingCasLogin(resp.bodyText);
      if (next === null) {
        return;
      }
      location = next;
    }
    throw new Error('图书馆认证跳转次数超限');
  }

  private static async tryChaoxingCasLogin(html: string): Promise<string | null> {
    const data: string | null = LibrarySession.regexFirst(html, /data: "(.*)",/);
    const time: string | null = LibrarySession.regexFirst(html, /time: ([0-9]*),/);
    const enc: string | null = LibrarySession.regexFirst(html, /enc: "(.*)",/);
    const name: string | null = LibrarySession.regexFirst(html, /displayName: "(.*)",/);
    const userRole: string | null = LibrarySession.regexFirst(html, /userRole: ([0-9]{1}),/);
    if (data === null || time === null || enc === null || name === null || userRole === null) {
      return null;
    }
    const casLoginUrl: string = `https://tyrzfw.chaoxing.com/auth/xidian/cas/login?data=${encodeURIComponent(data)}` +
      `&time=${encodeURIComponent(time)}&enc=${encodeURIComponent(enc)}&displayName=${encodeURIComponent(name)}` +
      `&userRole=${encodeURIComponent(userRole)}&group1=&mobilePhone=`;
    const loginResp: SessionResponse = await LibrarySession.session().get(casLoginUrl);
    let isSuccess: ChaoxingLoginResp | null = null;
    try {
      isSuccess = JSON.parse(loginResp.bodyText) as ChaoxingLoginResp;
    } catch (e) {
      isSuccess = null;
    }
    if (isSuccess === null || isSuccess.status !== true) {
      throw new Error('超星统一认证登录失败');
    }
    const ssoUrl: string = `${OPAC_BASE}/find/sso/login/xidian/1?data=${encodeURIComponent(data)}` +
      `&time=${encodeURIComponent(time)}&enc=${encodeURIComponent(enc)}`;
    const ssoResp: SessionResponse = await LibrarySession.session().get(ssoUrl);
    return ssoResp.location.length > 0 ? ssoResp.location : null;
  }

  private static regexFirst(html: string, pattern: RegExp): string | null {
    const match: RegExpExecArray | null = pattern.exec(html);
    return match !== null && match.length > 1 ? match[1] : null;
  }

  private static throwIfWechatLocation(location: string): void {
    const lower: string = location.toLowerCase();
    if (lower.includes('open.weixin.qq.com') || lower.includes('wx.chaoxing.com') || lower.includes('/weixin/')) {
      throw new Error('图书馆认证跳转到了微信授权页，暂不支持');
    }
  }

  private static tryLoadJwtFromLocation(location: string): void {
    const queryJwt: string = LibrarySession.queryParamOf(location, 'jwt');
    if (queryJwt.length > 0) {
      LibrarySession.token = queryJwt;
      return;
    }
    const hashIndex: number = location.indexOf('#');
    if (hashIndex < 0) {
      return;
    }
    const fragment: string = location.substring(hashIndex + 1);
    const queryIndex: number = fragment.indexOf('?');
    if (queryIndex >= 0) {
      const fragmentJwt: string = LibrarySession.queryParamOf(fragment.substring(queryIndex + 1), 'jwt');
      if (fragmentJwt.length > 0) {
        LibrarySession.token = fragmentJwt;
      }
    }
  }

  /** 手工解析 query 串（含完整 URL 或纯 query 串）中的参数。 */
  private static queryParamOf(source: string, key: string): string {
    const queryIndex: number = source.indexOf('?');
    const query: string = queryIndex >= 0 ? source.substring(queryIndex + 1) : source;
    const pairs: string[] = query.split('&');
    for (const pair of pairs) {
      const eq: number = pair.indexOf('=');
      if (eq < 0) {
        continue;
      }
      const k: string = pair.substring(0, eq);
      if (k === key) {
        try {
          return decodeURIComponent(pair.substring(eq + 1));
        } catch (e) {
          return pair.substring(eq + 1);
        }
      }
    }
    return '';
  }

  private static resolveLocation(currentLocation: string, location: string): string {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      return location;
    }
    if (location.startsWith('/')) {
      const schemeEnd: number = currentLocation.indexOf('//');
      const pathStart: number = currentLocation.indexOf('/', schemeEnd + 2);
      return pathStart < 0 ? currentLocation + location : currentLocation.substring(0, pathStart) + location;
    }
    const lastSlash: number = currentLocation.lastIndexOf('/');
    return currentLocation.substring(0, lastSlash + 1) + location;
  }

  private static loadJwtInfo(jwt: string): void {
    const parts: string[] = jwt.split('.');
    if (parts.length < 2) {
      return;
    }
    try {
      let payloadBase: string = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      while (payloadBase.length % 4 !== 0) {
        payloadBase += '=';
      }
      const text: string = CryptoUtil.bytesToUtf8(CryptoUtil.base64Decode(payloadBase));
      const payload: JwtPayload = JSON.parse(text) as JwtPayload;
      LibrarySession.groupCode = payload.groupCode !== undefined && payload.groupCode !== null
        ? `${payload.groupCode}` : DEFAULT_GROUP_CODE;
    } catch (e) {
      Log.warn(`library jwt parse failed: ${e}`);
      LibrarySession.groupCode = DEFAULT_GROUP_CODE;
    }
  }

  private static async warmUp(): Promise<void> {
    try {
      await LibrarySession.getOpac(`${OPAC_BASE}/oga/userinfo?jwtHeader=${JWT_HEADER_NAME}&jwt=${encodeURIComponent(LibrarySession.token)}`);
    } catch (e) {
      Log.warn(`library warm up userinfo failed: ${e}`);
    }
    try {
      const groupCodeBody: GroupCodeBody = { mappingPath: '' };
      const resp: SessionResponse = await LibrarySession.postOpac(`${OPAC_BASE}/find/homePage/getGroupCode`,
        groupCodeBody);
      const parsed: JwtPayload = JSON.parse(resp.bodyText) as JwtPayload;
      if (parsed.groupCode !== undefined && parsed.groupCode !== null) {
        LibrarySession.groupCode = `${parsed.groupCode}`;
      }
    } catch (e) {
      Log.warn(`library fetch group code failed: ${e}`);
    }
  }

  // ---- 检索筛选项 ----

  private static codedOptions(rows: CodedRow[] | null | undefined): LibrarySearchOption[] {
    const options: LibrarySearchOption[] = [new LibrarySearchOption('', '全部')];
    if (rows === undefined || rows === null) {
      return options;
    }
    rows.forEach((item: CodedRow): void => {
      const code: string = item.code === undefined || item.code === null ? '' : `${item.code}`;
      const name: string = item.name === undefined || item.name === null ? '' : `${item.name}`;
      if (code.length > 0 && name.length > 0) {
        options.push(new LibrarySearchOption(code, name));
      }
    });
    return options;
  }

  private static searchFieldValue(label: string): string {
    const map: Map<string, string> = new Map<string, string>([
      ['题名', 'title'], ['责任者', 'author'], ['主题', 'subject'], ['标准号', 'isbn'],
      ['分类号', 'kindNo'], ['索书号', 'callNo'], ['出版社', 'publisher'], ['摘要', 'abstract'],
      ['条码号', 'barcode'], ['工具号', 'toolNumber']
    ]);
    const value: string | undefined = map.get(label);
    return value !== undefined ? value : '';
  }

  /** 检索字段/条件/馆藏地三项并行拉取，任一失败整体回退 fallback。 */
  static async searchFilterOptions(): Promise<LibrarySearchFilterOptions> {
    const fallback: LibrarySearchFilterOptions = LibrarySearchFilterOptions.fallback();
    try {
      const fieldResp: SessionResponse = await LibrarySession.getOpac(
        `${OPAC_BASE}/find/groupResource/getFindOpacSearchFieldParaList`);
      const fieldParsed: FieldResp = JSON.parse(fieldResp.bodyText) as FieldResp;
      const fields: LibrarySearchOption[] = [new LibrarySearchOption('keyWord', '任意词', '任意')];
      const fieldRows: FieldRow[] = fieldParsed.data !== undefined && fieldParsed.data !== null ? fieldParsed.data : [];
      fieldRows.forEach((item: FieldRow): void => {
        const label: string = item.searchField ?? '';
        const value: string = LibrarySession.searchFieldValue(label);
        if (label.length > 0 && value.length > 0) {
          fields.push(new LibrarySearchOption(value, label));
        }
      });

      const conditionResp: SessionResponse = await LibrarySession.getOpac(`${OPAC_BASE}/find/category/getConditionList`);
      const conditionParsed: ConditionResp = JSON.parse(conditionResp.bodyText) as ConditionResp;
      const conditionData: ConditionData | null =
        conditionParsed.data !== undefined && conditionParsed.data !== null ? conditionParsed.data : null;

      const locationBody: LocationBody = {
        locationName: '', campusIds: [], locationTypeCodes: [], entrust: 0, subscribe: 0, page: 1, rows: 2000
      };
      const locationResp: SessionResponse = await LibrarySession.postOpac(`${OPAC_BASE}/find/location/list`, locationBody);
      const locationParsed: LocationResp = JSON.parse(locationResp.bodyText) as LocationResp;
      const locations: LibrarySearchOption[] = [new LibrarySearchOption('', '全部')];
      const rawLocations: LocationRow[] =
        locationParsed.data !== undefined && locationParsed.data !== null
        && locationParsed.data.donateList !== undefined && locationParsed.data.donateList !== null
          ? locationParsed.data.donateList : [];
      rawLocations.forEach((item: LocationRow): void => {
        const id: string = item.locationId === undefined || item.locationId === null ? '' : `${item.locationId}`;
        const name: string = item.locationName === undefined || item.locationName === null ? '' : `${item.locationName}`;
        if (id.length > 0 && name.length > 0) {
          locations.push(new LibrarySearchOption(id, name));
        }
      });

      return new LibrarySearchFilterOptions(
        fields,
        conditionData !== null ? LibrarySession.codedOptions(conditionData.documentTypeList) : fallback.documentTypes,
        fallback.resourceTypes,
        fallback.campuses,
        locations,
        conditionData !== null ? LibrarySession.codedOptions(conditionData.countryList) : fallback.countries,
        conditionData !== null ? LibrarySession.codedOptions(conditionData.languageList) : fallback.languages,
        fallback.years
      );
    } catch (e) {
      Log.warn(`library filter options fallback: ${e}`);
      return fallback;
    }
  }

  // ---- 检索 ----

  private static searchBody(raw: SearchFilterRaw): OpacSearchBody {
    const resourceType: string[] = raw.resourceType !== null && raw.resourceType.length > 0 ? [raw.resourceType] : [];
    const langCode: string[] = raw.langCode !== null && raw.langCode.length > 0 ? [raw.langCode] : [];
    const countryCode: string[] = raw.countryCode !== null && raw.countryCode.length > 0 ? [raw.countryCode] : [];
    const locationId: number[] = raw.locationId !== null ? [raw.locationId] : [];
    return {
      docCode: [raw.docCode],
      litCode: [],
      searchFieldContent: raw.searchWord,
      searchField: raw.searchField,
      matchMode: raw.matchMode,
      resourceType: resourceType,
      subject: [],
      discode1: [],
      publisher: [],
      locationId: locationId,
      collectionName: [],
      author: [],
      langCode: langCode,
      countryCode: countryCode,
      publishBegin: raw.publishBegin,
      publishEnd: raw.publishEnd,
      coreInclude: [],
      ddType: [],
      verifyStatus: [],
      group: [],
      sortField: 'relevance',
      sortClause: 'desc',
      page: raw.page,
      rows: 10,
      onlyOnShelf: raw.onlyOnShelf,
      campusId: [],
      curLocationId: [],
      eCollectionIds: [],
      kindNo: [],
      libCode: [],
      neweCollectionIds: [],
      newCoreInclude: [],
      customSub: [],
      customSub0: []
    };
  }

  private static async fetchSearchResult(url: string, body: OpacSearchBody): Promise<BookInfo[]> {
    const resp: SessionResponse = await LibrarySession.postOpac(url, body);
    const parsed: SearchResp = JSON.parse(resp.bodyText) as SearchResp;
    const rows: SearchRowJson[] = parsed.data !== undefined && parsed.data !== null
    && parsed.data.searchResult !== undefined && parsed.data.searchResult !== null
      ? parsed.data.searchResult : [];
    const list: BookInfo[] = [];
    rows.forEach((row: SearchRowJson): void => {
      list.push(bookInfoFromOpacJson(row));
    });
    return list;
  }

  /** 简单检索（searchItems: null + indexSearch: 1，对齐原版）。 */
  static async searchBook(searchWord: string, page: number, searchField: string): Promise<BookInfo[]> {
    if (searchWord.length === 0) {
      return [];
    }
    const body: OpacSearchBody = LibrarySession.searchBody({
      searchWord: searchWord, searchField: searchField, matchMode: '2', page: page,
      docCode: null, resourceType: null, locationId: null, countryCode: null, langCode: null,
      onlyOnShelf: null, publishBegin: null, publishEnd: null
    });
    body.searchItems = null;
    body.indexSearch = 1;
    return LibrarySession.fetchSearchResult(`${OPAC_BASE}/find/unify/search`, body);
  }

  /** 高级检索（多字段组合 + 全量筛选，searchItems 单条件对齐原版 advancedSearch）。 */
  static async advancedSearchBook(raw: SearchFilterRaw): Promise<BookInfo[]> {
    const body: OpacSearchBody = LibrarySession.searchBody({
      searchWord: '', searchField: raw.searchField, matchMode: raw.matchMode, page: raw.page,
      docCode: raw.docCode, resourceType: raw.resourceType, locationId: raw.locationId,
      countryCode: raw.countryCode, langCode: raw.langCode, onlyOnShelf: raw.onlyOnShelf,
      publishBegin: raw.publishBegin !== null && raw.publishBegin.trim().length > 0 ? raw.publishBegin.trim() : null,
      publishEnd: raw.publishEnd !== null && raw.publishEnd.trim().length > 0 ? raw.publishEnd.trim() : null
    });
    const item: SearchItemsItem = {
      oper: null, searchField: raw.searchField, matchMode: raw.matchMode, searchFieldContent: raw.searchWord
    };
    body.searchItems = [item];
    body.searchFieldList = null;
    return LibrarySession.fetchSearchResult(`${OPAC_BASE}/find/unify/advancedSearch`, body);
  }

  static async bookCover(title: string, isbn: string, docNumber: number): Promise<string> {
    try {
      const body: CoverBody = { title: title, isbn: isbn, recordId: docNumber };
      const resp: SessionResponse = await LibrarySession.postOpac(
        `${OPAC_BASE}/find/unify/getPItemAndOnShelfCountAndDuxiuImageUrl`, body);
      const parsed: CoverResp = JSON.parse(resp.bodyText) as CoverResp;
      return parsed.data !== undefined && parsed.data !== null ? (parsed.data.duxiuImageUrl ?? '') : '';
    } catch (e) {
      return '';
    }
  }

  static async bookLocations(recordId: number): Promise<BookLocation[]> {
    if (recordId <= 0) {
      return [];
    }
    const body: GroupItemsBody = { page: 1, rows: 200, entrance: null, recordId: `${recordId}`, isUnify: true };
    const resp: SessionResponse = await LibrarySession.postOpac(`${OPAC_BASE}/find/physical/groupitems`, body);
    const parsed: GroupItemsResp = JSON.parse(resp.bodyText) as GroupItemsResp;
    const rows: LocationRowJson[] = parsed.data !== undefined && parsed.data !== null
    && parsed.data.list !== undefined && parsed.data.list !== null ? parsed.data.list : [];
    const list: BookLocation[] = [];
    rows.forEach((row: LocationRowJson): void => {
      list.push(bookLocationFromOpacJson(row));
    });
    return list;
  }

  /** 借阅列表（按应还日期升序；封面并行拉取）。 */
  static async getBorrowList(): Promise<BorrowData[]> {
    await LibrarySession.ensureInitialized();
    const body: LoanBody = {
      page: 1, rows: 999, searchType: 1, searchContent: '', sortType: 0, startDate: null, endDate: null
    };
    const resp: SessionResponse = await LibrarySession.postOpac(`${OPAC_BASE}/find/loanInfo/loanList`, body);
    const parsed: LoanResp = JSON.parse(resp.bodyText) as LoanResp;
    const rows: LoanRowJson[] = parsed.data !== undefined && parsed.data !== null
    && parsed.data.searchResult !== undefined && parsed.data.searchResult !== null
      ? parsed.data.searchResult : [];
    if (rows.length === 0) {
      return [];
    }
    const list: BorrowData[] = [];
    const coverTasks: Promise<void>[] = [];
    rows.forEach((row: LoanRowJson): void => {
      const item: BorrowData = borrowDataFromJson(row);
      if (item.recordId > 0) {
        coverTasks.push(LibrarySession.bookCover(item.title, item.isbn, item.recordId).then((url: string): void => {
          item.imageUrl = url;
        }));
      }
      list.push(item);
    });
    await Promise.all(coverTasks);
    list.sort((a: BorrowData, b: BorrowData): number =>
      a.normReturnDateTime().getTime() - b.normReturnDateTime().getTime());
    return list;
  }

  /** 续借：data.success>0 视为成功，新日期取 result 首个值。 */
  static async renew(loanId: number): Promise<string> {
    await LibrarySession.ensureInitialized();
    const body: RenewBody = { loanIds: [loanId] };
    const resp: SessionResponse = await LibrarySession.postOpac(`${OPAC_BASE}/find/lendbook/reNew`, body);
    const parsed: RenewResp = JSON.parse(resp.bodyText) as RenewResp;
    const data: RenewData | null = parsed.data !== undefined && parsed.data !== null ? parsed.data : null;
    const success: number | null = data !== null && data.success !== undefined ? data.success : null;
    if (data !== null && data.result !== undefined) {
      const result: Record<string, string> = data.result;
      const keys: string[] = Object.keys(result);
      if (success !== null && success > 0) {
        const newDate: string = keys.length > 0 ? result[keys[0]] : '';
        return newDate.length === 0 ? '续借成功' : `续借成功，新还书日期：${newDate}`;
      }
      const values: string[] = keys.map((k: string): string => result[k]);
      if (values.length > 0) {
        return values.join('\n');
      }
    }
    if (success !== null && success > 0) {
      return '续借成功';
    }
    return parsed.message !== undefined && parsed.message !== null && parsed.message.length > 0
      ? parsed.message : '续借失败';
  }
}
