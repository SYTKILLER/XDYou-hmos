import { LibrarySession } from '../../service/library/LibrarySession';
import { BookInfo, BookLocation } from '../../model/library/LibraryModels';
import { Log } from '../../utils/Log';

/**
 * 图书详情页（对应 Dart book_detail_card / book_place_card）。
 * 展示检索结果行中的书目信息 + 封面 + 馆藏地点列表（circAttr/processType=="在架" 计可借）。
 * 参数：检索页传入的 BookInfo 对象。
 */
@Component
export struct BookDetailPage {
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @State book: BookInfo | null = null;
  @State locations: BookLocation[] = [];
  @State loadingLocations: boolean = false;
  @State loadError: string = '';
  @State descExpanded: boolean = false;

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private loadData(book: BookInfo): void {
    this.loadingLocations = true;
    this.loadError = '';
    const coverTask: Promise<void> = LibrarySession.bookCover(book.bookName, book.isbn ?? '', book.docNumber)
      .then((url: string): void => {
        if (url.length > 0 && this.book !== null) {
          this.book.imageUrl = url;
        }
      });
    const locationTask: Promise<void> = LibrarySession.bookLocations(book.docNumber)
      .then((list: BookLocation[]): void => {
        this.locations = list;
        this.loadingLocations = false;
      });
    Promise.all([coverTask, locationTask]).catch((e: Object): void => {
      this.loadingLocations = false;
      this.loadError = e instanceof Error ? e.message : `${e}`;
      Log.warn(`book detail load failed: ${e}`);
    });
  }

  private availableText(book: BookInfo): string {
    const available: number | null = book.availableCount;
    const storage: number | null = book.storageCount;
    const onShelf: number = this.locations.filter((l: BookLocation): boolean =>
      l.processType === '在架' || l.circAttr === '在架').length;
    const availableCount: number | null = available !== null ? available : (this.locations.length > 0 ? onShelf : null);
    const storageCount: number | null = storage !== null ? storage : (this.locations.length > 0 ? this.locations.length : null);
    if (availableCount === null && storageCount === null) {
      return '';
    }
    return `可借 ${availableCount ?? '—'} · 馆藏 ${storageCount ?? '—'}`;
  }

  @Builder
  InfoLine(label: string, value: string) {
    if (value.length > 0) {
      Row({ space: 12 }) {
        Text(label)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(64)
        Text(value)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 12 }) {
          if (this.book !== null) {
            Column({ space: 10 }) {
              Row({ space: 14 }) {
                if (this.book.imageUrl.length > 0) {
                  Image(this.book.imageUrl)
                    .width(84)
                    .height(116)
                    .borderRadius(8)
                    .objectFit(ImageFit.Cover)
                }
                Column({ space: 6 }) {
                  Text(this.book.bookName)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.availableText(this.book).length > 0) {
                    Text(this.availableText(this.book))
                      .fontSize(13)
                      .fontColor(this.themePrimary)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)

              Divider()
                .color($r('app.color.divider'))
                .width('100%')

              this.InfoLine('责任者', this.book.author ?? '')
              this.InfoLine('出版社', this.book.publisherHouse ?? '')
              this.InfoLine('出版年', this.book.publishYear ?? '')
              this.InfoLine('标准号', this.book.isbn ?? '')
              this.InfoLine('索书号', this.book.searchCodeStr())

              if (this.book.description !== null && this.book.description.length > 0) {
                Text(this.book.description)
                  .fontSize(13)
                  .lineHeight(19)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(this.descExpanded ? 40 : 4)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .onClick(() => {
                    this.descExpanded = !this.descExpanded;
                  })
              }
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor($r('app.color.app_card'))
            .alignItems(HorizontalAlign.Start)

            Text(`馆藏地点（${this.locations.length}）`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            if (this.loadingLocations) {
              Row({ space: 10 }) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color(this.themePrimary)
                Text('正在获取馆藏地点…')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .padding(16)
              .borderRadius(14)
              .backgroundColor($r('app.color.app_card'))
            } else if (this.loadError.length > 0) {
              Text(`馆藏信息获取失败：${this.loadError}`)
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.app_card'))
            } else if (this.locations.length === 0) {
              Text('暂无馆藏地点信息')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding(16)
                .borderRadius(14)
                .backgroundColor($r('app.color.app_card'))
            } else {
              ForEach(this.locations, (loc: BookLocation, index: number) => {
                Column({ space: 4 }) {
                  Row({ space: 8 }) {
                    Text(loc.locationName ?? '未知馆藏地')
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .layoutWeight(1)
                    Text(loc.processType.length > 0 ? loc.processType : (loc.circAttr.length > 0 ? loc.circAttr : '—'))
                      .fontSize(12)
                      .fontColor(loc.processType === '在架' || loc.circAttr === '在架'
                        ? this.themePrimary : $r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  Text(`${loc.searchCode}${loc.barCode !== null ? ' · 条码 ' + loc.barCode : ''}${loc.campus !== null ? ' · ' + loc.campus : ''}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .padding(12)
                .borderRadius(12)
                .backgroundColor($r('app.color.app_card'))
                .alignItems(HorizontalAlign.Start)
              }, (loc: BookLocation, index: number) => `${loc.itemId}-${index}`)
            }
          }
        }
        .width('100%')
      }
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('图书详情')
    .backgroundColor($r('app.color.app_bg'))
    .onReady((ctx: NavDestinationContext) => {
      const raw: Object | null = ctx.pathInfo.param as Object | null;
      if (raw !== null && raw instanceof BookInfo) {
        this.book = raw;
        this.loadData(raw);
      } else {
        this.toast('图书参数无效');
      }
    })
  }
}
