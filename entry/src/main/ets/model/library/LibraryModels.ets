/**
 * 图书馆数据模型（对应 Dart model/xidian_ids/library.dart）。
 * BorrowData/BookInfo/BookLocation 的 fromOpacJson 字段兼容映射 1:1 对拍原版。
 */

/** 检索选项（value/label/短标签）。 */
export class LibrarySearchOption {
  readonly value: string;
  readonly label: string;
  readonly shortLabel: string;

  constructor(value: string, label: string, shortLabel?: string) {
    this.value = value;
    this.label = label;
    this.shortLabel = shortLabel !== undefined ? shortLabel : label;
  }
}

function yearOptions(): LibrarySearchOption[] {
  const options: LibrarySearchOption[] = [new LibrarySearchOption('', '全部')];
  const currentYear: number = new Date().getFullYear();
  for (let year: number = currentYear; year >= 1950; year--) {
    options.push(new LibrarySearchOption(`${year}`, `${year}`));
  }
  return options;
}

/** 检索筛选项全集；网络拉取失败时使用 fallback 常量。 */
export class LibrarySearchFilterOptions {
  readonly searchFields: LibrarySearchOption[];
  readonly documentTypes: LibrarySearchOption[];
  readonly resourceTypes: LibrarySearchOption[];
  readonly campuses: LibrarySearchOption[];
  readonly locations: LibrarySearchOption[];
  readonly countries: LibrarySearchOption[];
  readonly languages: LibrarySearchOption[];
  readonly years: LibrarySearchOption[];

  constructor(searchFields: LibrarySearchOption[], documentTypes: LibrarySearchOption[],
    resourceTypes: LibrarySearchOption[], campuses: LibrarySearchOption[],
    locations: LibrarySearchOption[], countries: LibrarySearchOption[],
    languages: LibrarySearchOption[], years: LibrarySearchOption[]) {
    this.searchFields = searchFields;
    this.documentTypes = documentTypes;
    this.resourceTypes = resourceTypes;
    this.campuses = campuses;
    this.locations = locations;
    this.countries = countries;
    this.languages = languages;
    this.years = years;
  }

  static fallback(): LibrarySearchFilterOptions {
    return new LibrarySearchFilterOptions(
      [
        new LibrarySearchOption('keyWord', '任意词', '任意'),
        new LibrarySearchOption('title', '题名'),
        new LibrarySearchOption('author', '责任者'),
        new LibrarySearchOption('isbn', '标准号', '标准号'),
        new LibrarySearchOption('callNo', '索书号', '索书'),
        new LibrarySearchOption('barcode', '条码号', '条码')
      ],
      [new LibrarySearchOption('', '全部'), new LibrarySearchOption('1', '图书')],
      [
        new LibrarySearchOption('', '全部'),
        new LibrarySearchOption('1', '馆藏资源'),
        new LibrarySearchOption('2', '电子资源')
      ],
      [
        new LibrarySearchOption('', '全部'),
        new LibrarySearchOption('1', '雁塔校区'),
        new LibrarySearchOption('2', '长安校区')
      ],
      [new LibrarySearchOption('', '全部')],
      [new LibrarySearchOption('', '全部'), new LibrarySearchOption('CN', '中国'), new LibrarySearchOption('US', '美国')],
      [new LibrarySearchOption('', '全部'), new LibrarySearchOption('chi', '汉语'), new LibrarySearchOption('eng', '英语')],
      yearOptions()
    );
  }
}

