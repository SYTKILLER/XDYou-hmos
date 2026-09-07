import { HtmlParser, HtmlNode } from '../../utils/html/HtmlParser';
import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { SessionManager } from '../SessionManager';
import { PreferenceService } from '../preference/PreferenceService';
import { GeneralNetworkUsage, IpUsageRow, CurrentUserNetInfo, CurrentUserNetInfoJson, GeneralNetworkUsageJson } from '../../model/schoolnet/NetworkUsage';
import { FetchResult } from '../../model/FetchResult';
import { AppContext } from '../AppContext';
import { Log } from '../../utils/Log';

/**
 * 验证码交互回调（对应 Dart captchaFunction）：收到图片字节后由 UI 呈现，
 * 返回用户输入的验证码；返回空串表示放弃（会话层按验证码失败处理）。
 * refresh() 拉取一张新验证码（含 refresh=1 预请求）。
 */
export type SchoolnetCaptchaHandler =
  (imageBytes: Uint8Array, refresh: () => Promise<Uint8Array>) => Promise<string>;

// ---- zfw 自助服务登录页/校验响应 JSON 形状 ----

interface ValidateResp {
  success?: boolean;
  message?: string | null;
}

const ZFW_BASE: string = 'https://zfw.xidian.edu.cn';
const RAD_USER_INFO_URL: string = 'https://w.xidian.edu.cn/cgi-bin/rad_user_info';

/**
 * 校园网会话（对应 Dart repository/miscellaneous_session/schoolnet_session.dart）。
 * 两条数据线：
 * 1. rad_user_info（w.xidian.edu.cn，JSONP，无需登录态）——当前在线信息；
 * 2. zfw 自助服务（schoolnet 会话，HTML 抓取）——已用/剩余/结算 + 在线设备列表；
 *    未登录时走登录链：/login 提取 csrf 与 RSA 公钥 → 图片验证码（UI 交互）→
 *    RSA-PKCS1 加密密码 → /site/validate-user 校验 → POST / 登录 → /home 抓取。
 * 用量解析失败/验证码放弃/网络异常时可回退缓存（内存优先、磁盘兜底，照搬 Dart 回退语义）。
 */
export class SchoolnetSession {
  static readonly CACHE_FILE: string = 'schoolnet_usage.json';
  static readonly USER_CACHE_FILE: string = 'schoolnet_user.json';

  private static generalUsageCache: GeneralNetworkUsage | null = null;
  private static generalUsageCacheFetchTime: number = 0;

  private static account(): string {
    return PreferenceService.getString('idsAccount', '');
  }

  /**
   * 用量缓存读取：内存命中直接返回；未命中读磁盘并回填内存——
   * 供首页/页面冷启动直读，也让"验证码放弃回退缓存"在冷启动后依然有缓存可回。
   */
  static getCacheData(): GeneralNetworkUsage | null {
    if (SchoolnetSession.generalUsageCache !== null) {
      return SchoolnetSession.generalUsageCache;
    }
    const text: string | null = AppContext.readCacheText(SchoolnetSession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return null;
    }
    try {
      const usage: GeneralNetworkUsage =
        GeneralNetworkUsage.fromCacheJson(JSON.parse(text) as GeneralNetworkUsageJson);
      SchoolnetSession.generalUsageCache = usage;
      return usage;
    } catch (e) {
      Log.warn(`schoolnet usage cache parse failed: ${e}`);
      return null;
    }
  }

  /** 缓存抓取时间：内存记录优先，磁盘回落文件 mtime（秒精度×1000）。 */
  static cacheFetchTime(): number {
    if (SchoolnetSession.generalUsageCacheFetchTime > 0) {
      return SchoolnetSession.generalUsageCacheFetchTime;
    }
    return AppContext.cacheModifiedMs(SchoolnetSession.CACHE_FILE);
  }

  /** 成功抓取后统一落缓存（内存 + 磁盘）；所有写缓存路径必须经过这里。 */
  private static storeUsage(usage: GeneralNetworkUsage): void {
    SchoolnetSession.generalUsageCache = usage;
    SchoolnetSession.generalUsageCacheFetchTime = Date.now();
    AppContext.writeCacheText(SchoolnetSession.CACHE_FILE, JSON.stringify(usage.toCacheJson()));
  }

  /** 在线信息快照读取（冷启动首页瓦片直读，与页面"流量使用情况"同数据源）。 */
  static getUserCacheData(): CurrentUserNetInfo | null {
    const text: string | null = AppContext.readCacheText(SchoolnetSession.USER_CACHE_FILE);
    if (text === null || text.length === 0) {
      return null;
    }
    try {
      return CurrentUserNetInfo.fromJson(JSON.parse(text) as CurrentUserNetInfoJson);
    } catch (e) {
      Log.warn(`schoolnet user cache parse failed: ${e}`);
      return null;
    }
  }

