import { image } from '@kit.ImageKit';
import { Log } from '../Log';

/**
 * 成绩图片像素哈希（对应 Dart image_recognition.dart _calculatePixelFNV1A）：
 * 解码图片 → 取左上 50×20 区域内 alpha==255 的像素 RGB 字节（RGBA/BGRA 自动适配）→ FNV-1a 32 位。
 * 哈希与 lib/generated/score_hashes.g.dart 的常量表精确匹配（非 OCR）。
 */
export class ImageHasher {
  static async fnv1aPixelHash(bytes: Uint8Array): Promise<number> {
    const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const imageSource: image.ImageSource = image.createImageSource(buffer);
    const pixelMap: image.PixelMap = await imageSource.createPixelMap();
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = Math.min(info.size.width, 50);
    const height: number = Math.min(info.size.height, 20);
    if (width <= 0 || height <= 0) {
      throw new Error('score image has empty size');
    }

    const rowCount: number = info.size.width * 4;
    const dst: ArrayBuffer = new ArrayBuffer(rowCount * info.size.height);
    await pixelMap.readPixelsToBuffer(dst);
    const pixels: Uint8Array = new Uint8Array(dst);

    // 解码格式默认 RGBA_8888；BGRA_8888 时 R/B 字节序互换。
    const isBgra: boolean = info.pixelFormat === image.PixelMapFormat.BGRA_8888;
    const pixelBytes: number[] = [];
    for (let y: number = 0; y < height; y++) {
      for (let x: number = 0; x < width; x++) {
        const base: number = y * rowCount + x * 4;
        const a: number = pixels[base + 3];
        if (a !== 255) {
          // 透明像素跳过（与 Dart 端一致，减少计算量）。
          continue;
        }
        const r: number = isBgra ? pixels[base + 2] : pixels[base];
        const g: number = pixels[base + 1];
        const b: number = isBgra ? pixels[base] : pixels[base + 2];
        pixelBytes.push(r, g, b);
      }
    }
    pixelMap.release().catch((e: Object): void => {
      Log.warn(`ImageHasher pixelMap release: ${e}`);
    });
    imageSource.release().catch((e: Object): void => {
      Log.warn(`ImageHasher imageSource release: ${e}`);
    });

    let hash: number = 0x811C9DC5;
    for (const p of pixelBytes) {
      hash ^= p;
      // 32 位 FNV 素数乘法（Math.imul 保持 32 位语义后转无符号）。
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash >>> 0;
  }
}
