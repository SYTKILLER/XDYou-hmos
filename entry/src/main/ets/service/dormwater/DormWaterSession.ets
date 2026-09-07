import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { DormWaterCaptchaData, DormWaterDevice, dormWaterDeviceFromJson, FavosItemJson } from '../../model/dormwater/DormWaterData';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状 ----

interface AlData {
  token?: string;
  uid?: string | number;
  eid?: string | number;
}

interface LoginRespData {
  al?: AlData;
}

interface LoginResp {
  code?: number;
  msg?: string;
  data?: LoginRespData;
}

interface SimpleResp {
  code?: number;
  msg?: string;
}

interface MasterAccount {
  account?: string | null;
}

interface MasterRespData {
  account?: MasterAccount | string | null;
  favos?: FavosItemJson[];
}

interface MasterResp {
  code?: number;
  msg?: string;
  data?: MasterRespData;
}

interface DeviceGene {
  status?: number;
}

interface DeviceInfo {
  gene?: DeviceGene;
}

interface StatusRespData {
  device?: DeviceInfo;
}

interface StatusResp {
  code?: number;
  msg?: string;
  data?: StatusRespData;
}

const API_BASE: string = 'https://i.ilife798.com';
/** 验证码接口 UA（对齐 Dart iOS 分支） */
const UA_CAPTCHA: string = 'iLife798/3.1.1 (iPhone; iOS 26.2; Scale/3.00)';
/** 其余接口 UA */
const UA_NORMAL: string = 'iOS_ilife798_3.1.1';

/**
 * 宿舍水机会话（对应 Dart repository/miscellaneous_session/dorm_water_session.dart）。
 * 慧798/iLife798 平台：手机号 + 图片验证码 + 短信验证码登录，与 IDS 无关。
 * token/uid/eid 持久化于偏好（dormWaterToken/dormWaterUid/dormWaterEid/dormWaterPhone），
 * 后续请求以裸 token 作 Authorization 头；data.account == null 视为登录过期。
 */
export class DormWaterSession {
  /** 业务响应统一 {code,msg,data}，code==0 成功；失败抛出服务端 msg。 */
  private static checkCode(resp: SessionResponse, what: string): void {
    if (resp.statusCode !== 200) {
      throw new Error(`${what}失败（HTTP ${resp.statusCode}）`);
    }
    const parsed: SimpleResp = JSON.parse(resp.bodyText) as SimpleResp;
    if (parsed.code !== 0) {
      throw new Error(parsed.msg !== undefined && parsed.msg.length > 0 ? parsed.msg : `${what}失败`);
    }
  }

  private static token(): string {
    return PreferenceService.getString('dormWaterToken', '');
  }

  private static session(): NetworkSession {
    return SessionManager.get('dormWater');
  }

  private static options(extra: Map<string, string> | null): SessionOptions {
    const opts: SessionOptions = new SessionOptions();
    opts.headers.set('user-agent', UA_NORMAL);
    opts.headers.set('accept', '*/*');
    if (extra !== null) {
      extra.forEach((value: string, key: string): void => {
        opts.headers.set(key, value);
      });
    }
    return opts;
  }

  private static authedOptions(): SessionOptions {
    const extra: Map<string, string> = new Map();
    extra.set('Authorization', DormWaterSession.token());
    return DormWaterSession.options(extra);
  }

  private static randomDigits(length: number): string {
    let out: string = '';
    for (let i = 0; i < length; i++) {
      out += `${Math.floor(Math.random() * 10)}`;
    }
    return out;
  }

  /** 图片验证码：sessionId 为客户端自生成的 16 位数字串（非服务端下发）。 */
  static async getCaptcha(): Promise<DormWaterCaptchaData> {
    const sessionId: string = DormWaterSession.randomDigits(16);
    const timestamp: number = Date.now();
    const opts: SessionOptions = new SessionOptions();
    opts.headers.set('user-agent', UA_CAPTCHA);
    opts.headers.set('accept', '*/*');
    const resp: SessionResponse = await DormWaterSession.session()
      .get(`${API_BASE}/api/v1/captcha/?s=${sessionId}&r=${timestamp}`, opts);
    if (resp.statusCode !== 200 || resp.bodyBytes === null) {
      throw new Error(`获取图片验证码失败（HTTP ${resp.statusCode}）`);
    }
    const imageBase64: string = CryptoUtil.base64Encode(new Uint8Array(resp.bodyBytes));
    return new DormWaterCaptchaData(sessionId, imageBase64);
  }

  /** 发送短信验证码（需要先取图片验证码拿 sessionId）。 */
  static async sendSmsCode(sessionId: string, imageCode: string, phoneNumber: string): Promise<void> {
    const body: string = JSON.stringify({ s: sessionId, authCode: imageCode, un: phoneNumber });
    const opts: SessionOptions = DormWaterSession.options(null);
    const resp: SessionResponse = await DormWaterSession.session()
      .postRaw(`${API_BASE}/api/v1/acc/login/code`, 'application/json', body, opts);
    DormWaterSession.checkCode(resp, '发送验证码');
  }

