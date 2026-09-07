import { UrlUtil } from '../../utils/net/UrlUtil';
import { Log } from '../../utils/Log';

/**
 * IDS 二次认证协议解析与错误类型（对应 Dart ids_auth_protocol.dart）。
 */

export class IdsProtocolError extends Error {
}

export const REAUTH_PATH: string = '/authserver/reAuthCheck/reAuthLoginView.do';

/**
 * 判断 URL 是否为短信二次认证挑战页（对应 Dart isIDSReAuthLocation）。
 */
export function isReAuthLocation(targetUrl: string): boolean {
  return UrlUtil.schemeOf(targetUrl) === 'https:'
    && UrlUtil.hostOf(targetUrl) === 'ids.xidian.edu.cn'
    && UrlUtil.pathOf(targetUrl) === REAUTH_PATH;
}

export class IdsReAuthRequiredError extends Error {
  constructor() {
    super('登录需要短信二次认证，请打开应用后重试');
  }
}

export class IdsReAuthCodeRejectedError extends Error {
}

export class IdsReAuthExpiredError extends Error {
}

export class IdsReAuthCancelledError extends Error {
  constructor() {
    super('已取消短信二次认证');
  }
}

export class CaptchaSolveFailedError extends Error {
}

/**
 * 短信下发结果（对应 Dart IDSSmsDelivery）。
 */
export class IdsSmsDelivery {
  message: string = '验证码已发送';
  maskedMobile: string = '';
  retryAfterSeconds: number = 0;
  wasAlreadySent: boolean = false;
}

export function maskPhoneNumber(value: string): string {
  if (value.length < 7) {
    return '****';
  }
  return `${value.substring(0, 3)}****${value.substring(value.length - 4)}`;
}

interface SmsDeliveryJson {
  res?: string;
  codeTime?: string | number;
  mobile?: string;
  returnMessage?: string;
}

/**
 * 解析发短信响应（对应 Dart parseIDSSmsDelivery）。
 * res=success 或 code_time_fail（已发送）均放行，其余抛协议异常。
 */
export function parseSmsDelivery(jsonText: string): IdsSmsDelivery {
  let json: SmsDeliveryJson;
  try {
    json = JSON.parse(jsonText) as SmsDeliveryJson;
  } catch (e) {
    throw new IdsProtocolError('统一认证返回了非 JSON 响应');
  }
  const result: string = json.res !== undefined ? json.res : '';
  if (result !== 'success' && result !== 'code_time_fail') {
    throw new IdsProtocolError(json.returnMessage !== undefined ? json.returnMessage : '短信验证码发送失败');
  }
  const rawSeconds: number = typeof json.codeTime === 'number' ? json.codeTime
    : Number.parseInt(json.codeTime !== undefined ? json.codeTime : '', 10);
  const seconds: number = Number.isNaN(rawSeconds) || rawSeconds < 0 ? 0 : rawSeconds;
  const delivery: IdsSmsDelivery = new IdsSmsDelivery();
  delivery.message = json.returnMessage !== undefined ? json.returnMessage : '验证码已发送';
  delivery.maskedMobile = json.mobile !== undefined && json.mobile.length > 0
    ? maskPhoneNumber(json.mobile) : '';
  delivery.retryAfterSeconds = seconds;
  delivery.wasAlreadySent = result === 'code_time_fail';
  Log.info(`sms delivery: ${result}, retry after ${seconds}s`);
  return delivery;
}

const REAUTH_SUCCESS: string = 'reAuth_success';
const REAUTH_FAILED: string = 'reAuth_failed';
const REAUTH_UNAUTHORIZED: string = 'reAuth_unauthorized';

/**
 * 解析提交验证码响应（对应 Dart parseIDSReAuthSubmit）。
 * 返回 message；failed 抛拒绝、unauthorized 抛过期、未知 code 抛协议异常。
 */
export function parseReAuthSubmit(jsonText: string): string {
  let json: ReAuthSubmitJson;
  try {
    json = JSON.parse(jsonText) as ReAuthSubmitJson;
  } catch (e) {
    throw new IdsProtocolError('统一认证返回了非 JSON 响应');
  }
  const code: string = json.code !== undefined ? json.code.toString() : '';
  const message: string = json.msg !== undefined ? json.msg : '二次认证失败';
  if (code === REAUTH_SUCCESS) {
    return message;
  }
  if (code === REAUTH_FAILED) {
    throw new IdsReAuthCodeRejectedError(message);
  }
  if (code === REAUTH_UNAUTHORIZED) {
    throw new IdsReAuthExpiredError(message);
  }
  throw new IdsProtocolError('统一认证返回了未知的二次认证状态');
}

interface ReAuthSubmitJson {
  code?: string | number;
  msg?: string;
}
