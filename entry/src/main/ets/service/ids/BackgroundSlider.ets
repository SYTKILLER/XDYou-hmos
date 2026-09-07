import { SliderCaptchaHandler } from './SliderCaptchaHandler';
import { SliderCaptchaClient } from './SliderCaptchaClient';

/**
 * 后台静默续登用的滑块处理器：仅自动求解（NCC + 邻域穷举），不弹人工滑块页。
 * 自动失败即抛 CaptchaSolveFailedError，由调用方按"拉取失败"处理并回退缓存——
 * 后台刷新不应打断用户（Dart 侧同样以自动求解作为后台兜底）。
 */
export function backgroundSliderHandler(): SliderCaptchaHandler {
  return (cookie: string): Promise<void> => {
    const client: SliderCaptchaClient = new SliderCaptchaClient(cookie);
    return client.solveWithAuto(async (): Promise<boolean> => false);
  };
}
