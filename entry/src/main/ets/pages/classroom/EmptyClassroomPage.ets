import { SemesterController } from '../../controller/SemesterController';
import { EmptyClassroomSession } from '../../service/classroom/EmptyClassroomSession';
import { EmptyClassroomData, EmptyClassroomPlace } from '../../model/classroom/EmptyClassroomData';
import { PreferenceService } from '../../service/preference/PreferenceService';
import { Log } from '../../utils/Log';

/**
 * 空闲教室查询页（对应 Dart empty_classroom_window/search_window）。
 * 楼栋 Select（记忆上次选择）+ 默认今天日期 + 教室名过滤 + 11 节 4+4+3 方格（实心=有课）。
 * 复用主 IDS 登录态，无独立平台账号。
 */
@Component
export struct EmptyClassroomPage {
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @State buildings: EmptyClassroomPlace[] = [];
  @State selectedBuilding: number = -1;
  @State dateStr: string = '';
  @State rooms: EmptyClassroomData[] = [];
  @State filterText: string = '';
  @State busy: boolean = false;
  @State buildingBusy: boolean = false;
  @State errorMsg: string = '';

  aboutToAppear(): void {
    this.dateStr = EmptyClassroomPage.formatDate(new Date());
    this.initBuildings();
  }

  private static formatDate(d: Date): string {
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private buildingOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    this.buildings.forEach((b: EmptyClassroomPlace): void => {
      options.push({ value: b.name });
    });
    return options;
  }

  /** Select 按钮文本：selected 只定菜单高亮，按钮文字必须 value 提供（项目约定）。 */
  private buildingLabel(): string {
    if (this.selectedBuilding >= 0 && this.selectedBuilding < this.buildings.length) {
      return this.buildings[this.selectedBuilding].name;
    }
    return '请选择教学楼';
  }

  private semesterCode(): string {
    return SemesterController.currentSemester();
  }

  private initBuildings(): void {
    if (this.buildingBusy) {
      return;
    }
    this.buildingBusy = true;
    this.errorMsg = '';
    (async (): Promise<void> => {
      await SemesterController.ensureSemester();
      const list: EmptyClassroomPlace[] = await EmptyClassroomSession.getBuildingList();
      this.buildings = list;
      this.buildingBusy = false;
      const last: string = PreferenceService.getString('emptyClassroomLastChoice', '');
      let idx: number = -1;
      if (last.length > 0) {
        idx = list.findIndex((b: EmptyClassroomPlace): boolean => b.code === last);
      }
      if (idx < 0 && list.length > 0) {
        idx = 0;
      }
      this.selectedBuilding = idx;
      if (idx >= 0) {
        this.query();
      }
    })().catch((e: Object): void => {
      this.buildingBusy = false;
      this.errorMsg = e instanceof Error ? e.message : `${e}`;
      Log.warn(`emptyClassroom initBuildings failed: ${e}`);
    });
  }

  private query(): void {
    if (this.selectedBuilding < 0 || this.selectedBuilding >= this.buildings.length) {
      return;
    }
    if (this.semesterCode().length === 0) {
      this.errorMsg = '学期信息尚未同步，请稍后重试';
      return;
    }
    const building: EmptyClassroomPlace = this.buildings[this.selectedBuilding];
    PreferenceService.putString('emptyClassroomLastChoice', building.code);
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.errorMsg = '';
    EmptyClassroomSession.searchData(building.code, this.dateStr, this.semesterCode())
      .then((list: EmptyClassroomData[]): void => {
        this.rooms = list;
        this.busy = false;
      })
      .catch((e: Object): void => {
        this.busy = false;
        this.errorMsg = e instanceof Error ? e.message : `${e}`;
        Log.warn(`emptyClassroom query failed: ${e}`);
      });
  }