  /** 短信验证码登录：成功后持久化 token/uid/eid（账号=手机号）。 */
  static async login(phoneNumber: string, smsCode: string): Promise<void> {
    const body: string = JSON.stringify({ cid: '', authCode: smsCode, un: phoneNumber });
    const opts: SessionOptions = DormWaterSession.options(null);
    const resp: SessionResponse = await DormWaterSession.session()
      .postRaw(`${API_BASE}/api/v1/acc/login`, 'application/json', body, opts);
    if (resp.statusCode !== 200) {
      throw new Error(`登录失败（HTTP ${resp.statusCode}）`);
    }
    const parsed: LoginResp = JSON.parse(resp.bodyText) as LoginResp;
    if (parsed.code !== 0 || parsed.data === undefined || parsed.data.al === undefined) {
      throw new Error(parsed.msg !== undefined && parsed.msg.length > 0 ? parsed.msg : '登录失败');
    }
    const al: AlData = parsed.data.al;
    if (al.token === undefined || al.token.length === 0) {
      throw new Error('登录失败：响应缺少 token');
    }
    PreferenceService.putString('dormWaterToken', al.token);
    PreferenceService.putString('dormWaterUid', al.uid === undefined ? '' : `${al.uid}`);
    PreferenceService.putString('dormWaterEid', al.eid === undefined ? '' : `${al.eid}`);
    PreferenceService.putString('dormWaterPhone', phoneNumber);
  }

  /** 退出登录：清除 token 三件套与手机号（对应 Dart remove 三个键）。 */
  static logout(): void {
    PreferenceService.remove('dormWaterToken');
    PreferenceService.remove('dormWaterUid');
    PreferenceService.remove('dormWaterEid');
    PreferenceService.remove('dormWaterPhone');
  }

  static isLoggedIn(): boolean {
    return DormWaterSession.token().length > 0;
  }

  /** 收藏设备列表；data.account == null 判定为登录过期。 */
  static async getDeviceList(): Promise<DormWaterDevice[]> {
    const resp: SessionResponse = await DormWaterSession.session()
      .get(`${API_BASE}/api/v1/ui/app/master`, DormWaterSession.authedOptions());
    if (resp.statusCode !== 200) {
      throw new Error(`获取设备列表失败（HTTP ${resp.statusCode}）`);
    }
    const parsed: MasterResp = JSON.parse(resp.bodyText) as MasterResp;
    if (parsed.code !== 0) {
      throw new Error(parsed.msg !== undefined && parsed.msg.length > 0 ? parsed.msg : '获取设备列表失败');
    }
    const data: MasterRespData | undefined = parsed.data;
    if (data === undefined || data.account === undefined || data.account === null
      || (typeof data.account === 'string' && data.account.length === 0)) {
      throw new Error('登录已过期，请重新登录');
    }
    const favos: FavosItemJson[] = data.favos !== undefined ? data.favos : [];
    const list: DormWaterDevice[] = [];
    favos.forEach((j: FavosItemJson): void => {
      list.push(dormWaterDeviceFromJson(j));
    });
    return list;
  }

  /** 收藏/取消收藏（扫码添加设备也走此接口）。 */
  static async toggleFavorite(deviceId: string, remove: boolean): Promise<void> {
    const url: string = `${API_BASE}/api/v1/dev/favo?did=${encodeURIComponent(deviceId)}&remove=${remove ? 'true' : 'false'}`;
    const resp: SessionResponse = await DormWaterSession.session().get(url, DormWaterSession.authedOptions());
    DormWaterSession.checkCode(resp, remove ? '移除设备' : '添加设备');
  }

  /** 开始出水（pip=21 饮水模式，对齐 Dart 固定参数）。 */
  static async startWater(deviceId: string): Promise<void> {
    const url: string = `${API_BASE}/api/v1/dev/start?args=&cnt=1&did=${encodeURIComponent(deviceId)}&pip=21&rcp=0&upgrade=1`;
    const resp: SessionResponse = await DormWaterSession.session().get(url, DormWaterSession.authedOptions());
    DormWaterSession.checkCode(resp, '开始出水');
  }

  static async endWater(deviceId: string): Promise<void> {
    const url: string = `${API_BASE}/api/v1/dev/end?did=${encodeURIComponent(deviceId)}`;
    const resp: SessionResponse = await DormWaterSession.session().get(url, DormWaterSession.authedOptions());
    DormWaterSession.checkCode(resp, '结束出水');
  }

  /** 设备状态（99 = 空闲）。 */
  static async checkDeviceStatus(deviceId: string): Promise<number> {
    const url: string = `${API_BASE}/api/v1/ui/app/dev/status?did=${encodeURIComponent(deviceId)}&more=true&promo=false`;
    const resp: SessionResponse = await DormWaterSession.session().get(url, DormWaterSession.authedOptions());
    if (resp.statusCode !== 200) {
      throw new Error(`查询设备状态失败（HTTP ${resp.statusCode}）`);
    }
    const parsed: StatusResp = JSON.parse(resp.bodyText) as StatusResp;
    if (parsed.code !== 0 || parsed.data === undefined || parsed.data.device === undefined
      || parsed.data.device.gene === undefined || parsed.data.device.gene.status === undefined) {
      throw new Error(parsed.msg !== undefined && parsed.msg.length > 0 ? parsed.msg : '查询设备状态失败');
    }
    return parsed.data.device.gene.status;
  }
}
