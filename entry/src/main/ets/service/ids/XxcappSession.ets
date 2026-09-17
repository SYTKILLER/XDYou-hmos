import { IdsSession } from './IdsSession';
import { backgroundSliderHandler } from './BackgroundSlider';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { AppContext } from '../AppContext';
import { AccountInfo, AccountInfoJson, MineUserJson } from '../../model/user/AccountInfo';
import { Log } from '../../utils/Log';

interface MineResp {
  e?: number;
  d?: MineUserBox;
}

interface MineUserBox {
  user?: MineUserJson;
}

/**
 * 「学在西电」门户（xxcapp.xidian.edu.cn）用户信息抓取（2026-09-15 新增，无 Dart 对应）。
 * 协议要点（curl 追踪 mine 页前端 chunk + 未登录跳转链确认）：
 * 1. /xidianapp/wap/mine/index 未登录 302 → /uc/wap/login → /a_xidian/api/cas-login/index → CAS；
 * 2. CAS service 必须指向票据校验桥 /a_xidian/api/cas-login/index（SPA 静态页不校验 ticket），
 *    与浏览器登录链逐字节一致；redirect 参数落回 mine/index，followRedirects 终点即登录后的门户；
 * 3. mine/index 返回 {e:0, d:{user:{realname, role:{number}, avatar}, ...}} 纯 JSON；
 * 4. xxcapp 与图床 imgapp.xidian.edu.cn 均公网可达，不依赖校园网（与 ignypt 不同）。
 * 缓存：cacheDir/UserAccount.json 快照，冷启动直读。
 */
export class XxcappSession {
  static readonly CACHE_FILE: string = 'UserAccount.json';
  private static readonly CAS_LOGIN_BRIDGE: string =
    'https://xxcapp.xidian.edu.cn/a_xidian/api/cas-login/index?redirect=' +
    encodeURIComponent('https://xxcapp.xidian.edu.cn/xidianapp/wap/mine/index') + '&from=wap';
  private static readonly MINE_INDEX_URL: string = 'https://xxcapp.xidian.edu.cn/xidianapp/wap/mine/index';

  static async getAccountInfo(): Promise<AccountInfo> {
    const location: string =
      await IdsSession.checkAndLogin(XxcappSession.CAS_LOGIN_BRIDGE, backgroundSliderHandler());
    await IdsSession.followRedirects(location);
    const session: NetworkSession = SessionManager.ids();
    const options: SessionOptions = new SessionOptions();
    // 与门户前端 appFetch（jQuery ajax）一致，避免个别网关对无该头的请求返回 HTML 登录页。
    options.headers.set('X-Requested-With', 'XMLHttpRequest');
    const resp: SessionResponse = await session.get(XxcappSession.MINE_INDEX_URL, options);
    return XxcappSession.parseMineResp(resp.bodyText);
  }

  private static parseMineResp(bodyText: string): AccountInfo {
    let parsed: MineResp;
    try {
      parsed = JSON.parse(bodyText) as MineResp;
    } catch (e) {
      throw new Error(`学在西电用户信息响应非 JSON（登录态可能失效）：${bodyText.substring(0, 64)}`);
    }
    if (parsed.e === undefined || parsed.e !== 0 || parsed.d === undefined
      || parsed.d.user === undefined) {
      throw new Error(`学在西电用户信息接口返回失败：e=${parsed.e !== undefined ? parsed.e : 'undefined'}`);
    }
    return AccountInfo.fromMine(parsed.d.user);
  }

  /** 冷启动直读磁盘快照；不存在/解析失败返回 null。 */
  static getCacheData(): AccountInfo | null {
    const text: string | null = AppContext.readCacheText(XxcappSession.CACHE_FILE);
    if (text === null || text.length === 0) {
      return null;
    }
    try {
      return AccountInfo.fromCacheJson(JSON.parse(text) as AccountInfoJson);
    } catch (e) {
      Log.warn(`xxcapp account cache parse failed: ${e}`);
      return null;
    }
  }
}
