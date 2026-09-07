import { AppNav } from '../nav/AppNav';

/**
 * 登录流程 ↔ 滑块验证码页面 的桥接（对应 Dart manualSolver 回调）：
 * 服务层 solve(cookie) → 拉起 sliderCaptcha 页面 → 用户完成/取消 → resolve 结果。
 */
export class CaptchaCoordinator {
  private static pendingCookie: string = '';
  private static resolver: ((ok: boolean) => void) | null = null;

  static pendingCookieValue(): string {
    return CaptchaCoordinator.pendingCookie;
  }

  static solve(cookieStr: string): Promise<boolean> {
    CaptchaCoordinator.pendingCookie = cookieStr;
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      CaptchaCoordinator.resolver = resolve;
      const stack: NavPathStack | null = AppNav.stackOrNull();
      if (stack === null) {
        resolve(false);
        return;
      }
      stack.pushPathByName('sliderCaptcha', null);
    });
  }

  static finish(ok: boolean): void {
    if (CaptchaCoordinator.resolver !== null) {
      CaptchaCoordinator.resolver(ok);
      CaptchaCoordinator.resolver = null;
    }
  }
}
