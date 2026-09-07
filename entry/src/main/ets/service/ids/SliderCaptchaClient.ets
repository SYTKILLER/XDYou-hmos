import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { ImageCodec, RgbaImage } from '../../utils/codec/PixelBuffer';
import { IdsCrypto } from './IdsCrypto';
import { CaptchaSolveFailedError } from './IdsAuthProtocol';
import { SliderAutoSolver, SolveResult, TrackPoint, SLIDER_PUZZLE_WIDTH } from './SliderAutoSolver';
import { NetworkSession, SessionOptions, SessionResponse } from '../network/NetworkSession';
import { SessionManager } from '../SessionManager';
import { Log } from '../../utils/Log';

interface SliderCaptchaData {
  bigImage: string;
  smallImage: string;
}

interface SliderVerifyResult {
  errorCode?: number;
}

interface TrackPointPayload {
  a: number;
  b: number;
  c: number;
}

interface VerifyPayload {
  canvasLength: number;
  moveLength: number;
  tracks: TrackPointPayload[];
}

/**
 * 滑块验证码客户端（对应 Dart SliderCaptchaClientProvider）。
 * Dart 原实现使用全新 Dio（无 CookieManager）：每次请求只带登录会话 Cookie 串快照，
 * 不携带 openSliderCaptcha 响应新下发的 Set-Cookie。此处用独立 'slider' 会话并在每次
 * 请求前清空容器以保持同一行为。
 *
 * 服务端判定（2026-09-06 实测）：|moveLength − X| < 0.5（X 为缺口期望位置），
 * 人工拖动几乎无法稳定命中 → 默认先走自动求解（NCC + 邻域穷举），失败才降级人工滑块。
 */
export class SliderCaptchaClient {
  private cookie: string;
  puzzleBase64: string = '';
  pieceBase64: string = '';
  private puzzleImage: RgbaImage | null = null;
  private pieceImage: RgbaImage | null = null;
  private aesKey: Uint8Array = new Uint8Array(0);

  constructor(cookie: string) {
    this.cookie = cookie;
  }

  private freshSession(): NetworkSession {
    const session: NetworkSession = SessionManager.get('slider');
    session.cookies.clear();
    return session;
  }

  /**
   * 拉取并解析验证码图组，提取 AES key（smallImage 解码后末 16 字节）。
   */
  async updatePuzzle(): Promise<void> {
    const session: NetworkSession = this.freshSession();
    const options: SessionOptions = new SessionOptions();
    options.headers.set('cookie', this.cookie);
    const response: SessionResponse = await session.get(
      `https://ids.xidian.edu.cn/authserver/common/openSliderCaptcha.htl?_=${Date.now()}`, options);
    if (response.statusCode !== 200 || response.bodyText.length === 0) {
      throw new Error(`滑块验证码拉取失败（${response.statusCode}）`);
    }
    const data: SliderCaptchaData = JSON.parse(response.bodyText) as SliderCaptchaData;
    this.puzzleBase64 = data.bigImage;
    this.pieceBase64 = data.smallImage;
    this.puzzleImage = await ImageCodec.decodeFromBase64(this.puzzleBase64);
    this.pieceImage = await ImageCodec.decodeFromBase64(this.pieceBase64);
    const pieceBytes: Uint8Array = CryptoUtil.base64Decode(this.pieceBase64);
    if (pieceBytes.length < 16) {
      throw new Error('滑块验证码数据异常');
    }
    this.aesKey = pieceBytes.slice(pieceBytes.length - 16);
    const cookieNames: string[] = [];
    this.cookie.split('; ').forEach((segment: string) => {
      const eq = segment.indexOf('=');
      cookieNames.push(eq > 0 ? `${segment.substring(0, eq)}(${segment.length - eq - 1})` : segment.substring(0, 12));
    });
    Log.info(`Slider captcha fetched, cookieLen=${this.cookie.length}, cookies=${cookieNames.join(',')}`);
    Log.info(`slider cookie raw: ${this.cookie}`);
  }

