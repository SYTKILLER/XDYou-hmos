import { LibrarySession } from '../service/library/LibrarySession';
import { BookInfo, BorrowData, LibrarySearchFilterOptions } from '../model/library/LibraryModels';
import { Log } from '../utils/Log';

/**
 * 图书馆控制器：借阅列表内存态（原版无持久缓存）+ 检索分页状态 + 筛选项缓存。
 * libraryVersion 通知借阅页；检索结果由检索页本地状态管理（分页 append）。
 */
export class LibraryController {
  private static borrowList: BorrowData[] = [];
  private static borrowInflight: Promise<void> | null = null;
  private static borrowLoadingFlag: boolean = false;
  private static borrowErrorMsg: string = '';
  private static filterOptions: LibrarySearchFilterOptions | null = null;
  private static filterInflight: Promise<LibrarySearchFilterOptions> | null = null;

  static borrowData(): BorrowData[] {
    return LibraryController.borrowList;
  }

  static borrowLoading(): boolean {
    return LibraryController.borrowLoadingFlag;
  }

  static borrowError(): string {
    return LibraryController.borrowErrorMsg;
  }

  private static bumpVersion(): void {
    AppStorage.setOrCreate('libraryVersion', (AppStorage.get<number>('libraryVersion') ?? 0) + 1);
  }

  static refreshBorrowList(): Promise<void> {
    if (LibraryController.borrowInflight !== null) {
      return LibraryController.borrowInflight;
    }
    LibraryController.borrowLoadingFlag = true;
    LibraryController.borrowErrorMsg = '';
    LibraryController.bumpVersion();
    const task: Promise<void> = (async (): Promise<void> => {
      try {
        LibraryController.borrowList = await LibrarySession.getBorrowList();
      } catch (e) {
        LibraryController.borrowErrorMsg = e instanceof Error ? e.message : `${e}`;
        Log.warn(`library borrow list failed: ${e}`);
      } finally {
        LibraryController.borrowLoadingFlag = false;
        LibraryController.borrowInflight = null;
        LibraryController.bumpVersion();
      }
    })();
    LibraryController.borrowInflight = task;
    return task;
  }

  static renew(loanId: number): Promise<string> {
    return LibrarySession.renew(loanId);
  }

  /** 筛选项（字段/条件/馆藏地），内存缓存一次。 */
  static getFilterOptions(): Promise<LibrarySearchFilterOptions> {
    if (LibraryController.filterOptions !== null) {
      return Promise.resolve<LibrarySearchFilterOptions>(LibraryController.filterOptions);
    }
    if (LibraryController.filterInflight !== null) {
      return LibraryController.filterInflight;
    }
    const task: Promise<LibrarySearchFilterOptions> = LibrarySession.searchFilterOptions()
      .then((options: LibrarySearchFilterOptions): LibrarySearchFilterOptions => {
        LibraryController.filterOptions = options;
        return options;
      });
    LibraryController.filterInflight = task;
    return task;
  }

  /** 简单检索（供检索页常规模式调用）。 */
  static search(word: string, page: number, field: string): Promise<BookInfo[]> {
    return LibrarySession.searchBook(word, page, field);
  }

  /** 高级检索（组合条件 + 全量筛选）。 */
  static advancedSearch(word: string, page: number, field: string, matchMode: string,
    docCode: string | null, resourceType: string | null, locationId: number | null,
    countryCode: string | null, langCode: string | null, onlyOnShelf: boolean | null,
    publishBegin: string | null, publishEnd: string | null): Promise<BookInfo[]> {
    return LibrarySession.advancedSearchBook({
      searchWord: word, searchField: field, matchMode: matchMode, page: page,
      docCode: docCode, resourceType: resourceType, locationId: locationId,
      countryCode: countryCode, langCode: langCode, onlyOnShelf: onlyOnShelf,
      publishBegin: publishBegin, publishEnd: publishEnd
    });
  }
}
