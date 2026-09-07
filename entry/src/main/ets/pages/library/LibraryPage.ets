import { LibraryController } from '../../controller/LibraryController';
import { BookInfo, BorrowData, LibrarySearchFilterOptions, LibrarySearchOption } from '../../model/library/LibraryModels';
import { AppNav } from '../../service/nav/AppNav';
import { Log } from '../../utils/Log';

/**
 * 图书馆页（对应 Dart library_window 双页签：我的借阅 + 书目检索）。
 * 借阅需认证链（IDS→超星→OPAC JWT，自动完成，无独立平台账号）；检索不要求登录。
 * 高级检索支持字段组合 + 文献类型/馆藏地/语言/国家/出版年/仅可借全量筛选 + 分页。
 */
@Component
export struct LibraryPage {
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @StorageProp('themeOnPrimary') themeOnPrimary: string = '#FFFFFF';
  @StorageProp('libraryVersion') version: number = 0;
  // 检索状态
  @State searchText: string = '';
  @State fieldIndex: number = 0;
  @State matchModeIndex: number = 1;
  @State advancedOpen: boolean = false;
  @State docTypeIndex: number = 0;
  @State langIndex: number = 0;
  @State countryIndex: number = 0;
  @State locationIndex: number = 0;
  @State onlyOnShelf: boolean = false;
  @State yearBegin: string = '';
  @State yearEnd: string = '';
  @State results: BookInfo[] = [];
  @State page: number = 0;
  @State searching: boolean = false;
  @State searchError: string = '';
  @State searchedOnce: boolean = false;
  @State renewingId: number = -1;
  @State borrowBusy: boolean = false;
  private filterOptions: LibrarySearchFilterOptions = LibrarySearchFilterOptions.fallback();

  aboutToAppear(): void {
    this.loadBorrow();
    LibraryController.getFilterOptions().then((options: LibrarySearchFilterOptions): void => {
      this.filterOptions = options;
    }).catch((e: Object): void => {
      Log.warn(`library filter options failed: ${e}`);
    });
  }

