/**
 * 滑块验证码处理回调：输入当前 IDS Cookie 串；成功解决后 resolve，失败 reject。
 * 对应 Dart sliderCaptcha: Future<void> Function(String)。
 */
export type SliderCaptchaHandler = (cookieStr: string) => Promise<void>;
