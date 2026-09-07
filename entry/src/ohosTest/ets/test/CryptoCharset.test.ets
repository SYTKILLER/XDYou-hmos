import { describe, it, expect } from '@ohos/hypium';
import { CryptoUtil } from '../../../main/ets/utils/crypto/CryptoUtil';
import { CharsetDecoder } from '../../../main/ets/utils/charset/CharsetDecoder';

function hexToBytes(hex: string): Uint8Array {
  const out: Uint8Array = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = Number.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return out;
}

export default function cryptoCharsetTest() {
  describe('cryptoCharsetTest', () => {
    it('md5KnownVectors', 0, async () => {
      const abc: string = await CryptoUtil.md5HexOfText('abc');
      expect(abc).assertEqual('900150983cd24fb0d6963f7d28e17f72');
      const fox: string = await CryptoUtil.md5HexOfText('The quick brown fox jumps over the lazy dog');
      expect(fox).assertEqual('9e107d9d372bb6826bd81d3542a419d6');
    });

    it('aesCbcNoPaddingNistVector', 0, async () => {
      const key: Uint8Array = hexToBytes('2b7e151628aed2a6abf7158809cf4f3c');
      const iv: Uint8Array = hexToBytes('000102030405060708090A0B0C0D0E0F');
      const plain: Uint8Array = hexToBytes('6bc1bee22e409f96e93d7e117393172a');
      const cipher: Uint8Array = await CryptoUtil.aesCbcEncryptNoPadding(key, iv, plain);
      expect(CryptoUtil.bytesToHex(cipher)).assertEqual('7649abac8119b246cee98e9b12e9197d');
      const restored: Uint8Array = await CryptoUtil.aesCbcDecryptNoPadding(key, iv, cipher);
      expect(CryptoUtil.bytesToHex(restored)).assertEqual('6bc1bee22e409f96e93d7e117393172a');
    });

    it('aesCbcPkcs7Roundtrip', 0, async () => {
      const key: Uint8Array = CryptoUtil.utf8Bytes('xidianscriptsxdu');
      const iv: Uint8Array = CryptoUtil.utf8Bytes('xidianscriptsxdu');
      const plain: string = 'Hello, XDYou! 我';
      const cipher: Uint8Array = await CryptoUtil.aesCbcEncryptPkcs7(key, iv, CryptoUtil.utf8Bytes(plain));
      const restored: Uint8Array = await CryptoUtil.aesCbcDecryptPkcs7(key, iv, cipher);
      expect(CryptoUtil.bytesToUtf8(restored)).assertEqual(plain);
    });

    it('pkcs7PadManual', 0, () => {
      const padded: Uint8Array = CryptoUtil.pkcs7Pad(CryptoUtil.utf8Bytes('abcd'));
      expect(padded.length).assertEqual(16);
      expect(padded[15]).assertEqual(12);
    });

    it('base64Roundtrip', 0, () => {
      expect(CryptoUtil.base64Encode(CryptoUtil.utf8Bytes('hello'))).assertEqual('aGVsbG8=');
      const decoded: Uint8Array = CryptoUtil.base64Decode('aGVsbG8=');
      expect(CryptoUtil.bytesToUtf8(decoded)).assertEqual('hello');
    });

    it('gbkDecoding', 0, () => {
      const zhongWen: Uint8Array = new Uint8Array([0xD6, 0xD0, 0xCE, 0xC4]);
      expect(CharsetDecoder.decodeGbk(zhongWen.buffer as ArrayBuffer)).assertEqual('中文');
      const xiDian: Uint8Array = CryptoUtil.utf8Bytes('西电');
      expect(xiDian.length).assertEqual(6);
    });

    it('utf8BytesKnownVector', 0, () => {
      const bytes: Uint8Array = CryptoUtil.utf8Bytes('中');
      expect(bytes.length).assertEqual(3);
      expect(bytes[0]).assertEqual(0xE4);
      expect(bytes[1]).assertEqual(0xB8);
      expect(bytes[2]).assertEqual(0xAD);
    });
  });
}
