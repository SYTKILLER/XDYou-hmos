import { SliderCaptchaClient } from '../service/ids/SliderCaptchaClient';
import { TrackPoint, SLIDER_PUZZLE_WIDTH, SLIDER_PUZZLE_HEIGHT,
  SLIDER_PIECE_WIDTH, SLIDER_PIECE_HEIGHT } from '../service/ids/SliderAutoSolver';
import { CaptchaCoordinator } from '../service/ids/CaptchaCoordinator';
import { AppNav } from '../service/nav/AppNav';
import { Log } from '../utils/Log';

const SLIDER_HANDLE_SIZE: number = 42;
const SLIDER_RIGHT_PADDING: number = 40;
const RECORD_INTERVAL_MS: number = 20;
const RECORD_DISTANCE_PX: number = 2;

/**
 * 滑块验证码人工求解页（对应 Dart CaptchaWidget）：
 * 拖动手柄移动拼图块，释放后提交轨迹校验；成功回 resolve，失败刷新重试。
 * 颜色全部走 $r('app.color.*')（base/dark 自动切换）；按钮高 50 / 圆角 12 / 模块间距 24。
 */
@Component
export struct SliderCaptchaPage {
  // 主题响应式 token（AppTheme.syncStorage 维护）。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @State puzzleB64: string = '';
  @State pieceB64: string = '';
  @State loaded: boolean = false;
  @State loadFailed: boolean = false;
  @State sliderLeft: number = 0;
  @State statusText: string = '';
  @State submitting: boolean = false;
  private client: SliderCaptchaClient | null = null;
  private tracks: TrackPoint[] = [];
  private lastRecordMs: number = 0;
  private lastA: number = 0;
  private lastB: number = 0;

  aboutToAppear(): void {
    this.refresh('');
  }

  private async refresh(statusText: string): Promise<void> {
    this.sliderLeft = 0;
    this.tracks = [];
    this.loaded = false;
    this.loadFailed = false;
    this.statusText = statusText;
    this.submitting = false;
    this.client = new SliderCaptchaClient(CaptchaCoordinator.pendingCookieValue());
    try {
      await this.client.updatePuzzle();
      this.puzzleB64 = this.client.puzzleBase64;
      this.pieceB64 = this.client.pieceBase64;
      this.loaded = true;
    } catch (e) {
      Log.warn(`slider captcha refresh failed: ${e}`);
      this.loadFailed = true;
    }
  }

  private dragLimit(): number {
    return SLIDER_PUZZLE_WIDTH - SLIDER_RIGHT_PADDING;
  }

  private async finishDrag(offsetX: number, offsetY: number): Promise<void> {
    if (this.client === null) {
      return;
    }
    const dx: number = Math.round(offsetX);
    const dy: number = Math.round(offsetY);
    if (dx === 0) {
      return;
    }
    this.tracks.push(new TrackPoint(dx, dy, Date.now() - this.lastRecordMs));
    Log.info(`slider finish: dx=${dx}, dy=${dy}, sliderLeft=${Math.round(this.sliderLeft)}, points=${this.tracks.length}`);
    this.submitting = true;
    // 首选：当前验证码上 NCC+邻域穷举（服务端容差 |m−X|<0.5，人工对齐无法稳定命中）
    let verified = false;
    try {
      verified = await this.client.verifySweepFromCurrent();
    } catch (e) {
      Log.warn(`slider manual sweep error: ${e}`);
    }
    // 兜底：NCC 不可用时提交用户原始轨迹
    if (!verified) {
      try {
        verified = await this.client.verify(this.tracks);
      } catch (e) {
        Log.warn(`slider raw verify failed: ${e}`);
      }
    }
    this.submitting = false;
    if (verified) {
      CaptchaCoordinator.finish(true);
      AppNav.stackOrNull()?.pop();
      return;
    }
    this.refresh('再试一次');
  }

