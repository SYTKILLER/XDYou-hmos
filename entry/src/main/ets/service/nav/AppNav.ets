/**
 * 全局导航栈持有者：服务层（如滑块验证码协调器）通过它拉起页面。
 * NavPathStack 是 ArkUI 全局声明类（component/navigation.d.ts），不可从 @kit.ArkUI 导入。
 */
export class AppNav {
  private static stack: NavPathStack | null = null;

  static init(stack: NavPathStack): void {
    AppNav.stack = stack;
  }

  static stackOrNull(): NavPathStack | null {
    return AppNav.stack;
  }
}
