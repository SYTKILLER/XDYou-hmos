import { CryptoUtil } from '../../utils/crypto/CryptoUtil';
import { PreferenceService } from '../preference/PreferenceService';
import { Log } from '../../utils/Log';

/**
 * IDS 相关加密与浏览器指纹（对应 Dart ids_session.aesEncrypt + network_client.aesEncrypt + ids_fingerprint）。
 * 输出必须与 Dart 端逐字节一致——已由设备单测对拍固定向量。
 */
export class IdsCrypto {
  private static readonly IDS_FIXED_PREFIX: string =
    'xidianscriptsxduxidianscriptsxduxidianscriptsxduxidianscriptsxdu';
  private static readonly IDS_FIXED_IV: string = 'xidianscriptsxdu';
  private static readonly AES_CHARS: string = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  /**
   * IDS 密码加密：固定前缀 + 手动 PKCS7 + AES128-CBC（NoPadding）+ 固定 IV → Base64。
   * 对应 Dart IDSSession.aesEncrypt（libxduauth 变体）。
   */
  static async encryptIdsPassword(toEnc: string, key: string): Promise<string> {
    const plainBytes: Uint8Array =
      CryptoUtil.utf8Bytes(`${IdsCrypto.IDS_FIXED_PREFIX}${toEnc}`);
    const padded: Uint8Array = CryptoUtil.pkcs7Pad(plainBytes);
    const cipher: Uint8Array = await CryptoUtil.aesCbcEncryptNoPadding(
      CryptoUtil.utf8Bytes(key), CryptoUtil.utf8Bytes(IdsCrypto.IDS_FIXED_IV), padded);
    return CryptoUtil.base64Encode(cipher);
  }

  private static randomAesChar(): string {
    const index: number = Math.floor(Math.random() * IdsCrypto.AES_CHARS.length);
    return IdsCrypto.AES_CHARS.charAt(index);
  }

  /**
   * 滑块验证码 payload 加密：随机 64B nonce 前缀 + 随机 16B IV + AES-CBC PKCS7 → Base64。
   * 对应 Dart network_client.aesEncrypt。
   */
  static async encryptSliderPayload(text: string, keyBytes: Uint8Array): Promise<string> {
    let randstr: string = '';
    for (let i = 0; i < 80; i++) {
      randstr += IdsCrypto.randomAesChar();
    }
    const plain: string = randstr.substring(0, 64) + text;
    const iv: Uint8Array = CryptoUtil.utf8Bytes(randstr.substring(64, 80));
    const cipher: Uint8Array =
      await CryptoUtil.aesCbcEncryptPkcs7(keyBytes, iv, CryptoUtil.utf8Bytes(plain));
    return CryptoUtil.base64Encode(cipher);
  }

  /**
   * IDS 信任设备浏览器指纹：32 位大写十六进制（16 随机字节），独立于 Cookie 持久化。
   */
  static getOrCreateBrowserFingerprint(): string {
    const stored: string = PreferenceService.getString('idsBrowserFingerprint', '');
    if (/^[0-9A-F]{32}$/.test(stored)) {
      return stored;
    }
    let hex: string = '';
    for (let i = 0; i < 16; i++) {
      const value: number = Math.floor(Math.random() * 256);
      hex += value.toString(16).padStart(2, '0').toUpperCase();
    }
    PreferenceService.putString('idsBrowserFingerprint', hex);
    Log.info('IDS browser fingerprint generated');
    return hex;
  }
}
