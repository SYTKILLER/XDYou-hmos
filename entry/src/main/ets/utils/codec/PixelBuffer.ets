import { image } from '@kit.ImageKit';
import { CryptoUtil } from '../crypto/CryptoUtil';
import { Log } from '../Log';

/**
 * base64 图片 → RGBA 像素缓冲（供滑块自动求解的 NCC 模板匹配使用）。
 * 链路：util.Base64Helper 解码 → image.createImageSource → createPixelMap(RGBA_8888) → readPixelsToBuffer。
 */
export class RgbaImage {
  readonly width: number;
  readonly height: number;
  private readonly pixels: Uint8Array;
  private lum: Float64Array | null = null;

  constructor(width: number, height: number, pixels: Uint8Array) {
    this.width = width;
    this.height = height;
    this.pixels = pixels;
  }

  private luminanceTable(): Float64Array {
    if (this.lum === null) {
      const table = new Float64Array(this.width * this.height);
      for (let i = 0; i < table.length; i++) {
        const p = i * 4;
        table[i] = 0.299 * this.pixels[p] + 0.587 * this.pixels[p + 1] + 0.114 * this.pixels[p + 2];
      }
      this.lum = table;
    }
    return this.lum;
  }

  luminanceAt(x: number, y: number): number {
    return this.luminanceTable()[y * this.width + x];
  }

  luminanceByIndex(index: number): number {
    return this.luminanceTable()[index];
  }

  alphaAt(x: number, y: number): number {
    return this.pixels[(y * this.width + x) * 4 + 3];
  }
}

export class ImageCodec {
  static async decodeFromBase64(b64: string): Promise<RgbaImage> {
    const bytes: Uint8Array = CryptoUtil.base64Decode(b64);
    const buf: ArrayBuffer =
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
    const source: image.ImageSource = image.createImageSource(buf);
    const opts: image.DecodingOptions = { desiredPixelFormat: image.PixelMapFormat.RGBA_8888 };
    const pixelMap: image.PixelMap = await source.createPixelMap(opts);
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    const w: number = info.size.width;
    const h: number = info.size.height;
    const dst = new ArrayBuffer(w * h * 4);
    await pixelMap.readPixelsToBuffer(dst);
    await pixelMap.release();
    await source.release();
    Log.info(`ImageCodec decoded ${w}x${h}`);
    return new RgbaImage(w, h, new Uint8Array(dst));
  }
}
