import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { CharsetDecoder } from '../charset/CharsetDecoder';

/**
 * 加密工具封装（cryptoFramework + util.Base64Helper）。
 * 对应 Dart 端 encrypter_plus / pointycastle / crypto。
 * 注意：IDS 密码加密为「手动 PKCS7 + NoPadding」以保证与 Dart 输出逐字节一致。
 * 注意：对称密钥必须 convertKey 注入调用方密钥——generateSymKey() 是"随机生成密钥"，
 * 传入的 key 会被无视（曾致滑块 sign 与登录密码加密全部失效）。
 */
export class CryptoUtil {
  private static readonly BLOCK_SIZE: number = 16;

  static utf8Bytes(text: string): Uint8Array {
    return CharsetDecoder.utf8Bytes(text);
  }

  static bytesToUtf8(data: Uint8Array): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(data);
  }

  static bytesToHex(data: Uint8Array): string {
    const digits: string = '0123456789abcdef';
    let out: string = '';
    for (let i = 0; i < data.length; i++) {
      const b: number = data[i];
      out += digits[(b >>> 4) & 0x0F];
      out += digits[b & 0x0F];
    }
    return out;
  }

  static base64Encode(data: Uint8Array): string {
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.encodeToStringSync(data);
  }

  static base64Decode(text: string): Uint8Array {
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.decodeSync(text);
  }

  /**
   * 手动 PKCS7 填充（与 Dart 端实现一致：填充字节值 = 填充长度）。
   */
  static pkcs7Pad(data: Uint8Array): Uint8Array {
    const padLen: number = CryptoUtil.BLOCK_SIZE - (data.length % CryptoUtil.BLOCK_SIZE);
    const out: Uint8Array = new Uint8Array(data.length + padLen);
    out.set(data, 0);
    for (let i = 0; i < padLen; i++) {
      out[data.length + i] = padLen;
    }
    return out;
  }

  static pkcs7Unpad(data: Uint8Array): Uint8Array {
    if (data.length === 0 || data.length % CryptoUtil.BLOCK_SIZE !== 0) {
      return data;
    }
    const padLen: number = data[data.length - 1];
    if (padLen <= 0 || padLen > CryptoUtil.BLOCK_SIZE || padLen > data.length) {
      return data;
    }
    return data.slice(0, data.length - padLen);
  }

  private static aesAlgName(keyLength: number): string {
    if (keyLength === 16) {
      return 'AES128';
    }
    if (keyLength === 24) {
      return 'AES192';
    }
    return 'AES256';
  }

  /**
   * AES-CBC 加密（NoPadding：输入必须是 16 字节整数倍，配合手动 PKCS7 使用）。
   */
  static async aesCbcEncryptNoPadding(key: Uint8Array, iv: Uint8Array, paddedPlain: Uint8Array): Promise<Uint8Array> {
    const algName: string = `${CryptoUtil.aesAlgName(key.length)}|CBC|NoPadding`;
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(algName);
    const symKeyGenerator: cryptoFramework.SymKeyGenerator =
      cryptoFramework.createSymKeyGenerator(CryptoUtil.aesAlgName(key.length));
    const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey({ data: key });
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, CryptoUtil.makeIvSpec(iv));
    const inputBlob: cryptoFramework.DataBlob = { data: paddedPlain };
    const output: cryptoFramework.DataBlob = await cipher.doFinal(inputBlob);
    return output.data;
  }

  /**
   * AES-CBC 解密（NoPadding）。
   */
  static async aesCbcDecryptNoPadding(key: Uint8Array, iv: Uint8Array, cipherBytes: Uint8Array): Promise<Uint8Array> {
    const algName: string = `${CryptoUtil.aesAlgName(key.length)}|CBC|NoPadding`;
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(algName);
    const symKeyGenerator: cryptoFramework.SymKeyGenerator =
      cryptoFramework.createSymKeyGenerator(CryptoUtil.aesAlgName(key.length));
    const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey({ data: key });
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, CryptoUtil.makeIvSpec(iv));
    const inputBlob: cryptoFramework.DataBlob = { data: cipherBytes };
    const output: cryptoFramework.DataBlob = await cipher.doFinal(inputBlob);
    return output.data;
  }

  /**
   * AES-CBC 加密（框架内置 PKCS7 填充）。
   */
  static async aesCbcEncryptPkcs7(key: Uint8Array, iv: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
    const algName: string = `${CryptoUtil.aesAlgName(key.length)}|CBC|PKCS7`;
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(algName);
    const symKeyGenerator: cryptoFramework.SymKeyGenerator =
      cryptoFramework.createSymKeyGenerator(CryptoUtil.aesAlgName(key.length));
    const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey({ data: key });
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, CryptoUtil.makeIvSpec(iv));
    const inputBlob: cryptoFramework.DataBlob = { data: plain };
    const output: cryptoFramework.DataBlob = await cipher.doFinal(inputBlob);
    return output.data;
  }

  /**
   * AES-CBC 解密（框架内置 PKCS7 填充）。
   */
  static async aesCbcDecryptPkcs7(key: Uint8Array, iv: Uint8Array, cipherBytes: Uint8Array): Promise<Uint8Array> {
    const algName: string = `${CryptoUtil.aesAlgName(key.length)}|CBC|PKCS7`;
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher(algName);
    const symKeyGenerator: cryptoFramework.SymKeyGenerator =
      cryptoFramework.createSymKeyGenerator(CryptoUtil.aesAlgName(key.length));
    const symKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey({ data: key });
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, CryptoUtil.makeIvSpec(iv));
    const inputBlob: cryptoFramework.DataBlob = { data: cipherBytes };
    const output: cryptoFramework.DataBlob = await cipher.doFinal(inputBlob);
    return CryptoUtil.pkcs7Unpad(output.data);
  }

  private static makeIvSpec(iv: Uint8Array): cryptoFramework.IvParamsSpec {
    const spec: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };
    return spec;
  }

  /**
   * MD5 摘要（hex 小写）。对应 Dart crypto 包 md5。
   */
  static async md5Hex(data: Uint8Array): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    const blob: cryptoFramework.DataBlob = { data: data };
    await md.update(blob);
    const digest: cryptoFramework.DataBlob = await md.digest();
    return CryptoUtil.bytesToHex(digest.data);
  }

  static async md5HexOfText(text: string): Promise<string> {
    return CryptoUtil.md5Hex(CryptoUtil.utf8Bytes(text));
  }

  /**
   * 从 DER 编码的 X.509 SubjectPublicKeyInfo 导入 RSA 公钥。
   * 对应 pointycastle 从服务端下发的 modulus/exponent 或 PEM 构造公钥。
   */
  static async importRsaPublicKey(derBytes: Uint8Array, keyBits: number): Promise<cryptoFramework.PubKey> {
    const generator: cryptoFramework.AsyKeyGenerator =
      cryptoFramework.createAsyKeyGenerator(`RSA${keyBits}`);
    const keyPair: cryptoFramework.KeyPair =
      await generator.convertKey({ data: derBytes }, null);
    return keyPair.pubKey;
  }

  /**
   * RSA PKCS1 加密。
   */
  static async rsaEncryptPkcs1(publicKey: cryptoFramework.PubKey, plain: Uint8Array): Promise<Uint8Array> {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('RSA|PKCS1');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, publicKey, null);
    const output: cryptoFramework.DataBlob = await cipher.doFinal({ data: plain });
    return output.data;
  }
}