  build() {
    NavDestination() {
      Column() {
        if (this.loadFailed) {
          Column() {
            Text($r('app.string.login_captcha_fetch_failed'))
              .fontSize(15)
              .fontColor($r('app.color.error'))
            Button($r('app.string.login_try_again'))
              .margin({ top: 24 })
              .height(50)
              .borderRadius(12)
              .padding({ left: 24, right: 24 })
              .fontSize(16)
              .fontColor(this.themeOnPrimary)
              .backgroundColor(this.themePrimary)
              .onClick(() => {
                this.refresh('');
              })
          }
          .justifyContent(FlexAlign.Center)
          .height('100%')
        } else if (!this.loaded) {
          Column() {
            LoadingProgress().width(48).height(48)
          }
          .justifyContent(FlexAlign.Center)
          .height('100%')
        } else {
          Column() {
            Stack({ alignContent: Alignment.TopStart }) {
              Image(`data:image/png;base64,${this.puzzleB64}`)
                .width(SLIDER_PUZZLE_WIDTH)
                .height(SLIDER_PUZZLE_HEIGHT)
              Image(`data:image/png;base64,${this.pieceB64}`)
                .width(SLIDER_PIECE_WIDTH)
                .height(SLIDER_PIECE_HEIGHT)
                .offset({ x: this.sliderLeft })
            }
            .width(SLIDER_PUZZLE_WIDTH)
            .height(SLIDER_PUZZLE_HEIGHT)

            Stack({ alignContent: Alignment.Start }) {
              Row()
                .width(SLIDER_PUZZLE_WIDTH)
                .height(10)
                .borderRadius(5)
                .backgroundColor($r('app.color.slider_track_rest'))
                .margin({ top: 17 })
              Row()
                .width(Math.max(0, this.sliderLeft + 4))
                .height(10)
                .borderRadius(5)
                .backgroundColor($r('app.color.slider_track_active'))
                .margin({ top: 17 })
              Column() {
                if (this.submitting) {
                  LoadingProgress().width(20).height(20)
                } else {
                  Text('→').fontSize(18).fontColor($r('app.color.slider_track_active'))
                }
              }
              .width(SLIDER_HANDLE_SIZE)
              .height(SLIDER_HANDLE_SIZE)
              .borderRadius(SLIDER_HANDLE_SIZE / 2)
              .backgroundColor($r('app.color.app_card'))
              .justifyContent(FlexAlign.Center)
              .shadow({ radius: 4, color: '#40000000', offsetX: 0, offsetY: 2 })
              .offset({ x: this.sliderLeft - 1, y: 1 })
            }
            .width(SLIDER_PUZZLE_WIDTH)
            .height(44)
            .gesture(
              PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 1 })
                .onActionStart((event: GestureEvent) => {
                  if (this.submitting) {
                    return;
                  }
                  this.tracks = [];
                  this.tracks.push(new TrackPoint(0, 0, 0));
                  this.lastRecordMs = Date.now();
                  this.lastA = 0;
                  this.lastB = 0;
                  this.statusText = '';
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.submitting) {
                    return;
                  }
                  const dx: number = event.offsetX;
                  this.sliderLeft = Math.max(0, Math.min(dx, this.dragLimit()));
                  const now: number = Date.now();
                  const elapsed: number = now - this.lastRecordMs;
                  if (elapsed < RECORD_INTERVAL_MS) {
                    return;
                  }
                  const a: number = Math.round(dx);
                  const b: number = Math.round(event.offsetY);
                  const distSq: number = (a - this.lastA) * (a - this.lastA)
                    + (b - this.lastB) * (b - this.lastB);
                  if (distSq < RECORD_DISTANCE_PX * RECORD_DISTANCE_PX) {
                    return;
                  }
                  this.tracks.push(new TrackPoint(a, b, elapsed));
                  this.lastA = a;
                  this.lastB = b;
                  this.lastRecordMs = now;
                })
                .onActionEnd((event: GestureEvent) => {
                  if (this.submitting) {
                    return;
                  }
                  this.finishDrag(event.offsetX, event.offsetY);
                })
            )

            if (this.statusText !== '') {
              Text(this.statusText)
                .fontSize(14)
                .fontColor($r('app.color.error'))
                .margin({ top: 8 })
            }
          }
          .margin({ top: 24 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_bg'))
    }
    .title($r('app.string.login_slider_title'))
    .onBackPressed(() => {
      CaptchaCoordinator.finish(false);
      return false;
    })
  }
}
