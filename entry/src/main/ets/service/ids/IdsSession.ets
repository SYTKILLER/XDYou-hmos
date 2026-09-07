import { HtmlParser, HtmlNode } from '../../utils/html/HtmlParser';
import { UrlUtil } from '../../utils/net/UrlUtil';
import { IdsCrypto } from './IdsCrypto';
import { IdsReAuthClient } from './IdsReAuthClient';
import { IdsReAuthCancelledError, IdsReAuthExpiredError, IdsReAuthRequiredError,
  isReAuthLocation } from './IdsAuthProtocol';
import { SliderCaptchaHandler } from './SliderCaptchaHandler';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { SessionManager } from '../SessionManager';
import { PreferenceService } from '../preference/PreferenceService';
import { Log } from '../../utils/Log';

export class PasswordWrongError extends Error {
}

export class LoginFailedError extends Error {
}

export class CaptchaSolveFailedError extends Error {
}

export type LoginProgressCallback = (percent: number, messageKey: string) => void;

/**
 * 二次认证处理回调：完成短信验证后 resolve 续跳 URI（对应 Dart IDSReAuthHandler）。
 */
export type ReAuthHandler = (client: IdsReAuthClient) => Promise<string>;

const LOGIN_ORIGIN: string = 'https://ids.xidian.edu.cn';
const LOGIN_URL: string = 'https://ids.xidian.edu.cn/authserver/login';

/**
 * IDS 统一认证会话（对应 Dart IDSSession）。
 * CAS 登录协议：取登录页 → 浏览器指纹 → hidden 表单（lt/execution/pwdEncryptSalt）→
 * 滑块验证码 → 提交 → 301/302 闭环或 form#continue 续跳。
 * 全流程串行化（对应 Dart _idsLock）。
 */
export class IdsSession {
  static readonly MAX_AUTH_REDIRECTS: number = 30;
  private static lockTail: Promise<void> = Promise.resolve();
  private static reAuthTail: Promise<void> = Promise.resolve();
  private static activeReAuthHandler: ReAuthHandler | null = null;

  /**
   * 设置全局二次认证处理器（对应 Dart activeIDSReAuthHandler，供登录后服务刷新续登复用）。
   */
  static setActiveReAuthHandler(handler: ReAuthHandler | null): void {
    IdsSession.activeReAuthHandler = handler;
  }

