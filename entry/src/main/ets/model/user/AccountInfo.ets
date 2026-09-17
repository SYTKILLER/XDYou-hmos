/**
 * 用户账号信息模型（无 Dart 对应，移植新增）：来自「学在西电」门户 /xidianapp/wap/mine/index，
 * 供设置页账号区展示真实姓名与头像。
 * JSON 形状按 mine 页前端 chunk 反编译确认（user.realname / user.role.number / user.avatar）；
 * 头像为门户图床相对路径（siteInfo.imgUrl=imgapp.xidian.edu.cn，图床公网可直连）。
 */

/** mine/index 响应内 user.role 的形状（number = 学号/工号）。 */
export interface MineRoleJson {
  number?: string;
}

/** mine/index 响应内 d.user 的形状。 */
export interface MineUserJson {
  realname?: string;
  avatar?: string;
  role?: MineRoleJson;
}

/** 磁盘缓存 JSON 形状（cacheDir/UserAccount.json）。 */
export interface AccountInfoJson {
  realName?: string;
  number?: string;
  avatarUrl?: string;
  fetchTime?: number;
}

export class AccountInfo {
  readonly realName: string;
  readonly number: string;
  readonly avatarUrl: string;
  readonly fetchTime: number;

  constructor(realName: string, number: string, avatarUrl: string, fetchTime: number) {
    this.realName = realName;
    this.number = number;
    this.avatarUrl = avatarUrl;
    this.fetchTime = fetchTime;
  }

  /** 头像相对路径解析：绝对 URL 直接用；其余拼门户图床（siteInfo.imgUrl）。空串原样返回。 */
  static resolveAvatarUrl(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    const base: string = 'https://imgapp.xidian.edu.cn/';
    return raw.startsWith('/') ? base.substring(0, base.length - 1) + raw : base + raw;
  }

  static fromMine(user: MineUserJson): AccountInfo {
    const realName: string = user.realname !== undefined ? user.realname : '';
    const number: string = user.role !== undefined && user.role.number !== undefined ? user.role.number : '';
    const avatar: string = user.avatar !== undefined ? user.avatar : '';
    return new AccountInfo(realName, number, AccountInfo.resolveAvatarUrl(avatar), Date.now());
  }

  toCacheJson(): AccountInfoJson {
    return {
      realName: this.realName,
      number: this.number,
      avatarUrl: this.avatarUrl,
      fetchTime: this.fetchTime
    };
  }

  static fromCacheJson(p: AccountInfoJson): AccountInfo {
    return new AccountInfo(
      p.realName !== undefined ? p.realName : '',
      p.number !== undefined ? p.number : '',
      p.avatarUrl !== undefined ? p.avatarUrl : '',
      p.fetchTime !== undefined ? p.fetchTime : 0
    );
  }
}
