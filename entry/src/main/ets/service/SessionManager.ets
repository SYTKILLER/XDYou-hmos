import { NetworkSession } from './network/NetworkSession';
import { PreferenceService } from './preference/PreferenceService';
import { Log } from '../utils/Log';

/**
 * 网络会话注册中心（对应 Dart get_it 注册的多个共享 dio 客户端）。
 * Cookie 存储：ids（统一身份认证 + ehall）、schoolnet、sport、general（其余系统）。
 * Cookie 持久化经 PreferenceService 落盘，键名 cookie_<store>。
 */
export class SessionManager {
  private static readonly sessions: Map<string, NetworkSession> = new Map();

  private static prefKey(storeName: string): string {
    return `cookie_${storeName}`;
  }

  static get(storeName: string): NetworkSession {
    const existing: NetworkSession | undefined = SessionManager.sessions.get(storeName);
    if (existing !== undefined) {
      return existing;
    }
    const created: NetworkSession = new NetworkSession(storeName);
    const saved: string = PreferenceService.getString(SessionManager.prefKey(storeName), '');
    if (saved.length > 0) {
      created.cookies.loadFrom(saved);
    }
    SessionManager.sessions.set(storeName, created);
    return created;
  }

  /** 统一身份认证/ehall 会话（CAS Cookie 存储） */
  static ids(): NetworkSession {
    return SessionManager.get('ids');
  }

  /** 无状态/独立系统会话 */
  static general(): NetworkSession {
    return SessionManager.get('general');
  }

  /** 校园网自助服务会话 */
  static schoolnet(): NetworkSession {
    return SessionManager.get('schoolnet');
  }

  /** 体育平台会话（独立登录态） */
  static sport(): NetworkSession {
    return SessionManager.get('sport');
  }

  static save(storeName: string): void {
    const session: NetworkSession | undefined = SessionManager.sessions.get(storeName);
    if (session !== undefined) {
      PreferenceService.putString(SessionManager.prefKey(storeName), session.cookies.serialize());
    }
  }

  static saveAll(): void {
    SessionManager.sessions.forEach((session: NetworkSession, storeName: string) => {
      PreferenceService.putString(SessionManager.prefKey(storeName), session.cookies.serialize());
    });
  }

  static clearStore(storeName: string): void {
    const session: NetworkSession | undefined = SessionManager.sessions.get(storeName);
    if (session !== undefined) {
      session.cookies.clear();
    }
    PreferenceService.remove(SessionManager.prefKey(storeName));
    Log.info(`SessionManager cleared store ${storeName}`);
  }
}