function toInt(v: string | number | null | undefined): number {
  if (typeof v === 'number') {
    return Math.trunc(v);
  }
  if (typeof v === 'string') {
    const parsed: number = parseInt(v, 10);
    return isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

function toNullableInt(v: string | number | null | undefined): number | null {
  if (v === undefined || v === null) {
    return null;
  }
  const parsed: number = toInt(v);
  return `${parsed}` === `${v}` || typeof v === 'number' ? parsed : null;
}

function toStr(v: string | number | boolean | null | undefined): string {
  return v === undefined || v === null ? '' : `${v}`;
}

function toNullableStr(v: string | number | boolean | null | undefined): string | null {
  return v === undefined || v === null ? null : `${v}`;
}

function parseLibraryDate(value: string): Date {
  if (value.length === 0) {
    return new Date();
  }
  const datePart: string = value.replace(/\//g, '-').split(' ')[0];
  const parts: string[] = datePart.split('-');
  if (parts.length >= 3) {
    return new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
  }
  return new Date();
}

/** 在借图书（对应 Dart BorrowData）。 */
export class BorrowData {
  readonly locationId: number;
  readonly loanId: number;
  readonly renewTimes: number;
  readonly recallTimes: number;
  readonly loanDate: string;
  readonly renewDate: string | null;
  readonly normReturnDate: string;
  readonly returnDate: string | null;
  readonly loanType: string;
  readonly locationName: string;
  readonly curLibCode: string;
  readonly curLibName: string;
  readonly loanDeskName: string;
  readonly title: string;
  readonly author: string;
  readonly publisher: string;
  readonly isbn: string;
  readonly isbn10: string;
  readonly isbn13: string;
  readonly publishYear: string;
  readonly propNo: string;
  readonly recordId: number;
  imageUrl: string;

  constructor(locationId: number, loanId: number, renewTimes: number, recallTimes: number,
    loanDate: string, renewDate: string | null, normReturnDate: string, returnDate: string | null,
    loanType: string, locationName: string, curLibCode: string, curLibName: string,
    loanDeskName: string, title: string, author: string, publisher: string, isbn: string,
    isbn10: string, isbn13: string, publishYear: string, propNo: string, recordId: number, imageUrl: string) {
    this.locationId = locationId;
    this.loanId = loanId;
    this.renewTimes = renewTimes;
    this.recallTimes = recallTimes;
    this.loanDate = loanDate;
    this.renewDate = renewDate;
    this.normReturnDate = normReturnDate;
    this.returnDate = returnDate;
    this.loanType = loanType;
    this.locationName = locationName;
    this.curLibCode = curLibCode;
    this.curLibName = curLibName;
    this.loanDeskName = loanDeskName;
    this.title = title;
    this.author = author;
    this.publisher = publisher;
    this.isbn = isbn;
    this.isbn10 = isbn10;
    this.isbn13 = isbn13;
    this.publishYear = publishYear;
    this.propNo = propNo;
    this.recordId = recordId;
    this.imageUrl = imageUrl;
  }

  normReturnDateTime(): Date {
    return parseLibraryDate(this.normReturnDate);
  }

  loanDateTime(): Date {
    return parseLibraryDate(this.loanDate);
  }

  /** 应还日 - 今天（天）；负数为逾期。 */
  lendDay(): number {
    const today: Date = new Date();
    const todayDate: Date = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    return Math.round((this.normReturnDateTime().getTime() - todayDate.getTime()) / 86400000);
  }
}

export interface LoanRowJson {
  locationId?: string | number | null;
  loanId?: string | number | null;
  renewTimes?: string | number | null;
  recallTimes?: string | number | null;
  loanDate?: string | number | boolean | null;
  renewDate?: string | number | boolean | null;
  normReturnDate?: string | number | boolean | null;
  returnDate?: string | number | boolean | null;
  loanType?: string | number | boolean | null;
  locationName?: string | number | boolean | null;
  curLibCode?: string | number | boolean | null;
  curLibName?: string | number | boolean | null;
  loanDeskName?: string | number | boolean | null;
  title?: string | number | boolean | null;
  author?: string | number | boolean | null;
  publisher?: string | number | boolean | null;
  isbn?: string | number | boolean | null;
  isbn10?: string | number | boolean | null;
  isbn13?: string | number | boolean | null;
  publishYear?: string | number | boolean | null;
  propNo?: string | number | boolean | null;
  recordId?: string | number | null;
}

export function borrowDataFromJson(j: LoanRowJson): BorrowData {
  return new BorrowData(
    toInt(j.locationId), toInt(j.loanId), toInt(j.renewTimes), toInt(j.recallTimes),
    toStr(j.loanDate), toNullableStr(j.renewDate), toStr(j.normReturnDate), toNullableStr(j.returnDate),
    toStr(j.loanType), toStr(j.locationName), toStr(j.curLibCode), toStr(j.curLibName),
    toStr(j.loanDeskName), toStr(j.title), toStr(j.author), toStr(j.publisher), toStr(j.isbn),
    toStr(j.isbn10), toStr(j.isbn13), toStr(j.publishYear), toStr(j.propNo), toInt(j.recordId), ''
  );
}

/** 馆藏地点条目（对应 Dart BookLocation.fromOpacJson）。 */
export class BookLocation {
  readonly yearVol: string | null;
  readonly locationName: string | null;
  readonly searchCode: string;
  readonly campus: string | null;
  readonly inDate: string | null;
  readonly barCode: string | null;
  readonly itemId: number;
  readonly circAttr: string;
  readonly processType: string;
  readonly curLocationId: string;
  readonly borrowStatus: string | null;
  readonly noBorrowMessages: string | null;

  constructor(yearVol: string | null, locationName: string | null, searchCode: string, campus: string | null,
    inDate: string | null, barCode: string | null, itemId: number, circAttr: string, processType: string,
    curLocationId: string, borrowStatus: string | null, noBorrowMessages: string | null) {
    this.yearVol = yearVol;
    this.locationName = locationName;
    this.searchCode = searchCode;
    this.campus = campus;
    this.inDate = inDate;
    this.barCode = barCode;
    this.itemId = itemId;
    this.circAttr = circAttr;
    this.processType = processType;
    this.curLocationId = curLocationId;
    this.borrowStatus = borrowStatus;
    this.noBorrowMessages = noBorrowMessages;
  }
}

export interface LocationRowJson {
  vol?: string | number | boolean | null;
  yearVol?: string | number | boolean | null;
  realLocationName?: string | number | boolean | null;
  locationName?: string | number | boolean | null;
  urlName?: string | number | boolean | null;
  callNo?: string | number | boolean | null;
  campus?: string | number | boolean | null;
  inDate?: string | number | boolean | null;
  barcode?: string | number | boolean | null;
  propNo?: string | number | boolean | null;
  itemId?: string | number | null;
  circAttr?: string | number | boolean | null;
  locationId?: string | number | boolean | null;
  processType?: string | number | boolean | null;
  curLocationId?: string | number | boolean | null;
  borrowStatus?: string | number | boolean | null;
  noBorrowMessages?: string | number | boolean | null;
}

export function bookLocationFromOpacJson(j: LocationRowJson): BookLocation {
  const locationName: string = toStr(j.realLocationName !== undefined && j.realLocationName !== null
    ? j.realLocationName : j.locationName);
  const shelfName: string = toStr(j.urlName);
  const displayLocation: string = shelfName.length === 0 ? locationName : `${locationName} ${shelfName}`;
  return new BookLocation(
    toNullableStr(j.vol !== undefined && j.vol !== null ? j.vol : j.yearVol),
    displayLocation.length === 0 ? null : displayLocation,
    toStr(j.callNo),
    toNullableStr(j.campus),
    toNullableStr(j.inDate),
    toNullableStr(j.barcode !== undefined && j.barcode !== null ? j.barcode : j.propNo),
    toInt(j.itemId),
    toStr(j.circAttr),
    toStr(j.processType),
    toStr(j.curLocationId),
    toNullableStr(j.borrowStatus),
    toNullableStr(j.noBorrowMessages)
  );
}

/** 图书信息（对应 Dart BookInfo.fromOpacJson）。 */
export class BookInfo {
  readonly author: string | null;
  readonly subject: string | null;
  readonly isbn: string | null;
  readonly description: string | null;
  readonly bookName: string;
  readonly docNumber: number;
  readonly publishYear: string | null;
  readonly publisherHouse: string | null;
  readonly groupCode: string | null;
  readonly callNos: string[];
  readonly barCodes: string[];
  readonly availableCount: number | null;
  readonly storageCount: number | null;
  imageUrl: string;

  constructor(author: string | null, subject: string | null, isbn: string | null, description: string | null,
    bookName: string, docNumber: number, publishYear: string | null, publisherHouse: string | null,
    groupCode: string | null, callNos: string[], barCodes: string[], availableCount: number | null,
    storageCount: number | null, imageUrl: string) {
    this.author = author;
    this.subject = subject;
    this.isbn = isbn;
    this.description = description;
    this.bookName = bookName;
    this.docNumber = docNumber;
    this.publishYear = publishYear;
    this.publisherHouse = publisherHouse;
    this.groupCode = groupCode;
    this.callNos = callNos;
    this.barCodes = barCodes;
    this.availableCount = availableCount;
    this.storageCount = storageCount;
    this.imageUrl = imageUrl;
  }

  canBeBorrowed(): number | null {
    return this.availableCount;
  }

  searchCodeStr(): string {
    return this.callNos.length === 0 ? '未提供' : this.callNos[0];
  }
}

export interface SearchRowJson {
  author?: string | number | boolean | null;
  subjectWord?: string | number | boolean | null;
  isbn?: string | number | boolean | null;
  adstract?: string | number | boolean | null;
  ddAbstract?: string | number | boolean | null;
  title?: string | number | boolean | null;
  barcode?: string | number | boolean | null;
  propNo?: string | number | boolean | null;
  recordId?: string | number | null;
  publishYear?: string | number | boolean | null;
  year?: string | number | boolean | null;
  publisher?: string | number | boolean | null;
  groupCode?: string | number | boolean | null;
  callNo?: string[] | string | null;
  barCodes?: string[] | null;
  onShelfCountI?: string | number | null;
  canBrrowCountI?: string | number | null;
  onShelfNum?: string | number | null;
  groupPhysicalCount?: string | number | null;
  physicalCount?: string | number | null;
}

function stringListOf(v: string[] | string | null | undefined): string[] {
  if (v === undefined || v === null) {
    return [];
  }
  if (Array.isArray(v)) {
    return v.filter((e: string): boolean => e.length > 0);
  }
  return v.length === 0 ? [] : [v];
}

export function bookInfoFromOpacJson(j: SearchRowJson): BookInfo {
  const callNos: string[] = stringListOf(j.callNo);
  const barCodesRaw: string[] | null = j.barCodes !== undefined && j.barCodes !== null ? j.barCodes : null;
  const barCodes: string[] = barCodesRaw !== null ? barCodesRaw : [];
  return new BookInfo(
    toNullableStr(j.author),
    toNullableStr(j.subjectWord),
    toNullableStr(j.isbn),
    toNullableStr(j.adstract !== undefined && j.adstract !== null ? j.adstract : j.ddAbstract),
    toStr(j.title),
    toInt(j.recordId),
    toNullableStr(j.publishYear !== undefined && j.publishYear !== null ? j.publishYear : j.year),
    toNullableStr(j.publisher),
    toNullableStr(j.groupCode),
    callNos,
    barCodes,
    toNullableInt(j.onShelfCountI !== undefined && j.onShelfCountI !== null
      ? j.onShelfCountI : (j.canBrrowCountI !== undefined && j.canBrrowCountI !== null ? j.canBrrowCountI : j.onShelfNum)),
    toNullableInt(j.groupPhysicalCount !== undefined && j.groupPhysicalCount !== null
      ? j.groupPhysicalCount : j.physicalCount),
    ''
  );
}