  /**
   * 当前在线信息（无需登录态）。JSONP 形如 jsonp({...})——照搬 Dart 去头去尾后解析。
   */
  static async getCurrentUserNetInfo(): Promise<CurrentUserNetInfo> {
    const session: NetworkSession = SessionManager.general();
    const options: SessionOptions = new SessionOptions();
    options.headers.set('referer', 'https://w.xidian.edu.cn/index.html');
    const response: SessionResponse = await session.get(
      `${RAD_USER_INFO_URL}?callback=jsonp&_=${Date.now()}`, options);
    const raw: string = response.bodyText.trim();
    Log.info(`schoolnet rad_user_info http=${response.statusCode} len=${raw.length}`);
    if (raw.length < 8) {
      throw new Error('在线信息获取失败：响应为空');
    }
    const jsonString: string = raw.substring(6, raw.length - 1);
    const info: CurrentUserNetInfo = CurrentUserNetInfo.fromJson(JSON.parse(jsonString) as CurrentUserNetInfoJson);
    info.syncDisplayName();
    // 无论 error 位是否为空都落盘：数据本身（套餐/已用/剩余）与页面"流量使用情况"区一致可用。
    AppContext.writeCacheText(SchoolnetSession.USER_CACHE_FILE, JSON.stringify(info.toCacheJson()));
    return info;
  }

