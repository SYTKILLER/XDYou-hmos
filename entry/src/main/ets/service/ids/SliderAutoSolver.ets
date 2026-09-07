import { RgbaImage } from '../../utils/codec/PixelBuffer';

/**
 * 滑块轨迹点（对应 Dart TrackPoint）。
 */
export class TrackPoint {
  a: number; // x 位移
  b: number; // y 位移
  c: number; // 毫秒时间

  constructor(a: number, b: number, c: number) {
    this.a = a;
    this.b = b;
    this.c = c;
  }
}

export const SLIDER_PUZZLE_WIDTH: number = 280;
export const SLIDER_PUZZLE_HEIGHT: number = 155;
export const SLIDER_PIECE_WIDTH: number = 44;
export const SLIDER_PIECE_HEIGHT: number = 155;

/**
 * 求解结果：offset 为 piece 左边缘位移/谜题宽度的比例，ncc 为匹配置信度（0~1）。
 */
export class SolveResult {
  offset: number = 0;
  ncc: number = 0;
}

/**
 * 滑块自动求解器（移植 Dart SliderCaptchaClientProvider.solveOffset / generateTracks）。
 * 服务端判定为 |moveLength − X| < 0.5（实测 2026-09-06），人工拖动命中概率低，
 * 自动求解用 NCC 算出精确位置后按邻域穷举。
 */
export class SliderAutoSolver {
  private static readonly GEN_TRACKS_NORM: number = 1.0 / (1.0 + Math.exp(-7.0 * (1.0 - 0.42)));

  /**
   * NCC 峰值相对服务端期望 X 存在逐张变化的偏差（实测 2026-09-06：0 ~ +4px+，
   * 与验证码生成时内容摆放偏移有关），穷举窗口必须覆盖 -6..+10，按命中概率排序。
   */
  static readonly DELTAS: number[] = [2, 3, 1, 4, 0, 5, 6, -1, 7, -2, 8, -3, 9, -4, 10, -5, -6];

  /**
   * NCC 模板匹配求解缺口位置：返回匹配结果，null 表示求解失败。
   */
  static solveOffset(puzzle: RgbaImage, piece: RgbaImage): SolveResult | null {
    const border: number = 24;
    let xL: number = piece.width, yT: number = piece.height, xR: number = 0, yB: number = 0;
    for (let y = 0; y < piece.height; y++) {
      for (let x = 0; x < piece.width; x++) {
        if (piece.alphaAt(x, y) >= 200) {
          if (x < xL) { xL = x; }
          if (y < yT) { yT = y; }
          if (x > xR) { xR = x; }
          if (y > yB) { yB = y; }
        }
      }
    }
    if (xL > xR || yT > yB) {
      return null;
    }
    xL += border;
    yT += border;
    xR -= border;
    yB -= border;
    if (xR < xL || yB < yT) {
      return null;
    }
    const windowWidth: number = xR - xL + 1;
    const windowHeight: number = yB - yT + 1;
    const bigWidth: number = puzzle.width - piece.width + windowWidth;
    if (bigWidth <= windowWidth) {
      return null;
    }
    let templateSum = 0;
    for (let y = 0; y < windowHeight; y++) {
      for (let x = 0; x < windowWidth; x++) {
        templateSum += piece.luminanceAt(xL + x, yT + y);
      }
    }
    const templateMean: number = templateSum / (windowWidth * windowHeight);
    const template = new Float64Array(windowWidth * windowHeight);
    let ti = 0;
    let templateSqSum = 0;
    for (let y = 0; y < windowHeight; y++) {
      for (let x = 0; x < windowWidth; x++) {
        const v = piece.luminanceAt(xL + x, yT + y) - templateMean;
        template[ti] = v;
        templateSqSum += v * v;
        ti++;
      }
    }
    const columnSums = new Float64Array(bigWidth);
    for (let x = 0; x < bigWidth; x++) {
      let s = 0;
      for (let y = 0; y < windowHeight; y++) {
        s += puzzle.luminanceAt(x + xL, yT + y);
      }
      columnSums[x] = s;
    }
    let windowSum = 0;
    for (let x = 0; x < windowWidth; x++) {
      windowSum += columnSums[x];
    }
    const area: number = windowWidth * windowHeight;
    let nccMax = -2, xMax = 0;
    for (let x = 0; x < bigWidth - windowWidth; x++) {
      if (x > 0) {
        windowSum += columnSums[x + windowWidth - 1] - columnSums[x - 1];
      }
      const meanW: number = windowSum / area;
      let sumWt = 0, sumWw = 0.000001;
      ti = 0;
      for (let wy = 0; wy < windowHeight; wy++) {
        const rowBase = (yT + wy) * puzzle.width + x + xL;
        for (let wx = 0; wx < windowWidth; wx++) {
          const w = puzzle.luminanceByIndex(rowBase + wx) - meanW;
          sumWt += w * template[ti];
          sumWw += w * w;
          ti++;
        }
      }
      const ncc: number = sumWt / Math.sqrt(sumWw * templateSqSum);
      if (ncc > nccMax) {
        nccMax = ncc;
        xMax = x;
      }
    }
    const result = new SolveResult();
    result.offset = xMax / puzzle.width;
    result.ncc = nccMax;
    return result;
  }

  /**
   * 沿偏移 S 形曲线生成拟人滑动轨迹（对应 Dart generateTracks）。
   */
  static generateTracks(offs: number): TrackPoint[] {
    const tracks: TrackPoint[] = [new TrackPoint(0, 0, 0)];
    const n: number = Math.floor(Math.random() * 5) + 10;
    let b = 0;
    for (let i = 0; i < n; i++) {
      const z: number = (1.0 / (1.0 + Math.exp(-7.0 * ((i / n) - 0.42)))) / SliderAutoSolver.GEN_TRACKS_NORM;
      const prevA: number = tracks[tracks.length - 1].a;
      const a: number = Math.min(offs - 1, Math.max(prevA + 1, Math.round(offs * z)));
      const r: number = Math.random();
      b = r < 0.65 ? b - 1 : (r < 0.80 ? b + 1 : b);
      b = Math.max(-10, Math.min(10, b));
      tracks.push(new TrackPoint(a, b, Math.floor(Math.random() * 201) + 300));
    }
    tracks.push(new TrackPoint(offs, b, Math.floor(Math.random() * 201) + 300));
    return tracks;
  }
}
