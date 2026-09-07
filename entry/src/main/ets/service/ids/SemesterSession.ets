import { IdsSession } from './IdsSession';
import { backgroundSliderHandler } from './BackgroundSlider';
import { SliderCaptchaHandler } from './SliderCaptchaHandler';
import { SessionManager } from '../SessionManager';
import { SessionResponse } from '../network/NetworkSession';
import { PreferenceService } from '../preference/PreferenceService';
import { Log } from '../../utils/Log';

// ---- 响应 JSON 形状（字段名以学校接口原文为准） ----

interface YjsptUserInfoData {
  xnxqdm?: string;
  xm?: string;
  name?: string;
}

interface YjsptUserInfoResp {
  code?: string | number;
  msg?: string;
  data?: YjsptUserInfoData;
}

interface DqxnxqRow {
  DM?: string;
}

interface DqxnxqSection {
  rows?: DqxnxqRow[];
}

interface EhallDqxnxqDatas {
  dqxnxq?: DqxnxqSection;
}

interface EhallDqxnxqResp {
  datas?: EhallDqxnxqDatas;
}

const YJSPT_USER_INFO_URL: string =
  'https://yjspt.xidian.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do';
const EHALL_DQXNXQ_URL: string =
  'https://ehall.xidian.edu.cn/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do';
const EHALL_APP_SHOW_URL: string =
  'https://ehall.xidian.edu.cn/appShow?appId=4770397878132218';

/**
 * 当前学期拉取（对应 Dart repository/ids_session/semester_session.dart）。
 * 本科走 ehall 教务，研究生走 yjspt。
 */
export class SemesterSession {
  /** 研究生：yjspt getUserInfo.do → data.xnxqdm。 */
  static async getSemesterInfoYjspt(): Promise<string> {
    const slider: SliderCaptchaHandler = backgroundSliderHandler();
    const location: string = await IdsSession.checkAndLogin('https://yjspt.xidian.edu.cn/', slider);
    await IdsSession.followRedirects(location);
    const response: SessionResponse =
      await SessionManager.ids().postForm(YJSPT_USER_INFO_URL, new Map<string, string>());
    const parsed: YjsptUserInfoResp = JSON.parse(response.bodyText) as YjsptUserInfoResp;
    if (`${parsed.code ?? ''}` !== '0') {
      throw new Error(`学期信息获取失败：${parsed.msg ?? '未知错误'}`);
    }
    const semester: string = parsed.data !== undefined && parsed.data.xnxqdm !== undefined ? parsed.data.xnxqdm : '';
    // 尽力提取真实姓名（研究生 getUserInfo 响应可能带 xm/name；本科无源，回退学号，M6 成绩/校园网接口再补）。
    if (parsed.data !== undefined) {
      const name: string = parsed.data.xm !== undefined && parsed.data.xm !== null ? parsed.data.xm
        : (parsed.data.name !== undefined && parsed.data.name !== null ? parsed.data.name : '');
      if (name.length > 0) {
        PreferenceService.putString('displayName', name);
      }
    }
    Log.info(`[SemesterSession][yjspt] semester=${semester}`);
    return semester;
  }

  /** 本科：ehall dqxnxq.do → datas.dqxnxq.rows[0].DM。 */
  static async getSemesterInfoEhall(): Promise<string> {
    const slider: SliderCaptchaHandler = backgroundSliderHandler();
    const location: string = await IdsSession.checkAndLogin(EHALL_APP_SHOW_URL, slider);
    await IdsSession.followRedirects(location);
    const response: SessionResponse =
      await SessionManager.ids().postForm(EHALL_DQXNXQ_URL, new Map<string, string>());
    const parsed: EhallDqxnxqResp = JSON.parse(response.bodyText) as EhallDqxnxqResp;
    const rows: DqxnxqRow[] =
      parsed.datas !== undefined && parsed.datas.dqxnxq !== undefined && parsed.datas.dqxnxq.rows !== undefined
        ? parsed.datas.dqxnxq.rows : [];
    if (rows.length === 0 || rows[0].DM === undefined) {
      throw new Error('学期信息获取失败：响应缺少学期代码');
    }
    Log.info(`[SemesterSession][ehall] semester=${rows[0].DM}`);
    return rows[0].DM;
  }
}
