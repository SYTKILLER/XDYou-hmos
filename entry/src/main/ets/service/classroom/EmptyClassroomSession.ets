import { IdsSession } from '../ids/IdsSession';
import { backgroundSliderHandler } from '../ids/BackgroundSlider';
import { SessionManager } from '../SessionManager';
import { NetworkSession, SessionResponse } from '../network/NetworkSession';
import { EmptyClassroomData, EmptyClassroomPlace } from '../../model/classroom/EmptyClassroomData';
import { Log } from '../../utils/Log';

// ---- 响应/请求 JSON 形状（显式 interface，动态 datas 键逐一声明） ----

interface OrderBody {
  '*order': string;
}

interface BuildingRow {
  JXLDM?: string;
  JXLJC?: string;
}

interface BuildingRows {
  rows?: BuildingRow[] | null;
}

interface BuildingDatas {
  jxlcx?: BuildingRows;
}

interface BuildingResp {
  datas?: BuildingDatas;
}

interface DateBody {
  RQ: string;
  XN: string;
  XQ: string;
}

interface DateConvertSection {
  ZC?: string | number | null;
  XQJ?: string | number | null;
}

interface DateConvertDatas {
  rqzhzcjc?: DateConvertSection;
}

interface DateConvertResp {
  datas?: DateConvertDatas;
}

interface QuerySetting {
  name: string;
  caption?: string;
  builder: string;
  linkOpt: string;
  value?: string | number;
}

interface CxjsqkBody {
  XNXQDM: string;
  ZC: string | number;
  XQ: string | number;
  querySetting: string;
  '*order': string;
  pageSize: number;
  pageNumber: number;
}

interface RoomRow {
  JASMC?: string | null;
  JC1?: string | null;
  JC2?: string | null;
  JC3?: string | null;
  JC4?: string | null;
  JC5?: string | null;
  JC6?: string | null;
  JC7?: string | null;
  JC8?: string | null;
  JC9?: string | null;
  JC10?: string | null;
  JC11?: string | null;
}

interface RoomRows {
  rows?: RoomRow[] | null;
}

interface RoomDatas {
  cxjsqk?: RoomRows;
}

interface RoomResp {
  datas?: RoomDatas;
}

const BASE_URL: string = 'https://ehall.xidian.edu.cn/jwapp/sys/kxjas/modules/kxjas';
const EHALL_APP_URL: string = 'https://ehall.xidian.edu.cn/appShow?appId=4768402106681759';

/**
 * 空闲教室查询（对应 Dart repository/ids_session/empty_classroom_session.dart，ehall kxjas）。
 * 复用主 IDS 会话（checkAndLogin + followRedirects，滑块走后台自动求解），业务接口均为 JSON POST。
 * 注意：weekDaySetting 的 name 原版就写成了 "ZC"（上游疑似 bug），此处忠实复刻以保证服务端行为一致。
 */
export class EmptyClassroomSession {
  private static async loginAndFollow(): Promise<void> {
    const slider = backgroundSliderHandler();
    const location: string = await IdsSession.checkAndLogin(EHALL_APP_URL, slider);
    await IdsSession.followRedirects(location);
  }

  /** 楼栋列表（JXLDM 教学楼代码 / JXLJC 简称）。 */
  static async getBuildingList(): Promise<EmptyClassroomPlace[]> {
    await EmptyClassroomSession.loginAndFollow();
    const session: NetworkSession = SessionManager.ids();
    const body: OrderBody = { '*order': '+XXXQDM,+PX,+JXLDM' };
    const resp: SessionResponse = await session.postRaw(`${BASE_URL}/jxlcx.do`, 'application/json', JSON.stringify(body));
    const parsed: BuildingResp = JSON.parse(resp.bodyText) as BuildingResp;
    const rows: BuildingRow[] =
      parsed.datas !== undefined && parsed.datas.jxlcx !== undefined
      && parsed.datas.jxlcx.rows !== undefined && parsed.datas.jxlcx.rows !== null
        ? parsed.datas.jxlcx.rows : [];
    const toReturn: EmptyClassroomPlace[] = [];
    rows.forEach((i: BuildingRow): void => {
      toReturn.push(new EmptyClassroomPlace(i.JXLDM ?? '', i.JXLJC ?? ''));
    });
    return toReturn;
  }