  /**
   * zfw 自助服务用量（完整登录链，照搬 Dart getGeneralNetworkUsage）。
   * 密码未配置直接抛错；验证码放弃按验证码失败处理；网络/解析异常回退内存缓存。
   */
  static async getGeneralNetworkUsage(captchaFunction: SchoolnetCaptchaHandler):
    Promise<FetchResult<GeneralNetworkUsage>> {
    try {
      const password: string = PreferenceService.getString('schoolNetQueryPassword', '');
      if (password.length === 0) {
        throw new Error('未配置校园网查询密码');
      }
      const username: string = SchoolnetSession.account();
      const schoolnet: NetworkSession = SessionManager.schoolnet();

      // 先试直接抓 /home：未重定向说明登录态有效。
      const home: SessionResponse = await schoolnet.get(`${ZFW_BASE}/home`, new SessionOptions());
      if (!home.isRedirect) {
        const usage: GeneralNetworkUsage = SchoolnetSession.parseUsage(home.bodyText);
        SchoolnetSession.storeUsage(usage);
        SessionManager.save('schoolnet');
        return FetchResult.fresh<GeneralNetworkUsage>(usage);
      }

      // 登录页：提取 csrf 与 RSA 公钥（name 含 csrf / id 含 public，照搬 Dart）。
      const loginPage: SessionResponse = await schoolnet.get(`${ZFW_BASE}/login`, new SessionOptions());
      const inputs: HtmlNode[] = HtmlParser.getElementsByTagName(HtmlParser.parse(loginPage.bodyText), 'input');
      let csrf: string = '';
      let key: string = '';
      for (let i = 0; i < inputs.length; i++) {
        if (inputs[i].attr('name').includes('csrf') && csrf.length === 0) {
          csrf = inputs[i].attr('value');
        }
        if (inputs[i].attr('id').includes('public') && key.length === 0) {
          key = inputs[i].attr('value');
        }
        if (csrf.length > 0 && key.length > 0) {
          break;
        }
      }
      if (csrf.length === 0 || key.length === 0) {
        throw new Error('自助服务页面解析失败：缺少 csrf 或公钥');
      }

      // 验证码：refresh=1 预请求后抓图片字节；用户放弃 → 按验证码失败（可回退缓存）。
      const refreshCaptcha = (): Promise<Uint8Array> => SchoolnetSession.refreshCaptcha(schoolnet);
      const picture: Uint8Array = await refreshCaptcha();
      const verifycode: string = await captchaFunction(picture, refreshCaptcha);
      if (verifycode.length === 0) {
        throw new Error('验证码校验失败');
      }
      Log.info(`[SchoolnetSession] verifycode received (len=${verifycode.length})`);

      // RSA 公钥加密密码（PEM/DER → convertKey → PKCS1，密钥位长按 DER 长度启发）。
      const encryptedPassword: string =
        await SchoolnetSession.encryptPassword(password, key);

      const loginHeaders = (): SessionOptions => {
        const opts: SessionOptions = new SessionOptions();
        opts.headers.set('X-CSRF-Token', csrf);
        opts.headers.set('X-Requested-With', 'XMLHttpRequest');
        opts.headers.set('accept', '*/*');
        return opts;
      };

      // 预登录校验（用户名/密码错误不再重试，照搬 Dart）。
      const validateFields: Map<string, string> = new Map();
      validateFields.set('LoginForm[username]', username);
      validateFields.set('LoginForm[password]', encryptedPassword);
      validateFields.set('LoginForm[verifyCode]', verifycode);
      const validate: SessionResponse =
        await schoolnet.postForm(`${ZFW_BASE}/site/validate-user`, validateFields, loginHeaders());
      const validateText: string = validate.bodyText.trim();
      if (!validateText.startsWith('{')) {
        throw new Error('自助服务校验响应异常（可能不在校园网环境）');
      }
      const validateParsed: ValidateResp = JSON.parse(validateText) as ValidateResp;
      if (validateParsed.success !== true) {
        const message: string = validateParsed.message !== undefined && validateParsed.message !== null
          ? validateParsed.message : 'unknown';
        Log.warn(`[SchoolnetSession] validate failed: ${message}`);
        if (message.includes('用户名') || message.includes('密码')) {
          throw new Error(`用户名或密码错误：${message}`);
        }
        throw new Error(message);
      }

      // 登录提交（_csrf-8800 字段名照搬 Dart）。
      const loginFields: Map<string, string> = new Map();
      loginFields.set('_csrf-8800', csrf);
      loginFields.set('LoginForm[username]', username);
      loginFields.set('LoginForm[password]', encryptedPassword);
      loginFields.set('LoginForm[smsCode]', '');
      loginFields.set('LoginForm[verifyCode]', verifycode);
      await schoolnet.postForm(`${ZFW_BASE}/`, loginFields, loginHeaders());

      const usagePage: SessionResponse = await schoolnet.get(`${ZFW_BASE}/home`, new SessionOptions());
      const usage: GeneralNetworkUsage = SchoolnetSession.parseUsage(usagePage.bodyText);
      SchoolnetSession.storeUsage(usage);
      SessionManager.save('schoolnet');
      return FetchResult.fresh<GeneralNetworkUsage>(usage);
    } catch (e) {
      const message: string = `${e}`;
      const canUseCache: boolean = message.includes('验证码') || message.includes('自助服务')
        || message.includes('网络') || message.includes('连接') || message.includes('超时');
      const cached: GeneralNetworkUsage | null = SchoolnetSession.getCacheData();
      if (cached !== null && canUseCache) {
        Log.warn(`[SchoolnetSession] fallback usage cache: ${message}`);
        return FetchResult.cached<GeneralNetworkUsage>(
          cached, SchoolnetSession.cacheFetchTime(), 'school_net.cache_hint_request_failed');
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new Error(`${e}`);
    }
  }

  /** 验证码刷新：refresh=1 使下一张图生效，再抓图片字节（照搬 Dart refreshCaptcha）。 */
  private static async refreshCaptcha(schoolnet: NetworkSession): Promise<Uint8Array> {
    const pre: SessionOptions = new SessionOptions();
    await schoolnet.get(`${ZFW_BASE}/site/captcha?refresh=1&_=${Date.now()}`, pre);
    const imageResp: SessionResponse = await schoolnet.get(`${ZFW_BASE}/site/captcha`, new SessionOptions());
    if (imageResp.bodyBytes === null || imageResp.bodyBytes.byteLength === 0) {
      throw new Error('验证码图片获取失败');
    }
    return new Uint8Array(imageResp.bodyBytes.slice(0));
  }

  /** PEM/DER 公钥 → RSA-PKCS1 加密 → base64（密钥位长按 DER 长度启发式判断）。 */
  private static async encryptPassword(password: string, key: string): Promise<string> {
    const base64: string = key
      .replace(/-----BEGIN PUBLIC KEY-----/, '')
      .replace(/-----END PUBLIC KEY-----/, '')
      .replace(/\s+/g, '');
    const der: Uint8Array = CryptoUtil.base64Decode(base64);
    const keyBits: number = der.length > 220 ? 2048 : 1024;
    const publicKey = await CryptoUtil.importRsaPublicKey(der, keyBits);
    return CryptoUtil.base64Encode(await CryptoUtil.rsaEncryptPkcs1(publicKey, CryptoUtil.utf8Bytes(password)));
  }

  /**
   * /home HTML 抓取解析（照搬 Dart _getNetworkUsage）：
   * tr 有 7 个 td → 在线设备行 (ip, online_time, used_t)；tr 有 4 个 td → 用量行，
   * 产品名含 联通/移动/电信 的运营商行跳过（排除法，照搬 Dart 注释语义）。
   */
  private static parseUsage(page: string): GeneralNetworkUsage {
    try {
      const rows: HtmlNode[] = HtmlParser.getElementsByTagName(HtmlParser.parse(page), 'tr');
      const ipList: IpUsageRow[] = [];
      let used: string = '';
      let rest: string = '';
      let charged: string = '';
      for (let i = 0; i < rows.length; i++) {
        const tdList: HtmlNode[] = HtmlParser.getElementsByTagName(rows[i], 'td');
        if (tdList.length === 7) {
          const usedT: string = tdList[2].textContent();
          if (usedT.length > 0) {
            ipList.push(new IpUsageRow(tdList[1].textContent(), tdList[3].textContent(), usedT));
          }
        } else if (tdList.length === 4) {
          const productName: string = tdList[0].textContent().trim();
          const lowerName: string = productName.toLowerCase();
          const isOperator: boolean = lowerName.includes('联通') || lowerName.includes('移动')
            || lowerName.includes('电信');
          if (!isOperator) {
            used = tdList[1].textContent().trim();
            rest = tdList[2].textContent().trim();
            charged = tdList[3].textContent().trim();
          }
        }
      }
      return new GeneralNetworkUsage(ipList, used, rest, charged);
    } catch (e) {
      Log.warn(`[SchoolnetSession] usage parse failed: ${e}`);
      throw new Error('自助服务用量解析失败');
    }
  }
}