  /** borrowBusy 翻转是渲染依赖（NOTICE 2026-09-07 教训）：完成时重渲染并重读控制器 getter。 */
  private loadBorrow(): void {
    this.borrowBusy = true;
    LibraryController.refreshBorrowList().then((): void => {
      this.borrowBusy = false;
    }).catch((e: Object): void => {
      this.borrowBusy = false;
      Log.warn(`library borrow load failed: ${e}`);
    });
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private optionLabel(options: LibrarySearchOption[], index: number, fallback: string): string {
    if (index >= 0 && index < options.length) {
      return options[index].label;
    }
    return fallback;
  }

  private optionValue(options: LibrarySearchOption[], index: number): string {
    if (index >= 0 && index < options.length) {
      return options[index].value;
    }
    return '';
  }

  private selectOptions(options: LibrarySearchOption[]): SelectOption[] {
    const list: SelectOption[] = [];
    options.forEach((o: LibrarySearchOption): void => {
      list.push({ value: o.label });
    });
    return list;
  }

  // ---- 我的借阅 ----

  private renew(item: BorrowData): void {
    if (this.renewingId >= 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '续借',
      message: `确认续借《${item.title}》？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '续借',
        action: () => {
          this.renewingId = item.loanId;
          LibraryController.renew(item.loanId).then((message: string): void => {
            this.renewingId = -1;
            this.toast(message);
            this.loadBorrow();
          }).catch((e: Object): void => {
            this.renewingId = -1;
            this.toast(e instanceof Error ? e.message : '续借失败');
          });
        }
      }
    });
  }

  @Builder
  BorrowCell(item: BorrowData) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(item.title.length > 0 ? item.title : '未知书名')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.lendDay() < 0) {
          Text(`已逾期 ${-item.lendDay()} 天`)
            .fontSize(12)
            .fontColor($r('app.color.error'))
        } else {
          Text(`剩 ${item.lendDay()} 天`)
            .fontSize(12)
            .fontColor(this.themePrimary)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(`${item.author.length > 0 ? item.author + ' · ' : ''}${item.publisher.length > 0 ? item.publisher + ' · ' : ''}${item.publishYear}`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(`应还日期：${item.normReturnDate}    ${item.locationName.length > 0 ? '馆藏地：' + item.locationName : ''}`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Button(this.renewingId === item.loanId ? '续借中…' : '续借')
        .height(34)
        .borderRadius(10)
        .fontSize(13)
        .backgroundColor(item.lendDay() < 0 ? $r('app.color.app_bg') : this.themePrimary)
        .fontColor(item.lendDay() < 0 ? $r('app.color.text_secondary') : this.themeOnPrimary)
        .enabled(item.lendDay() >= 0 && this.renewingId < 0)
        .opacity(item.lendDay() < 0 ? 0.6 : 1)
        .onClick(() => this.renew(item))
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor($r('app.color.app_card'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  BorrowView() {
    if (this.borrowBusy && LibraryController.borrowData().length === 0) {
      Column({ space: 12 }) {
        LoadingProgress()
          .width(36)
          .height(36)
          .color(this.themePrimary)
        Text('正在加载借阅信息…')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (LibraryController.borrowError().length > 0 && LibraryController.borrowData().length === 0) {
      Column({ space: 16 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(44)
          .fontColor([$r('app.color.error')])
        Text(LibraryController.borrowError())
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        Button('重试')
          .height(44)
          .borderRadius(12)
          .fontSize(15)
          .backgroundColor(this.themePrimary)
          .fontColor(this.themeOnPrimary)
          .onClick(() => this.loadBorrow())
      }
      .width('100%')
      .padding({ left: 32, right: 32 })
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll() {
        Column({ space: 12 }) {
          if (this.borrowBusy) {
            Text('正在刷新…')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          if (LibraryController.borrowData().length === 0) {
            Text('当前没有在借图书')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 64 })
          }
          ForEach(LibraryController.borrowData(), (item: BorrowData) => {
            this.BorrowCell(item)
          }, (item: BorrowData) => `${item.loanId}-${item.normReturnDate}`)
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

  // ---- 书目检索 ----

  private doSearch(loadMore: boolean): void {
    if (this.searching) {
      return;
    }
    const word: string = this.searchText.trim();
    if (!loadMore && word.length === 0) {
      this.toast('请输入检索关键词');
      return;
    }
    const nextPage: number = loadMore ? this.page + 1 : 1;
    this.searching = true;
    this.searchError = '';
    if (!loadMore) {
      this.searchedOnce = true;
    }
    const task: Promise<BookInfo[]> = this.advancedOpen
      ? LibraryController.advancedSearch(word, nextPage,
        this.optionValue(this.filterOptions.searchFields, this.fieldIndex),
        `${this.matchModeIndex + 1}`,
        this.docTypeIndex > 0 ? this.optionValue(this.filterOptions.documentTypes, this.docTypeIndex) : null,
        null,
        this.locationIndex > 0 && this.optionValue(this.filterOptions.locations, this.locationIndex).length > 0
          ? parseInt(this.optionValue(this.filterOptions.locations, this.locationIndex), 10) : null,
        this.countryIndex > 0 ? this.optionValue(this.filterOptions.countries, this.countryIndex) : null,
        this.langIndex > 0 ? this.optionValue(this.filterOptions.languages, this.langIndex) : null,
        this.onlyOnShelf ? true : null,
        this.yearBegin.trim().length > 0 ? this.yearBegin.trim() : null,
        this.yearEnd.trim().length > 0 ? this.yearEnd.trim() : null)
      : LibraryController.search(word, nextPage,
        this.optionValue(this.filterOptions.searchFields, this.fieldIndex));
    task.then((list: BookInfo[]): void => {
      this.searching = false;
      this.page = nextPage;
      this.results = loadMore ? this.results.concat(list) : list;
      if (list.length === 0 && !loadMore) {
        this.results = [];
      }
    }).catch((e: Object): void => {
      this.searching = false;
      this.searchError = e instanceof Error ? e.message : `${e}`;
      Log.warn(`library search failed: ${e}`);
    });
  }

  private openDetail(book: BookInfo): void {
    const stack: NavPathStack | null = AppNav.stackOrNull();
    if (stack === null) {
      return;
    }
    stack.pushPath({ name: 'bookDetail', param: book });
  }

  @Builder
  FilterSelect(label: string, options: LibrarySearchOption[], index: number, fallback: string,
    onPick: (index: number) => void) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(64)
      Select(this.selectOptions(options))
        .selected(index)
        .value(this.optionLabel(options, index, fallback))
        .font({ size: 13 })
        .layoutWeight(1)
        .onSelect((idx: number): void => {
          onPick(idx);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SearchView() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            TextInput({ text: this.searchText, placeholder: '输入检索关键词' })
              .height(44)
              .borderRadius(12)
              .fontSize(14)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.searchText = value;
              })
              .onSubmit((): void => {
                this.doSearch(false);
              })
            Button(this.searching ? '检索中' : '检索')
              .height(44)
              .borderRadius(12)
              .fontSize(14)
              .backgroundColor(this.themePrimary)
              .fontColor(this.themeOnPrimary)
              .onClick(() => this.doSearch(false))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          this.FilterSelect('检索字段', this.filterOptions.searchFields, this.fieldIndex, '任意词',
            (idx: number): void => {
              this.fieldIndex = idx;
            })

          Row({ space: 10 }) {
            Text('匹配方式')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width(64)
            Select([{ value: '精确' }, { value: '模糊' }, { value: '前方一致' }])
              .selected(this.matchModeIndex)
              .value(this.matchModeIndex === 0 ? '精确' : (this.matchModeIndex === 2 ? '前方一致' : '模糊'))
              .font({ size: 13 })
              .layoutWeight(1)
              .onSelect((idx: number): void => {
                this.matchModeIndex = idx;
              })
            Text(this.advancedOpen ? '收起筛选' : '高级筛选')
              .fontSize(13)
              .fontColor(this.themePrimary)
              .onClick(() => {
                this.advancedOpen = !this.advancedOpen;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.advancedOpen) {
            Divider()
              .color($r('app.color.divider'))
              .width('100%')
            this.FilterSelect('文献类型', this.filterOptions.documentTypes, this.docTypeIndex, '全部',
              (idx: number): void => {
                this.docTypeIndex = idx;
              })
            this.FilterSelect('馆藏地', this.filterOptions.locations, this.locationIndex, '全部',
              (idx: number): void => {
                this.locationIndex = idx;
              })
            this.FilterSelect('语言', this.filterOptions.languages, this.langIndex, '全部',
              (idx: number): void => {
                this.langIndex = idx;
              })
            this.FilterSelect('国家', this.filterOptions.countries, this.countryIndex, '全部',
              (idx: number): void => {
                this.countryIndex = idx;
              })
            Row({ space: 10 }) {
              Text('出版年')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width(64)
              TextInput({ text: this.yearBegin, placeholder: '起始年' })
                .type(InputType.Number)
                .height(38)
                .borderRadius(10)
                .fontSize(13)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.yearBegin = value;
                })
              Text('至')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              TextInput({ text: this.yearEnd, placeholder: '结束年' })
                .type(InputType.Number)
                .height(38)
                .borderRadius(10)
                .fontSize(13)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.yearEnd = value;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            Row({ space: 8 }) {
              Toggle({ type: ToggleType.Checkbox, isOn: this.onlyOnShelf })
                .selectedColor(this.themePrimary)
                .onChange((isOn: boolean) => {
                  this.onlyOnShelf = isOn;
                })
              Text('仅显示可借图书')
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding(14)
        .borderRadius(16)
        .backgroundColor($r('app.color.app_card'))

        if (this.searchError.length > 0) {
          Text(`检索失败：${this.searchError}`)
            .fontSize(13)
            .fontColor($r('app.color.error'))
            .width('100%')
        }

        if (this.searchedOnce && !this.searching && this.results.length === 0 && this.searchError.length === 0) {
          Text('未找到相关图书')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 32 })
        }

        ForEach(this.results, (book: BookInfo, index: number) => {
          Column({ space: 6 }) {
            Text(book.bookName.length > 0 ? book.bookName : '未知书名')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${book.author !== null ? book.author : ''}${book.publisherHouse !== null ? ' · ' + book.publisherHouse : ''}${book.publishYear !== null ? ' · ' + book.publishYear : ''}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row({ space: 10 }) {
              Text(`索书号 ${book.searchCodeStr()}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              if (book.availableCount !== null) {
                Text(`可借 ${book.availableCount}`)
                  .fontSize(12)
                  .fontColor(book.availableCount > 0 ? this.themePrimary : $r('app.color.text_secondary'))
              }
              if (book.storageCount !== null) {
                Text(`馆藏 ${book.storageCount}`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor($r('app.color.app_card'))
          .alignItems(HorizontalAlign.Start)
          .onClick(() => this.openDetail(book))
        }, (book: BookInfo, index: number) => `${book.docNumber}-${index}`)

        if (this.results.length > 0 && this.results.length >= this.page * 10) {
          Button(this.searching ? '加载中…' : '加载更多')
            .width('60%')
            .height(42)
            .borderRadius(12)
            .fontSize(14)
            .backgroundColor($r('app.color.app_card'))
            .fontColor(this.themePrimary)
            .enabled(!this.searching)
            .onClick(() => this.doSearch(true))
        }
      }
      .width('100%')
    }
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  build() {
    NavDestination() {
      Column() {
        Tabs() {
          TabContent() {
            this.BorrowView()
          }
          .tabBar(SubTabBarStyle.of('我的借阅'))

          TabContent() {
            this.SearchView()
          }
          .tabBar(SubTabBarStyle.of('书目检索'))
        }
        .barPosition(BarPosition.Start)
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8 })
    }
    .title('图书馆')
    .backgroundColor($r('app.color.app_bg'))
  }
}
