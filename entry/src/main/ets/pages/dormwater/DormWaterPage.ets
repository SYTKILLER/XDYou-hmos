import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DormWaterSession } from '../../service/dormwater/DormWaterSession';
import { DormWaterController } from '../../controller/DormWaterController';
import { DormWaterDevice } from '../../model/dormwater/DormWaterData';
import { AppNav } from '../../service/nav/AppNav';
import { Log } from '../../utils/Log';

/**
 * 宿舍水机设备页（对应 Dart dorm_water_window 设备分支）。
 * 收藏设备列表 + 扫码添加（Scan Kit startScanForResult，预授权无需相机权限，
 * 二维码格式 https://i.hnkzy.com/q/1/{did}）+ 开始/结束出水（1s×60 轮询，连续 3 次 status==99 判空闲）。
 * 未登录时不保留任何登录入口，直接拉起 dormWaterLogin 登录页。
 */
@Component
export struct DormWaterPage {
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @StorageProp('dormWaterVersion') version: number = 0;
  @State busy: boolean = false;
  @State busyAction: string = '';
  @State runningDeviceId: string = '';
  private idleCount: number = 0;

  private devices(): DormWaterDevice[] {
    return DormWaterController.data();
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  aboutToAppear(): void {
    if (!DormWaterSession.isLoggedIn()) {
      const stack: NavPathStack | null = AppNav.stackOrNull();
      if (stack !== null) {
        stack.pushPath({ name: 'dormWaterLogin' });
      }
      return;
    }
    this.reload();
  }

  /** busy 翻转是渲染依赖（NOTICE 2026-09-07 教训）：完成时重渲染并重读控制器 getter。 */
  private reload(): void {
    this.busy = true;
    DormWaterController.refreshDevices().then((): void => {
      this.busy = false;
    }).catch((e: Object): void => {
      this.busy = false;
      Log.warn(`dormWater reload failed: ${e}`);
    });
  }

  private stopRunning(): void {
    this.runningDeviceId = '';
    this.idleCount = 0;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  private startWater(device: DormWaterDevice): void {
    this.getUIContext().showAlertDialog({
      title: '开始出水',
      message: `确认让「${device.name}」开始出水？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '开始',
        action: () => {
          this.busyAction = device.id;
          DormWaterSession.startWater(device.id).then((): void => {
            this.busyAction = '';
            this.runningDeviceId = device.id;
            this.idleCount = 0;
            this.toast('已开始出水');
            this.pollDeviceStatus(device.id);
          }).catch((e: Object): void => {
            this.busyAction = '';
            this.toast(e instanceof Error ? e.message : '开始出水失败');
          });
        }
      }
    });
  }

  /** 轮询设备状态：最多 60 次（1 秒间隔），连续 3 次 99 视为空闲（防网络抖动）。 */
  private async pollDeviceStatus(deviceId: string): Promise<void> {
    const maxAttempts: number = 60;
    const requiredIdleCount: number = 3;
    let attempts: number = 0;
    while (attempts < maxAttempts && this.runningDeviceId === deviceId) {
      await this.sleep(1000);
      if (this.runningDeviceId !== deviceId) {
        return;
      }
      try {
        const status: number = await DormWaterSession.checkDeviceStatus(deviceId);
        if (status === 99) {
          this.idleCount++;
          if (this.idleCount >= requiredIdleCount) {
            this.stopRunning();
            this.toast('设备已恢复空闲');
            return;
          }
        } else {
          this.idleCount = 0;
        }
      } catch (e) {
        this.idleCount = 0;
      }
      attempts++;
    }
    if (this.runningDeviceId === deviceId) {
      this.stopRunning();
      this.toast('设备状态查询超时');
    }
  }

  private endWater(deviceId: string): void {
    this.busyAction = deviceId;
    DormWaterSession.endWater(deviceId).then((): void => {
      this.busyAction = '';
      this.stopRunning();
      this.toast('已结束出水');
    }).catch((e: Object): void => {
      this.busyAction = '';
      this.toast(e instanceof Error ? e.message : '结束出水失败');
    });
  }

  private removeDevice(device: DormWaterDevice): void {
    this.getUIContext().showAlertDialog({
      title: '移除设备',
      message: `确认移除收藏设备「${device.name}」？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '移除',
        fontColor: $r('app.color.error'),
        action: () => {
          this.busyAction = device.id;
          DormWaterSession.toggleFavorite(device.id, true).then((): void => {
            this.busyAction = '';
            DormWaterController.removeLocal(device.id);
            this.toast('设备已移除收藏');
          }).catch((e: Object): void => {
            this.busyAction = '';
            this.toast(e instanceof Error ? e.message : '移除设备失败');
          });
        }
      }
    });
  }

  /** 扫码添加设备：校验 hnkzy.com 链接，取路径末段为设备 id。 */
  private scanQrCode(): void {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const options: scanBarcode.ScanOptions = { scanTypes: [scanCore.ScanType.QR_CODE] };
    scanBarcode.startScanForResult(context, options).then((result: scanBarcode.ScanResult): void => {
      const text: string = result.originalValue;
      if (text.length === 0) {
        return;
      }
      if (!text.includes('hnkzy.com')) {
        this.toast('不是有效的水机二维码');
        return;
      }
      let deviceId: string = text;
      const parts: string[] = text.split('/').filter((p: string): boolean => p.length > 0);
      if (parts.length > 0) {
        deviceId = parts[parts.length - 1];
      }
      this.busyAction = deviceId;
      DormWaterSession.toggleFavorite(deviceId, false).then((): void => {
        this.busyAction = '';
        this.toast('设备已添加');
        this.reload();
      }).catch((e: Object): void => {
        this.busyAction = '';
        this.toast(e instanceof Error ? e.message : '添加设备失败');
      });
    }).catch((e: BusinessError): void => {
      // 1000500002 = 用户取消扫码，静默即可。
      if (e.code !== 1000500002) {
        Log.warn(`dormWater scan failed: ${e.message}`);
        this.toast('扫码失败，请重试');
      }
    });
  }

  @Builder
  DeviceCell(device: DormWaterDevice) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(device.name.length > 0 ? device.name : '未命名设备')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`ID: ${device.id}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(20)
        .fontColor([$r('app.color.text_secondary')])
        .onClick(() => this.removeDevice(device))

      SymbolGlyph(this.runningDeviceId === device.id ? $r('sys.symbol.stop_circle_fill') : $r('sys.symbol.play_fill'))
        .fontSize(24)
        .fontColor([this.runningDeviceId === device.id ? $r('app.color.error') : this.themePrimary])
        .onClick(() => {
          if (this.busyAction.length > 0) {
            return;
          }
          if (this.runningDeviceId === device.id) {
            this.endWater(device.id);
          } else {
            this.startWater(device);
          }
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(VerticalAlign.Center)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.busy && !DormWaterController.hasData()) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.themePrimary)
            Text('正在获取设备列表…')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (DormWaterController.error().length > 0 && !DormWaterController.hasData()) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(44)
              .fontColor([$r('app.color.error')])
            Text(DormWaterController.error())
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
            Button('重新加载')
              .height(44)
              .borderRadius(12)
              .fontSize(15)
              .backgroundColor(this.themePrimary)
              .fontColor(this.themeOnPrimary)
              .onClick(() => this.reload())
          }
          .width('100%')
          .padding({ left: 32, right: 32 })
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (!DormWaterController.hasData()) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.cup_fill'))
              .fontSize(44)
              .fontColor([$r('app.color.text_secondary')])
            Text('暂无收藏设备，点击右上角扫码添加')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Button('刷新列表')
              .height(44)
              .borderRadius(12)
              .fontSize(15)
              .backgroundColor(this.themePrimary)
              .fontColor(this.themeOnPrimary)
              .onClick(() => this.reload())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            if (this.busy) {
              Text('正在刷新…')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ bottom: 4 })
            }
            Refresh({ refreshing: false }) {
              Scroll() {
                Column({ space: 12 }) {
                  ForEach(this.devices(), (device: DormWaterDevice) => {
                    this.DeviceCell(device)
                  }, (device: DormWaterDevice) => device.id)
                }
                .width('100%')
              }
              .scrollable(ScrollDirection.Vertical)
              .edgeEffect(EdgeEffect.Spring)
              .width('100%')
            }
            .onRefreshing(() => this.reload())
            .layoutWeight(1)
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('宿舍水机')
    .backgroundColor($r('app.color.app_bg'))
    .menus([
      {
        value: '扫码添加设备',
        icon: 'sys.symbol.qrcode',
        action: () => this.scanQrCode()
      }
    ])
    .onShown(() => {
      if (DormWaterSession.isLoggedIn()) {
        this.reload();
      }
    })
  }
}