  private static jcValue(row: RoomRow, index: number): string {
    if (index === 1) {
      return row.JC1 ?? '';
    }
    if (index === 2) {
      return row.JC2 ?? '';
    }
    if (index === 3) {
      return row.JC3 ?? '';
    }
    if (index === 4) {
      return row.JC4 ?? '';
    }
    if (index === 5) {
      return row.JC5 ?? '';
    }
    if (index === 6) {
      return row.JC6 ?? '';
    }
    if (index === 7) {
      return row.JC7 ?? '';
    }
    if (index === 8) {
      return row.JC8 ?? '';
    }
    if (index === 9) {
      return row.JC9 ?? '';
    }
    if (index === 10) {
      return row.JC10 ?? '';
    }
    return row.JC11 ?? '';
  }

  /**
   * 查询某楼栋某日期的教室节课状态。
   * @param semesterCode 学期编码，形如 "2025-2026-1"。
   */
  static async searchData(buildingCode: string, date: string, semesterCode: string): Promise<EmptyClassroomData[]> {
    await EmptyClassroomSession.loginAndFollow();
    const session: NetworkSession = SessionManager.ids();
    const dash: number = semesterCode.lastIndexOf('-');
    if (dash < 0) {
      throw new Error('学期编码无效，请先同步学期信息');
    }
    const semesterRange: string = semesterCode.substring(0, dash);
    const semesterPart: string = semesterCode.substring(dash + 1);

    const dateBody: DateBody = { RQ: date, XN: semesterRange, XQ: semesterPart };
    const dateResp: SessionResponse = await session.postRaw(`${BASE_URL}/rqzhzcjc.do`, 'application/json',
      JSON.stringify(dateBody));
    const dateParsed: DateConvertResp = JSON.parse(dateResp.bodyText) as DateConvertResp;
    const dateSection = dateParsed.datas !== undefined ? dateParsed.datas.rqzhzcjc : undefined;
    if (dateSection === undefined || dateSection.ZC === undefined || dateSection.ZC === null
      || dateSection.XQJ === undefined || dateSection.XQJ === null) {
      throw new Error('日期转周次失败，请确认日期在本学期范围内');
    }
    const weekCount: string | number = dateSection.ZC;
    const weekDay: string | number = dateSection.XQJ;

    const querySetting: QuerySetting[] = [
      { name: 'JXLDM', caption: '教学楼代码', builder: 'equal', linkOpt: 'AND', value: buildingCode },
      { name: 'XNXQDM', value: semesterCode, linkOpt: 'AND', builder: 'equal' },
      { name: 'ZC', value: weekCount, linkOpt: 'AND', builder: 'equal' },
      // 原版 bug 复刻：本项 name 应为 XQ，但上游写成 ZC，按服务端实际接受的行为保持一致。
      { name: 'ZC', value: weekDay, linkOpt: 'AND', builder: 'equal' }
    ];
    const body: CxjsqkBody = {
      XNXQDM: semesterCode,
      ZC: weekCount,
      XQ: weekDay,
      querySetting: JSON.stringify(querySetting),
      '*order': '+LC,+JASMC',
      pageSize: 999,
      pageNumber: 1
    };
    const roomResp: SessionResponse = await session.postRaw(`${BASE_URL}/cxjsqk.do`, 'application/json',
      JSON.stringify(body));
    const roomParsed: RoomResp = JSON.parse(roomResp.bodyText) as RoomResp;
    const rows: RoomRow[] =
      roomParsed.datas !== undefined && roomParsed.datas.cxjsqk !== undefined
      && roomParsed.datas.cxjsqk.rows !== undefined && roomParsed.datas.cxjsqk.rows !== null
        ? roomParsed.datas.cxjsqk.rows : [];
    const toReturn: EmptyClassroomData[] = [];
    rows.forEach((i: RoomRow): void => {
      const name: string = (i.JASMC ?? '')
        .replace(/[(（]/g, '\n')
        .replace(/[)）]/g, '');
      const isUsed: boolean[] = [];
      for (let index: number = 1; index <= 11; index++) {
        isUsed.push(EmptyClassroomSession.jcValue(i, index).includes('1_'));
      }
      toReturn.push(new EmptyClassroomData(name, isUsed));
    });
    Log.info(`emptyClassroom rows: ${toReturn.length}`);
    return toReturn;
  }
}
