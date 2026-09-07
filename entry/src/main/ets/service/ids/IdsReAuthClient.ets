import { url } from '@kit.ArkTS';
import { IdsCrypto } from './IdsCrypto';
import { IdsProtocolError, IdsReAuthExpiredError, IdsSmsDelivery, IdsReAuthCodeRejectedError,
  isReAuthLocation, parseSmsDelivery, parseReAuthSubmit } from './IdsAuthProtocol';
import { NetworkSession, SessionResponse } from '../network/NetworkSession';
import { SessionManager } from '../SessionManager';
import { UrlUtil } from '../../utils/net/UrlUtil';

/**
 * 短信二次认证客户端（对应 Dart IDSReAuthClient）。
 * prepare()：GET 挑战页 → 注册浏览器指纹 → 切换短信认证类型；
 * sendSms()：下发短信（含已发送态）；
 * submitSms()：提交验证码（skipTmpReAuth=信任此设备）→ 换取业务系统登录票据 URI。
 */
export class IdsReAuthClient {
  private session: NetworkSession;
  private challengeUri: string;
  private username: string;
  private service: string;
  private prepared: boolean = false;
  private isMultifactor: string = 'true';
  recipientDescription: string = '';

  constructor(challengeUri: string, username: string, service: string) {
    this.challengeUri = challengeUri;
    this.username = username;
    this.service = service;
    this.session = SessionManager.ids();
    try {
      const parsed: url.URL = new url.URL(challengeUri);
      const multifactor: string | null = parsed.params.get('isMultifactor');
      if (multifactor !== null && multifactor.length > 0) {
        this.isMultifactor = multifactor;
      }
      const serviceParam: string | null = parsed.params.get('service');
      if (serviceParam !== null && serviceParam.length > 0 && this.service.length === 0) {
        this.service = serviceParam;
      }
    } catch (e) {
      // 解析失败保持默认 isMultifactor='true'
    }
  }

  async prepare(): Promise<void> {
    if (this.prepared) {
      return;
    }
    const challengeResponse: SessionResponse = await this.session.get(this.challengeUri);
    if (challengeResponse.statusCode !== 200) {
      throw new IdsReAuthExpiredError('二次认证已失效，请重新登录');
    }
    const fingerprint: string = IdsCrypto.getOrCreateBrowserFingerprint();
    await this.session.get(`https://ids.xidian.edu.cn/authserver/bfp/info?bfp=${fingerprint}&_=${Date.now()}`);

    const fields: Map<string, string> = new Map();
    fields.set('isMultifactor', this.isMultifactor);
    fields.set('reAuthType', '3');
    fields.set('service', this.service);
    const response: SessionResponse =
      await this.session.postForm('https://ids.xidian.edu.cn/authserver/reAuthCheck/changeReAuthType.do', fields);
    const json: ChangeTypeJson = IdsReAuthClient.toJson(response.bodyText) as ChangeTypeJson;
    const code: string = json.code !== undefined ? json.code.toString() : '';
    if (code !== '1') {
      throw new IdsProtocolError(json.message !== undefined ? json.message : '无法切换到短信二次认证');
    }
    if (json.data !== undefined && json.data.reAuthUserNameInput !== undefined) {
      this.recipientDescription = json.data.reAuthUserNameInput;
    }
    this.prepared = true;
  }

  async sendSms(): Promise<IdsSmsDelivery> {
    await this.prepare();
    const fields: Map<string, string> = new Map();
    fields.set('userName', this.username);
    fields.set('authCodeTypeName', 'reAuthDynamicCodeType');
    const response: SessionResponse = await this.session.postForm(
      'https://ids.xidian.edu.cn/authserver/dynamicCode/getDynamicCodeByReauth.do', fields);
    return parseSmsDelivery(response.bodyText);
  }

  async submitSms(code: string, trustDevice: boolean): Promise<string> {
    await this.prepare();
    const normalizedCode: string = code.trim();
    if (normalizedCode.length === 0) {
      throw new IdsReAuthCodeRejectedError('请输入短信验证码');
    }
    const fields: Map<string, string> = new Map();
    fields.set('service', this.service);
    fields.set('reAuthType', '3');
    fields.set('isMultifactor', this.isMultifactor);
    fields.set('password', '');
    fields.set('dynamicCode', normalizedCode);
    fields.set('uuid', '');
    fields.set('answer1', '');
    fields.set('answer2', '');
    fields.set('otpCode', '');
    fields.set('skipTmpReAuth', trustDevice ? 'true' : 'false');
    const response: SessionResponse =
      await this.session.postForm('https://ids.xidian.edu.cn/authserver/reAuthCheck/reAuthSubmit.do', fields);
    parseReAuthSubmit(response.bodyText);

    const loginQuery: string = this.service.length > 0 ? `?service=${encodeURIComponent(this.service)}` : '';
    const loginResponse: SessionResponse =
      await this.session.get(`https://ids.xidian.edu.cn/authserver/login${loginQuery}`);
    const isRedirect: boolean = loginResponse.statusCode === 301 || loginResponse.statusCode === 302;
    if (!isRedirect || loginResponse.location.length === 0) {
      throw new IdsProtocolError('二次认证成功，但没有收到业务系统登录票据');
    }
    const resolved: string = UrlUtil.resolveRedirect(loginResponse.finalUrl, loginResponse.location);
    if (isReAuthLocation(resolved)) {
      throw new IdsReAuthExpiredError('二次认证未完成，请重新登录');
    }
    return resolved;
  }

  private static toJson(text: string): object {
    try {
      return JSON.parse(text) as object;
    } catch (e) {
      throw new IdsProtocolError('统一认证返回了非 JSON 响应');
    }
  }
}

interface ChangeTypeJson {
  code?: string | number;
  message?: string;
  data?: ChangeTypeData;
}

interface ChangeTypeData {
  reAuthUserNameInput?: string;
}