  private pickDate(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2020-1-1'),
      end: new Date('2030-12-31'),
      selected: new Date(this.dateStr),
      lunar: false,
      onDateAccept: (value: Date): void => {
        this.dateStr = EmptyClassroomPage.formatDate(value);
        this.query();
      }
    });
  }

  private filteredRooms(): EmptyClassroomData[] {
    const keyword: string = this.filterText.trim();
    if (keyword.length === 0) {
      return this.rooms;
    }
    return this.rooms.filter((r: EmptyClassroomData): boolean => r.name.includes(keyword));
  }

  @Builder
  CellMark(used: boolean) {
    Column()
      .width(14)
      .height(14)
      .borderRadius(4)
      .backgroundColor(used ? this.themePrimary : $r('app.color.app_bg'))
      .border({ width: 1, color: used ? this.themePrimary : $r('app.color.divider') })
  }

  @Builder
  PeriodCells(data: EmptyClassroomData) {
    Row({ space: 5 }) {
      Row({ space: 5 }) {
        ForEach([0, 1, 2, 3], (i: number) => {
          this.CellMark(data.isUsed[i])
        }, (i: number) => `${i}`)
      }
      Row({ space: 5 }) {
        ForEach([4, 5, 6, 7], (i: number) => {
          this.CellMark(data.isUsed[i])
        }, (i: number) => `${i}`)
      }
      Row({ space: 5 }) {
        ForEach([8, 9, 10], (i: number) => {
          this.CellMark(data.isUsed[i])
        }, (i: number) => `${i}`)
      }
    }
  }

  @Builder
  RoomCell(room: EmptyClassroomData) {
    Column({ space: 8 }) {
      Text(room.nameLines()[0] ?? '')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 10 }) {
        Text(room.nameLines().length > 1 ? room.nameLines()[1] : '')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        this.PeriodCells(room)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.app_card'))
  }

  build() {
    NavDestination() {
      Column() {
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            Text('教学楼')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Select(this.buildingOptions())
              .selected(this.selectedBuilding)
              .value(this.buildingLabel())
              .font({ size: 14 })
              .layoutWeight(1)
              .onSelect((index: number): void => {
                this.selectedBuilding = index;
                this.query();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: 12 }) {
            Text('日期')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Text(this.dateStr)
              .fontSize(14)
              .fontColor(this.themePrimary)
              .layoutWeight(1)
            Text('选择日期')
              .fontSize(13)
              .fontColor(this.themePrimary)
              .onClick(() => this.pickDate())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          TextInput({ text: this.filterText, placeholder: '按教室名过滤（如 A101）' })
            .height(44)
            .borderRadius(12)
            .fontSize(14)
            .width('100%')
            .onChange((value: string) => {
              this.filterText = value;
            })

          Row({ space: 16 }) {
            Row({ space: 6 }) {
              this.CellMark(true)
              Text('有课')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(VerticalAlign.Center)
            Row({ space: 6 }) {
              this.CellMark(false)
              Text('空闲')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(VerticalAlign.Center)
            Blank()
            Button('查询')
              .height(36)
              .borderRadius(10)
              .fontSize(14)
              .backgroundColor(this.themePrimary)
              .onClick(() => this.query())
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))

        if (this.buildingBusy || (this.busy && this.rooms.length === 0)) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.themePrimary)
            Text(this.buildingBusy ? '正在获取教学楼列表…' : '正在查询空闲教室…')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorMsg.length > 0 && this.rooms.length === 0) {
          Column({ space: 16 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(44)
              .fontColor([$r('app.color.error')])
            Text(this.errorMsg)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
            Button('重试')
              .height(44)
              .borderRadius(12)
              .fontSize(15)
              .backgroundColor(this.themePrimary)
              .onClick(() => this.initBuildings())
          }
          .width('100%')
          .padding({ left: 32, right: 32 })
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              if (this.busy) {
                Text('正在刷新…')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              if (this.filteredRooms().length === 0) {
                Text('该条件下暂无教室数据')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 48 })
              }
              ForEach(this.filteredRooms(), (room: EmptyClassroomData, index: number) => {
                this.RoomCell(room)
              }, (room: EmptyClassroomData, index: number) => `${index}-${room.name}`)
            }
            .width('100%')
          }
          .scrollable(ScrollDirection.Vertical)
          .edgeEffect(EdgeEffect.Spring)
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('空闲教室')
    .backgroundColor($r('app.color.app_bg'))
  }
}
