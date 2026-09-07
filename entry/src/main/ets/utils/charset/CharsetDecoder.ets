import { util } from '@kit.ArkTS';

/**
 * 字符集解码封装。官方 TextDecoder 支持 utf-8 / gbk / gb18030 / big5 等。
 * 对应 Dart 端 charset_converter（体育等旧系统页面为 GBK 编码）。
 */
export class CharsetDecoder {
  static readonly UTF8: string = 'utf-8';
  static readonly GBK: string = 'gbk';
  static readonly GB18030: string = 'gb18030';
  static readonly BIG5: string = 'big5';

  static decodeToString(data: ArrayBuffer, encoding: string): string {
    const bytes: Uint8Array = new Uint8Array(data);
    const decoder: util.TextDecoder = util.TextDecoder.create(encoding);
    return decoder.decodeToString(bytes);
  }

  static decodeUtf8(data: ArrayBuffer): string {
    return CharsetDecoder.decodeToString(data, CharsetDecoder.UTF8);
  }

  static decodeGbk(data: ArrayBuffer): string {
    return CharsetDecoder.decodeToString(data, CharsetDecoder.GBK);
  }

  static utf8Bytes(text: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encode(text);
  }
}