  /**
   * 完整求解：先自动（6 轮 × ±1/2/3/4 邻域穷举），失败降级人工滑块页。
   * 对应 Dart solve(manualSolver:...)。
   */
  async solveWithAuto(manual: () => Promise<boolean>): Promise<void> {
    for (let round = 0; round < 4; round++) {
      await this.updatePuzzle();
      if (this.puzzleImage === null || this.pieceImage === null) {
        continue;
      }
      const solve: SolveResult | null = SliderAutoSolver.solveOffset(this.puzzleImage, this.pieceImage);
      if (solve === null) {
        Log.warn(`slider auto round ${round}: offset null`);
        continue;
      }
      const baseMove: number = Math.round(solve.offset * SLIDER_PUZZLE_WIDTH);
      Log.info(`slider auto round ${round}: offset=${solve.offset.toFixed(4)} ncc=${solve.ncc.toFixed(3)} baseMove=${baseMove}`);
      const deltas: number[] = SliderAutoSolver.DELTAS;
      for (let di = 0; di < deltas.length; di++) {
        const move: number = baseMove + deltas[di];
        if (move < 0 || move > SLIDER_PUZZLE_WIDTH) {
          continue;
        }
        const tracks: TrackPoint[] = SliderAutoSolver.generateTracks(move);
        const waitMs: number = tracks[tracks.length - 1].c - 100;
        if (waitMs > 0) {
          await SliderCaptchaClient.sleep(waitMs);
        }
        try {
          const ok: boolean = await this.verify(tracks);
          if (ok) {
            Log.info(`slider auto solved at round=${round} baseMove${deltas[di] >= 0 ? '+' : ''}${deltas[di]}`);
            return;
          }
        } catch (e) {
          Log.warn(`slider auto verify error: ${e}`);
        }
      }
    }
    Log.info('slider auto exhausted, fallback to manual');
    const ok: boolean = await manual();
    if (!ok) {
      throw new CaptchaSolveFailedError('验证码校验失败');
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  /**
   * 在当前已拉取的验证码上做 NCC+邻域穷举（人工页复用同一套求解能力）。
   * 服务端容差 |m−X|<0.5 加上人工页 ~0.47px 的系统性显示偏差，裸人工提交几乎必败。
   */
  async verifySweepFromCurrent(): Promise<boolean> {
    if (this.puzzleImage === null || this.pieceImage === null) {
      return false;
    }
    const solve: SolveResult | null = SliderAutoSolver.solveOffset(this.puzzleImage, this.pieceImage);
    if (solve === null) {
      return false;
    }
    const baseMove: number = Math.round(solve.offset * SLIDER_PUZZLE_WIDTH);
    Log.info(`slider manual sweep: offset=${solve.offset.toFixed(4)} ncc=${solve.ncc.toFixed(3)} baseMove=${baseMove}`);
    const deltas: number[] = SliderAutoSolver.DELTAS;
    for (let di = 0; di < deltas.length; di++) {
      const move: number = baseMove + deltas[di];
      if (move < 0 || move > SLIDER_PUZZLE_WIDTH) {
        continue;
      }
      const tracks: TrackPoint[] = SliderAutoSolver.generateTracks(move);
      const waitMs: number = tracks[tracks.length - 1].c - 100;
      if (waitMs > 0) {
        await SliderCaptchaClient.sleep(waitMs);
      }
      try {
        const ok: boolean = await this.verify(tracks);
        if (ok) {
          Log.info(`slider manual solved at ${move}`);
          return true;
        }
      } catch (e) {
        Log.warn(`slider manual verify error: ${e}`);
      }
    }
    return false;
  }

  /**
   * sign 路径提交（Dart 原版策略）。
   */
  async verify(tracks: TrackPoint[]): Promise<boolean> {
    const trackPayloads: TrackPointPayload[] = [];
    for (let i = 0; i < tracks.length; i++) {
      trackPayloads.push({ a: tracks[i].a, b: tracks[i].b, c: tracks[i].c });
    }
    const payload: VerifyPayload = {
      canvasLength: SLIDER_PUZZLE_WIDTH,
      moveLength: tracks.length > 0 ? tracks[tracks.length - 1].a : 0,
      tracks: trackPayloads
    };
    const payloadJson: string = JSON.stringify(payload);
    Log.info(`slider payload: canvasLength=${payload.canvasLength}, moveLength=${payload.moveLength}, points=${trackPayloads.length}`);
    const sign: string = await IdsCrypto.encryptSliderPayload(payloadJson, this.aesKey);
    return this.postVerifyBody(`sign=${encodeURIComponent(sign)}`, 'sign');
  }

  private async postVerifyBody(body: string, tag: string): Promise<boolean> {
    const session: NetworkSession = this.freshSession();
    const options: SessionOptions = new SessionOptions();
    options.hasBody = true;
    options.body = body;
    options.contentType = 'application/x-www-form-urlencoded;charset=UTF-8';
    options.headers.set('cookie', this.cookie);
    options.headers.set('accept', 'application/json, text/javascript, */*; q=0.01');
    options.headers.set('origin', 'https://ids.xidian.edu.cn');
    options.headers.set('access-control-allow-origin', 'https://ids.xidian.edu.cn');
    options.headers.set('x-requested-with', 'XMLHttpRequest');
    const response: SessionResponse = await session.postRaw(
      'https://ids.xidian.edu.cn/authserver/common/verifySliderCaptcha.htl',
      'application/x-www-form-urlencoded;charset=UTF-8', options.body, options);
    Log.info(`slider verify(${tag}) resp: status=${response.statusCode}, body=${response.bodyText.substring(0, 120)}`);
    const result: SliderVerifyResult = JSON.parse(response.bodyText) as SliderVerifyResult;
    return result.errorCode === 1;
  }
}