  private static runExclusive<T>(fn: () => Promise<T>): Promise<T> {
    const run: Promise<T> = IdsSession.lockTail.then((): Promise<T> => fn());
    IdsSession.lockTail = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  private static runReAuthExclusive<T>(fn: () => Promise<T>): Promise<T> {
    const run: Promise<T> = IdsSession.reAuthTail.then((): Promise<T> => fn());
    IdsSession.reAuthTail = run.then((): void => {
    }, (): void => {
    });
    return run;
  }

  private static session(): NetworkSession {
    return SessionManager.ids();
  }

  static isRedirect(response: SessionResponse): boolean {
    return response.statusCode === 301 || response.statusCode === 302;
  }

  /**
   * 命中二次认证挑战页时执行 handler（对应 Dart resolveIDSReAuthIfNeeded）。
   * 取消/过期时清空 IDS Cookie（对应 Dart deleteAll）。
   */
  private static async resolveReAuthIfNeeded(targetUrl: string, service: string, username: string,
    handler: ReAuthHandler | null): Promise<string> {
    if (!isReAuthLocation(targetUrl)) {
      return targetUrl;
    }
    const effectiveHandler: ReAuthHandler | null = handler !== null ? handler : IdsSession.activeReAuthHandler;
    if (effectiveHandler === null) {
      throw new IdsReAuthRequiredError();
    }
    return IdsSession.runReAuthExclusive<string>(async (): Promise<string> => {
      const client: IdsReAuthClient = new IdsReAuthClient(targetUrl, username, service);
      try {
        return await effectiveHandler(client);
      } catch (e) {
        const err: Error = e instanceof Error ? e : new Error(String(e));
        if (err instanceof IdsReAuthCancelledError || err instanceof IdsReAuthExpiredError) {
          SessionManager.clearStore('ids');
          Log.warn('reAuth cancelled/expired, ids cookies cleared');
        }
        throw err;
      }
    });
  }

  /**
   * 解析 301/302 的 Location，处理二次认证，返回续跳 URI。
   */
  private static async completeRedirect(response: SessionResponse, username: string, service: string,
    handler: ReAuthHandler | null): Promise<string> {
    if (response.location.length === 0) {
      throw new LoginFailedError('统一认证跳转响应缺少 Location');
    }
    const resolved: string = UrlUtil.resolveRedirect(response.finalUrl, response.location);
    return IdsSession.resolveReAuthIfNeeded(resolved, service, username, handler);
  }

  private static parsePasswordWrongMsg(html: string): string {
    const tip: HtmlNode | null = HtmlParser.getElementById(HtmlParser.parse(html), 'showErrorTip');
    let msg: string = tip !== null ? tip.textContent() : '登录遇到问题';
    if (/(用户名|密码)[\s\S]*误/.test(msg)) {
      msg = '用户名或密码有误';
    }
    return msg;
  }

  private static async registerBrowserFingerprint(): Promise<void> {
    const fingerprint: string = IdsCrypto.getOrCreateBrowserFingerprint();
    await IdsSession.session().get(
      `https://ids.xidian.edu.cn/authserver/bfp/info?bfp=${fingerprint}&_=${Date.now()}`);
  }

  /**
   * 提取 hidden input 的 value：优先按 id（pwdEncryptSalt），否则按 name（lt/execution）。
   */
  private static hiddenValue(page: HtmlNode, key: string): string {
    const inputs: HtmlNode[] = HtmlParser.getElementsByTagName(page, 'input');
    for (let i = 0; i < inputs.length; i++) {
      const node: HtmlNode = inputs[i];
      if (node.attr('type') !== 'hidden') {
        continue;
      }
      if (node.id() === key || node.attr('name') === key) {
        return node.attr('value');
      }
    }
    throw new LoginFailedError(`登录页缺少隐藏域：${key}`);
  }

  private static serviceQuery(target: string): string {
    return target.length > 0 ? `?service=${encodeURIComponent(target)}` : '';
  }

  /**
   * 完整登录（对应 Dart _loginOnce）。返回 CAS 跳转链的起始 Location。
   */
  private static async loginOnce(username: string, password: string, sliderCaptcha: SliderCaptchaHandler,
    onResponse: LoginProgressCallback | null, target: string, handler: ReAuthHandler | null): Promise<string> {
    const session: NetworkSession = IdsSession.session();
    if (onResponse !== null) {
      onResponse(10, 'login_progress_ready_page');
    }
    const initial: SessionResponse = await session.get(`${LOGIN_URL}${IdsSession.serviceQuery(target)}`);
    if (IdsSession.isRedirect(initial)) {
      return IdsSession.completeRedirect(initial, username, target, handler);
    }

    if (onResponse !== null) {
      onResponse(20, 'login_progress_get_encrypt');
    }
    await IdsSession.registerBrowserFingerprint();
    const page: HtmlNode = HtmlParser.parse(initial.bodyText);
    const salt: string = IdsSession.hiddenValue(page, 'pwdEncryptSalt');
    const lt: string = IdsSession.hiddenValue(page, 'lt');
    const execution: string = IdsSession.hiddenValue(page, 'execution');
    const encryptedPassword: string = await IdsCrypto.encryptIdsPassword(password, salt);

    if (onResponse !== null) {
      onResponse(40, 'login_progress_ready_login');
    }
    await session.get(`https://ids.xidian.edu.cn/authserver/common/openSliderCaptcha.htl?_=${Date.now()}`);

    if (onResponse !== null) {
      onResponse(45, 'login_progress_slider');
    }
    const cookieStr: string = session.cookies.cookieHeader('https://ids.xidian.edu.cn/authserver');
    try {
      await sliderCaptcha(cookieStr);
    } catch (e) {
      Log.warn(`slider captcha failed: ${e}`);
      throw new LoginFailedError('验证码校验失败');
    }

    if (onResponse !== null) {
      onResponse(50, 'login_progress_submitting');
    }
    const fields: Map<string, string> = new Map();
    fields.set('username', username);
    fields.set('password', encryptedPassword);
    fields.set('rememberMe', 'true');
    fields.set('cllt', 'userNameLogin');
    fields.set('dllt', 'generalLogin');
    fields.set('_eventId', 'submit');
    fields.set('lt', lt);
    fields.set('execution', execution);
    const submit: SessionResponse = await session.postForm(`${LOGIN_URL}${IdsSession.serviceQuery(target)}`, fields);
    if (submit.statusCode === 401) {
      throw new PasswordWrongError(IdsSession.parsePasswordWrongMsg(submit.bodyText));
    }
    if (IdsSession.isRedirect(submit)) {
      return IdsSession.completeRedirect(submit, username, target, handler);
    }

    // CAS 续跳：解析 form#continue 并重新提交。
    const continueForm: HtmlNode | null = HtmlParser.getElementById(HtmlParser.parse(submit.bodyText), 'continue');
    if (continueForm !== null && continueForm.tag === 'form') {
      const inputs: HtmlNode[] = HtmlParser.getElementsByTagName(continueForm, 'input');
      const again: Map<string, string> = new Map();
      for (let i = 0; i < inputs.length; i++) {
        const name: string = inputs[i].attr('name');
        const value: string = inputs[i].attr('value');
        if (name.length > 0) {
          again.set(name, value);
        }
      }
      if (again.size > 0) {
        const continued: SessionResponse = await session.postForm(LOGIN_URL, again);
        if (continued.statusCode === 401) {
          throw new PasswordWrongError(IdsSession.parsePasswordWrongMsg(continued.bodyText));
        }
        if (IdsSession.isRedirect(continued)) {
          return IdsSession.completeRedirect(continued, username, target, handler);
        }
        throw new LoginFailedError(`登录失败，响应状态码：${continued.statusCode}。`);
      }
    }
    throw new LoginFailedError(`登录失败，响应状态码：${submit.statusCode}。`);
  }

  /**
   * 登录（对应 Dart IDSSession.login）。返回 CAS 跳转链起始 Location。
   */
  static login(username: string, password: string, sliderCaptcha: SliderCaptchaHandler,
    onResponse?: LoginProgressCallback, target?: string, reAuthHandler?: ReAuthHandler): Promise<string> {
    return IdsSession.runExclusive<string>(async (): Promise<string> => {
      const captchaHandler: SliderCaptchaHandler = sliderCaptcha;
      const callback: LoginProgressCallback | null = onResponse !== undefined ? onResponse : null;
      const service: string = target !== undefined ? target : '';
      const handler: ReAuthHandler | null = reAuthHandler !== undefined ? reAuthHandler : null;
      return IdsSession.loginOnce(username, password, captchaHandler, callback, service, handler);
    });
  }

  /**
   * 会话有效性检查 + 静默续登（对应 Dart checkAndLogin）。返回 CAS 跳转链起始 Location。
   */
  static checkAndLogin(target: string, sliderCaptcha: SliderCaptchaHandler,
    reAuthHandler?: ReAuthHandler): Promise<string> {
    return IdsSession.runExclusive<string>(async (): Promise<string> => {
      const handler: ReAuthHandler | null = reAuthHandler !== undefined ? reAuthHandler : null;
      const username: string = PreferenceService.getString('idsAccount', '');
      const session: NetworkSession = IdsSession.session();
      const response: SessionResponse = await session.get(`${LOGIN_URL}?service=${encodeURIComponent(target)}`);
      if (IdsSession.isRedirect(response)) {
        return IdsSession.completeRedirect(response, username, target, handler);
      }
      const page: HtmlNode = HtmlParser.parse(response.bodyText);
      const continueForm: HtmlNode | null = HtmlParser.getElementById(page, 'continue');
      if (continueForm !== null && continueForm.tag === 'form') {
        const fields: Map<string, string> = new Map();
        const inputs: HtmlNode[] = HtmlParser.getElementsByTagName(continueForm, 'input');
        for (let i = 0; i < inputs.length; i++) {
          const name: string = inputs[i].attr('name');
          const value: string = inputs[i].attr('value');
          if (name.length > 0) {
            fields.set(name, value);
          }
        }
        if (fields.size > 0) {
          const continued: SessionResponse = await session.postForm(LOGIN_URL, fields);
          if (IdsSession.isRedirect(continued)) {
            return IdsSession.completeRedirect(continued, username, target, handler);
          }
        }
      }
      const password: string = PreferenceService.getString('idsPassword', '');
      return IdsSession.loginOnce(username, password, sliderCaptcha, null, target, handler);
    });
  }

  /**
   * 跟随 CAS 登录后的整条跳转链直到落地页（对应 Dart followIDSRedirects）。
   * 每一跳请求前检查二次认证挑战。
   */
  static async followRedirects(initialLocation: string, reAuthHandler?: ReAuthHandler): Promise<SessionResponse> {
    const handler: ReAuthHandler | null = reAuthHandler !== undefined ? reAuthHandler : null;
    const session: NetworkSession = IdsSession.session();
    const username: string = PreferenceService.getString('idsAccount', '');
    let currentUrl: string = UrlUtil.resolveRedirect(LOGIN_ORIGIN, initialLocation);
    let redirectCount: number = 0;
    for (; ;) {
      currentUrl = await IdsSession.resolveReAuthIfNeeded(currentUrl, '', username, handler);
      const options: SessionOptions = new SessionOptions();
      const response: SessionResponse = await session.get(currentUrl, options);
      if (response.location.length === 0) {
        return response;
      }
      redirectCount++;
      if (redirectCount > IdsSession.MAX_AUTH_REDIRECTS) {
        throw new LoginFailedError('统一认证跳转次数超过 30 次');
      }
      currentUrl = UrlUtil.resolveRedirect(response.finalUrl, response.location);
      Log.info(`followRedirects #${redirectCount} -> ${UrlUtil.hostOf(currentUrl)}${UrlUtil.pathOf(currentUrl)}`);
    }
  }

  /**
   * 判断当前账号是否研究生（对应 Dart checkWhetherPostgraduate），写入 role 偏好。
   */
  static async checkWhetherPostgraduate(sliderCaptcha: SliderCaptchaHandler,
    reAuthHandler?: ReAuthHandler): Promise<boolean> {
    const location: string = await IdsSession.checkAndLogin(
      'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/portal/index.do', sliderCaptcha, reAuthHandler);
    await IdsSession.followRedirects(location, reAuthHandler);
    const response: SessionResponse = await IdsSession.session().postForm(
      'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getCanVisitAppList.do', new Map());
    interface CanVisitAppList {
      res?: Array<Object>;
    }
    let isPostgraduate: boolean = false;
    try {
      const parsed: CanVisitAppList = JSON.parse(response.bodyText) as CanVisitAppList;
      // 对应 Dart data["res"] != null：无研究生应用授权时服务端返回 res 为 null（字段存在但值为 null），
      // 必须判空而非判存在——判存在会把本科生误判为研究生，导致成绩/考试走 yjspt 被 ACL 403（2026-09-07 真机实证）。
      isPostgraduate = parsed.res !== undefined && parsed.res !== null;
    } catch (e) {
      Log.warn(`checkWhetherPostgraduate parse failed: ${e}`);
    }
    PreferenceService.putBool('role', isPostgraduate);
    return isPostgraduate;
  }
}
