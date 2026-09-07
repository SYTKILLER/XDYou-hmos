/**
 * 宿舍水机数据模型（对应 Dart model/dorm_water.dart）。
 * DormWaterDevice：收藏设备（id/name），fromJson 取 json['id']/json['name']。
 */

export interface FavosItemJson {
  id?: string | number;
  name?: string;
}

export class DormWaterDevice {
  readonly id: string;
  readonly name: string;

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

export function dormWaterDeviceFromJson(json: FavosItemJson): DormWaterDevice {
  const id: string | number | undefined = json.id;
  return new DormWaterDevice(id === undefined || id === null ? '' : `${id}`, json.name ?? '');
}

/** 图片验证码（sessionId 客户端自生成，imageBase64 为原始二进制转 base64，不带 data: 前缀）。 */
export class DormWaterCaptchaData {
  readonly sessionId: string;
  readonly imageBase64: string;

  constructor(sessionId: string, imageBase64: string) {
    this.sessionId = sessionId;
    this.imageBase64 = imageBase64;
  }
}
