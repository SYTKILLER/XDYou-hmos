# XDYou（Traintime PDA）→ HarmonyOS 移植方案

> 生成时间：2026-06-18 · 调研方式：只读探索 + harmonyos-knowledge 三级检索（T1 本地参考文件 → T2 `devecocli docs search/read` → T3 `deveco run`，本次用到 T1/T2，未触发 T3）
>
> **修订 2026-09-05**：基线更新为 traintime_pda-1.6.4（290 文件/49,422 行）；官方文档 18 项复核，修正重定向与代理提醒两处关键错误；阶段 0 编译基线达成（BUILD SUCCESSFUL 13.9s）。源项目实为 Flutter 应用，本移植为 ArkTS/ArkUI 全量重写 + 协议层平移。
>
> 标记说明：
> - **✅ 已验证** = 已通过官方 API 文档（`devecocli docs read`）或源码直接确认
> - **[候选]** = 基于已知能力推断，执行期须用 harmonyos-knowledge 三级检索复核精确签名 / API Level / import / 权限

---

## 1. 项目现状（实测数据）

### 1.1 源项目（traintime_pda-1.6.4）

- 定位：模拟浏览器访问西电（西安电子科技大学）各业务系统的个人数据助手（原开源项目 watermeter，MPLv2）。**技术栈为 Flutter**（Dart），Android/iOS 侧仅为宿主壳。
- 规模：**290 个 Dart 文件，49,422 行**（主 App 257 文件/42,709 行 + 内嵌睿思模块 33 文件/6,713 行）。
- 依赖（pubspec.yaml，节选关键）：dio、cookie_jar/dio_cookie_manager、encrypter_plus、pointycastle、crypto、charset_converter、html、shared_preferences、path_provider、signals/provider/get_it、flex_color_scheme、flutter_html、flutter_local_notifications、device_calendar_plus、home_widget、qr_code_dart_scan、file_picker、url_launcher、share_plus 等。**零遥测**。

### 1.2 分层结构（lib/，实测）

| 目录 | Dart 文件数 | 职责 | 鸿蒙移植目标 |
|---|---|---|---|
| model | 34 | 数据模型（课程/成绩/考试/实验/电量/体育/图书馆/校园卡/校园网…） | `ets/model/*.ets` 纯类 |
| repository | 36 | 网络会话（16 个学校系统 session）+ 偏好 + 日志 + 通知/日历服务 | `ets/service/*.ets` + `utils/` |
| controller | 13 | 状态管理（signals + provider + get_it） | `ets/controller/*.ets`（`@Observed`/`AppStorage`/单例） |
| page | 140 | 40+ 页面/窗口/组件 | `ets/pages/**`（ArkUI 组件重写） |
| routing | 1 | 路由表（routes.dart） | `router` 或 `Navigation` + `NavPathStack` |
| themes | 4 | 种子色主题（default/green/orange） | `ets/theme/*.ets` + `$r` 资源 |
| bridge | 1 | pigeon 生成（home_widget SaveToGroupId） | 后置阶段评估 |
| external | 33 | 睿思论坛子项目（ruisi_flutter） | 独立迁移模块 |
| generated | 2 | build_runner 生成（i18n/score_hashes） | 不移植，改原生 i18n |

### 1.3 目标工程（XDYou 根）

- DevEco 脚手架：targetSdkVersion 6.1.1(24) / compatibleSdkVersion 6.1.1(24)（2026-09-05 实测 build-profile.json5），runtimeOS HarmonyOS；deviceTypes phone/tablet/2in1。
- **编译基线：2026-09-05 hvigorw assembleHap BUILD SUCCESSFUL（13.9s）**。签名未配置（signingConfigs 空），真机验证前需 DevEco 自动签名。
- `module.json5` deviceTypes 已含 **phone / tablet / 2in1**（Master-Detail 平板布局目标天然支持）。
- 无第三方依赖（oh-package.json5 dependencies 为空）；`requestPermissions` 尚未配置（需新增，见 §6）。
- 当前仅默认脚手架页面（Index.ets + EntryAbility.ets）。

---

## 2. 核心协议与算法（源码提取的事实，移植时必须逐字节一致）

### 2.1 IDS 统一认证登录（`repository/xidian_ids/ids_session.dart`）

CAS 协议流程（已在源码确认）：

1. `GET https://ids.xidian.edu.cn/authserver/login?service=<target>` → 解析 HTML。
2. 从 HTML 提取 hidden input：`lt`、`execution`、`pwdEncryptSalt`（AES 密钥，页面动态下发）。
3. 密码加密（**关键，输出必须与 Dart 一致**）：
   - 明文 = 固定前缀 `xidianscriptsxduxidianscriptsxduxidianscriptsxduxidianscriptsxdu` + 密码
   - 手动 PKCS7 填充（paddingLength = 16 - len%16，填充字节 = paddingLength）
   - `AES-CBC`，key = `pwdEncryptSalt` 的 UTF-8 字节，**IV 固定** = `xidianscriptsxdu`（16B）
   - 结果 Base64
4. 触发滑块验证码：`GET /authserver/common/openSliderCaptcha.htl?_=<ts>`，携带 Cookie。
5. 提交：`POST /authserver/login`（form-urlencoded：username/password/rememberMe/cllt/dllt/_eventId/lt/execution）。
6. 成功判定：**301/302**（读 `Location` 头手动跟随，多跳直到 200）；401 = 密码错误（解析 `#showErrorTip`）；其他 = 解析 `#continue` form 二次 POST（CAS 续跳）。
7. 错误消息简化：`#showErrorTip` 文本含 `(用户名|密码).*误` → 归一为"用户名或密码有误"。

> 注意：`network_session.dart` 里另有**第二个 AES 用法**（随机 64B nonce + 16B 随机 IV + 自定义字符集 `_aesChars`），用于宿舍水机/电量场景，两者密钥/IV 来源不同，移植时需区分实现。

### 2.2 滑块验证码（`slider_captcha_client.dart`）

- `openSliderCaptcha.htl` 返回 JSON：`bigImage`/`smallImage`（Base64 PNG）。
- **AES key = smallImage 解码后最后 16 字节**。
- 自动求解：`solveOffset()`（图像匹配计算缺口位置）→ 邻近偏移枚举 → `generateTracks()` 生成模拟轨迹 → `verify()` 提交 `sign=AES-CBC(payload, key)`（payload = `{canvasLength, moveLength, tracks}`，IV 为空串——需在移植时确认 encrypter_plus 缺省 IV 语义）。
- **源码自带 `manualSolver` 参数**（人工求解分支）→ 移植第一期直接走人工分支，自动求解后置。

### 2.3 网络会话基础设施（`network_session.dart`）

- `PersistCookieJar`：Cookie 持久化到 `supportPath/cookie/general`（文件）。
- dio 全局配置：form-urlencoded 默认 content-type、Chrome UA、connectTimeout 10s / receiveTimeout 30s、**followRedirects=false**、validateStatus 200–399。
- `isInSchool()`：请求 `notice.xidian.edu.cn`，响应体不含"校外访问"即在校园网内。
- `initSession()`：请求 `www.xidian.edu.cn` 探测网络可用性（SessionState 状态机 none/fetching/fetched/error）。

---

## 3. API 映射表

### 3.1 网络与 Cookie（最高优先级，登录与全部数据源依赖）

| Flutter 源 | HarmonyOS 映射 | 状态与要点 |
|---|---|---|
| dio（HTTP/重定向/超时） | `@ohos.net.http`（`import { http } from '@kit.NetworkKit'`）或 `rcp`（`@kit.RemoteCommunicationKit`） | ✅ 2026-09-05 复核修正：http **默认自动跟随 30x，无 followRedirects 选项**；API 23+ 新增 `maxRedirects`（默认 30，设 0 关闭重定向，超限错误码 2300047）。原项目 `followRedirects=false` 手动读 Location 的行为需 `maxRedirects:0` 实现——**302 时 resolve 还是 reject 待阶段 1 尖兵实测**；备选 rcp（`autoRedirect:false`、typed cookies、`effectiveUrl`）。⚠️ 手动 header 设置的 Cookie 在重定向时不会自动携带（服务端 Set-Cookie 的按域名自动携带）。**请求 Cookie 需自行在 header 传入**（响应侧 `HttpResponse.cookies` 8+ 可读原始 Set-Cookie）。需 `ohos.permission.INTERNET`。明文 http 默认放行（API 18+ `cleartextTrafficPermitted` 默认 true）。响应默认上限 5MB，须设 `maxLimit`（API 23+ 单请求上限 50MB）；`body`/`queryParams` 字段为 API 26+，**禁用** |
| cookie_jar / PersistCookieJar | 自研 `CookieContainer` + `@ohos.data.preferences` 或文件持久化 | ✅ http 无 CookieManager，需自建：手动解析 `Set-Cookie`（name/value/Path/Domain/Expires），按域名匹配回填 `Cookie` 头；持久化到 preferences 或 `context.filesDir` 文件 |
| charset_converter（GBK/GB18030） | `@ohos.util` `TextDecoder`（`import { util } from '@kit.ArkTS'`） | ✅ **已解除风险**：官方文档明确支持 `gbk`、`gb18030`、`gb2312` 等编码。`decodeToString(Uint8Array)` 解码 |
| Base64 | `@ohos.util` `Base64Helper` | ✅ util 模块内置（`Base64Helper9+`） |
| 图片 base64 解码（滑块） | `@ohos.image` `ImageSource` + `image.createImagePacker` 或直接 `util.Base64Helper` 解码为字节 | [候选] 滑块图需解码为像素做匹配算法，执行期确认 `image` API |

### 3.2 加密（cryptoFramework）

| Flutter 源 | HarmonyOS 映射 | 状态与要点 |
|---|---|---|
| encrypter_plus AES-CBC（密码/水机/滑块） | `@ohos.security.cryptoFramework`（`import { cryptoFramework } from '@kit.CryptoArchitectureKit'`） | ✅ 文档确认。`createSymKeyGenerator('AES128'/'AES256')` + `createCipher('AES128|CBC|PKCS7')`，`IvParamsSpec`（iv 为 `DataBlob`，CBC 需 16B）。**注意**：IDS 密码加密是"手动 PKCS7 + 固定 IV"，与框架内置 PKCS7 填充等价但需用 `doFinal` 分块验证对拍；滑块加密 IV 为空串的场景需单测确认 |
| pointycastle RSA（校园网/体育签名） | cryptoFramework `createAsyKeyGenerator('RSA1024|PRIMES_2')` + `createCipher('RSA|PKCS1')` | [候选] 需解析服务端下发的 PEM/模数-指数，执行期确认 RSA 密钥构造方式 |
| crypto MD5（论坛登录/体育签名） | cryptoFramework `createMd('MD5')` | [候选] 文档确认 MD 支持（SHA/MD5），`Md.update/doFinal` |
| 自实现 Xor/自定义签名（如有） | 保留纯 ArkTS 实现 | 源码复核确认（schoolnet/sport 涉及） |

### 3.3 存储与文件

| Flutter 源 | HarmonyOS 映射 | 状态与要点 |
|---|---|---|
| shared_preferences / SharedPreferencesWithCache | `@ohos.data.preferences`（`import { preferences } from '@kit.ArkData'`） | ✅ 文档确认。`getPreferences(context, name)` → `get/put/flush`，Key-Value 持久化 |
| path_provider getApplicationSupportDirectory | `context.filesDir` + `@ohos.file.fs` | ✅ 常规能力，执行期确认 API Level |
| file_picker（导入/导出课表文件） | `@ohos.file.picker`（`DocumentViewPicker` / `DocumentSaveOptions`） | ✅ 文档确认。选择与保存能力，需在 UIAbility 中调用 |
| 图片缓存（cached_network_image） | ArkUI `Image` 组件 + 自研磁盘缓存（`@ohos.file.fs` + LRU） | [候选] 或直接用系统图片缓存，执行期评估 |

### 3.4 原生能力

| Flutter 源 | HarmonyOS 映射 | 状态与要点 |
|---|---|---|
| flutter_local_notifications（上课提醒/定时通知） | **首选 Calendar Kit（带提醒的日程）**；reminderAgentManager 受管控 | ⚠️ 2026-09-05 复核修正：reminderAgentManager 文档明确"手机、平板、PC/2in1 设备存在管控，应用无法直接使用代理提醒"（需向华为申请豁免，普通校园应用难获批）；`PUBLISH_AGENT_REMINDER` 为 system_grant 但不免除管控。**课程提醒改用 calendarManager 写入带提醒的日程**（Event 提醒字段实施期确认）；通知展示用 `notificationManager`。**后置里程碑** |
| device_calendar_plus（系统日历写入，含 iCal 生成） | `@ohos.calendarManager`（`import { calendarManager } from '@kit.CalendarKit'`） | ✅ 文档确认。日历/日程创建/删除/修改/查询；需 `ohos.permission.READ_CALENDAR`/`WRITE_CALENDAR`。iCal 生成逻辑保留纯 ArkTS。**后置阶段** |
| home_widget（桌面小组件） | `FormExtensionAbility` + `@ohos.app.form.*` | ✅ 有官方能力（Form Kit），但能力与 Flutter home_widget 差异大（无 AppGroup 数据共享，需 `DataShareExtensionAbility`/`distributedKVStore`）→ **后置单独评估，可能裁剪为仅提醒** |
| qr_code_dart_scan（宿舍水机扫码） | Scan Kit `scanBarcode`（默认界面扫码，API 10+）/ `customScan`（API 11+）/ `detectBarcode`（图像识码） | ✅ 文档确认。需 CAMERA 权限；`scanBarcode` 返回码值，水机场景够用 |
| url_launcher | `@ohos.app.ability.common` UIAbilityContext `openLink` / Want 拉起浏览器 | [候选] 执行期确认签名 |
| share_plus | `@ohos.systemShare`（ShareKit） | [候选] |
| permission_handler | `@ohos.abilityAccessCtrl` `requestPermissionsFromUser` | ✅ 常规能力 |
| device_info_plus / package_info_plus | `@ohos.deviceInfo` / `@ohos.bundle.bundleManager` | ✅ 常规能力 |
| fluttertoast | `@ohos.promptAction.showToast`（`@ohos.promptAction` 弹窗模块） | ✅ 文档确认 |
| restart_app | 重新拉起 Ability（`AbilityDelegator`/进程重启） | 低优先级 |
| flutter_native_splash | `module.json5` startWindow 配置 + `resources/base/media` 启动图 | ✅ 脚手架已含 startIcon/startWindow |
| flutter_i18n / flutter_localizations / intl / timezone | 原生资源 i18n（`resources/base|zh_CN|zh_TW|en_US` string.json + `$r` 引用）+ `@ohos.i18n` | ✅ 标准做法。**注意**：原项目 i18n 是 YAML（assets/flutter_i18n/*.yaml）+ generated（non_ui_i18n.g.dart），移植时转为 string.json |

### 3.5 UI 与状态管理

| Flutter 源 | HarmonyOS 映射 | 状态与要点 |
|---|---|---|
| signals / provider / get_it | ArkTS `@State/@Prop/@Link/@Provide/@Consume` + `AppStorage/LocalStorage` + 单例 service 类 | ✅ 架构重写为"controller 单例 + 组件状态装饰器" |
| FlexColorScheme / FlexThemeData（种子色） | `$r` 颜色资源（base/dark）+ 种子色 palette 重算逻辑保留纯 ArkTS | ✅ |
| MaterialApp / Navigator / routes | `@ohos.router`（`router.pushUrl`）或 **`Navigation` + `NavPathStack`**（推荐，支持 Master-Detail/平板） | ✅ 二选一执行期定 |
| Tabs（tabBar） | `Tabs` + `TabContent` | ✅ ⚠️ 注意记忆坑：`BottomTabBarStyle` 不支持 `@Builder` 作为 normal/selected 参数，自定义页签用 `@Builder` 直接传 `.tabBar()` |
| infinite_scroll_pagination / staggered grid | `List` + `LazyForEach` 分页 / `Grid` 瀑布流 | ✅ 原生组件 |
| flutter_html / html（富文本） | **无现成库** → 自研轻量 HTML 解析器 + `RichText`/`Span` 重渲染 | ⚠️ 核心前置工作，见 §4 |

---

## 4. 风险与对策（调研后更新）

| # | 风险 | 状态 | 对策 |
|---|---|---|---|
| 1 | **HTML 解析无现成库**（登录 hidden form、错误提示、各系统页面数据提取全依赖 `html` 包） | 未解除 | 自研轻量 DOM 子集解析器：`getElementById` / `getElementsByTagName` / `getElementsByClassName` / 属性读取（`attrs`）+ 文本提取；先覆盖登录页与已知 16 个 session 用到的选择器。**作为阶段 1 前置任务** |
| 2 | **AES/RSA 输出必须与 Dart 逐字节一致** | 执行期验证 | 用固定向量单测对拍：IDS 密码加密（固定前缀+固定 IV）、水机 nonce 模式、滑块 smallImage 末 16B key、体育/校园网 RSA。`entry/src/test` LocalUnit.test.ets |
| 3 | GBK/GB18030 解码 | ✅ **已解除** | `@ohos.util.TextDecoder` 官方支持 gbk/gb18030/gb2312 |
| 4 | 滑块验证码自动求解（图像匹配 + 轨迹模拟） | 高风险 | 第一期走源码自带的 `manualSolver` 人工分支（展示滑块图 + 用户滑动）；自动求解算法（`solveOffset`/`generateTracks`）后置独立攻坚 |
| 5 | Cookie 持久化（http 无 CookieManager） | 自研 | `CookieContainer`：解析 `Set-Cookie` + 域名匹配 + preferences 持久化；重启免登录依赖它 |
| 6 | 大响应体（5MB 上限） | 执行期验证 | 所有请求设置 `maxLimit`（如 20MB），或对下载流用 `requestInStream` |
| 7 | 桌面小组件 / 日历写入 | 能力受限 | 后置里程碑单独评估；小组件可能裁剪为仅"课程提醒通知" |
| 8 | 工作量（265 文件 / 45.7K 行，page 140 文件） | 已知 | 按里程碑分批交付（§5），每阶段编译验证 + 日志沉淀 |

---

## 5. 分阶段执行计划

> 每阶段结束必须编译验证（命令见 §7），遵守 `harmonyos-dev-spec` 语法禁区（禁 `any`、解构、对象展开、`for..in`、`obj["field"]`、第三方库、`catch` 类型标注、`require` 等）。

### 阶段 0：环境与基线（0.5 天）
1. 定位 DevEco Studio / hvigor 路径（`local.properties` 为空，需从环境或默认安装路径探测）。
2. 编译现有脚手架 → baseline `BUILD SUCCESSFUL`。
3. 用 harmonyos-knowledge 三级检索复核 §3 中所有 `[候选]` 项（RSA 密钥构造、openLink、systemShare、Image 解码、reminderAgentManager 权限等）。

### 阶段 1：工程骨架 + 基础设施（1-2 天）
1. 建目录：`entry/src/main/ets/{model,service,controller,pages,theme,utils,i18n}`。
2. **自研 HTML 解析器**（`utils/html_parser.ets`）——登录与全部数据源的前置。
3. `NetworkSession.ets`：`@ohos.net.http` 封装（手动重定向、UA、超时、maxLimit、form-urlencoded）+ `CookieContainer` + `isInSchool`。
4. `utils/crypto.ets`（AES/RSA/MD5/Base64）+ `utils/charset.ets`（TextDecoder GBK），**单测对拍**。
5. `PreferenceService`（preferences 封装）+ logger（`@ohos.hilog`）。
6. 主题（深/浅色 + 种子色）+ i18n 资源骨架（base/zh_CN/zh_TW/en_US string.json）。

### 阶段 2：登录闭环（最高优先级，1-2 天）
1. `IDS_Session.ets`：CAS 流程（§2.1）+ AES 密码加密 + hidden 表单解析 + Cookie。
2. 滑块验证码**人工降级路径**（`jc_captcha` 图形验证码组件 → ArkUI 重写）。
3. 登录页 `LoginWindow.ets` 重写。
4. 验收：能登录、Cookie 持久化、重启免登录、密码错误提示（`#showErrorTip`）。

### 阶段 3：登录后页面建设（2026-09-06 修订：三 Tab 框架 + 逐模块迭代）

> **修订决策（2026-09-06，用户确认）**：
> 1. 登录后框架改为**三页签**（首页 / 全部功能 / 设置，悬浮毛玻璃底栏 + 沉浸光感），替代原"五 Tab"方案。
> 2. **睿思论坛、猪图鉴赏（Pig）放弃移植**，从全部里程碑移除。
> 3. 页面 UI 按 HarmonyOS 设计语言用系统组件重新设计（不复刻 Flutter 布局）；数据逻辑（聚合/周次/过滤/协议）与原版对齐。
> 4. 关键 API 已核实 SDK d.ts（API 24 可用）：Swiper@7、Refresh@8、ListItemGroup@10、SymbolGlyph@11、backgroundBlurStyle@11（BlurStyle.COMPONENT_THICK@12）、expandSafeArea@11、window.setWindowBackgroundColor。
> 5. 首页首期仅「今日日程」+「考试安排」两卡；全部功能页只展示已移植功能；设置页账号区首字符头像 + 尽力取真实姓名（回退学号）。
> 6. **修订决策（2026-09-07，用户确认）**：首页改版为"此刻"聚焦版——Hero 卡（课程/考试双形态：合并时间线取最近一条未结束日程，课程上完考试自然顶到首位；考试态展示时间/考场/座位 + 分钟级倒计时）+ "需要留意"提醒条（电费低于阈值/图书 7 天内到期/考试临近，Hero 考试态去重）+ 2×2 信息瓦片（考试倒计时/宿舍电费/图书借阅/校园网流量）；refreshAll 扩源 5 路 allSettled（校园网仅刷免验证码的在线信息，zfw 自助用量仍由页面拉取）。替代第 5 条的两卡首期方案。

1. **M1 三 Tab 悬浮底栏框架**：HomePageView（Swiper 3 页 keep-alive + 悬浮毛玻璃底栏 backgroundBlurStyle）、首页/全部功能/设置三页骨架、NavDestination 注册结构、窗口背景与安全区融合。
2. **M2 学期 + 课程表**：SemesterSession、ClassTableSession（本科 ehall + 研究生 yjspt 双链路；调课/停课/补课合并算法照搬）、model/ClassTableData、ClassTableController（周次计算 termStartDay+7×weekSwift）、周视图课程表页。
3. **M3 考试**：ExamSession（双角色链路）、ExamData 时间正则解析、分组卡片考试页（未开考/已结束/无法参加/未安排）。
4. **M4 首页聚合**：GlobalTimer 整分对齐定时器（AppStorage nowTick + onForeground 补算）、今日日程卡片（课程+考试聚合 HomeArrangement，过滤 endTime≤now，21:25 切明日）、考试卡片（未结束考试升序提前展示，最近一场高亮）、Refresh 下拉刷新、加载/错误态。
5. **M5 全部功能页 + 设置页完善**：功能入口注册表（Grid 宫格）、账号区（教务接口取姓名，回退学号）、平台账号管理（校园网账号增改删存）、偏好（主题种子色/深浅色）。
6. **M6+ 逐模块迭代**：成绩→校园网→一卡通→图书馆→电费→空教室→考勤→水机→物理实验→体育（顺序可按难度调整），每模块用鸿蒙组件重设计 UI，完成后进入全部功能页，适用的模块加回首页卡片。

### 阶段 4：系统级扩展（后置，各单独评估）
1. 上课提醒：`reminderAgentManager` 定时提醒（替代 flutter_local_notifications zonedSchedule）+ `notificationManager`。
2. 系统日历同步：`calendarManager`（含 iCal 生成逻辑移植）。
3. 桌面小组件：FormExtensionAbility 可行性评估，受限则裁剪。

### 阶段 5：收尾
1. 全量编译 + 真机/模拟器回归核心闭环（登录 → 课程表 → 成绩 → 首页聚合）。
2. 更新 `DEVELOPMENT_LOG.md`、`PROJECT_STRUCTURE.md`；新坑沉淀到记忆。

---

## 6. 权限清单（`module.json5` `requestPermissions` 需新增）

| 权限 | 用途 | 阶段 |
|---|---|---|
| `ohos.permission.INTERNET` | 全部网络请求（**必须**） | 0 |
| `ohos.permission.GET_NETWORK_INFO` | isInSchool/网络状态探测 | 1 |
| `ohos.permission.CAMERA` | 水机扫码 | 3 |
| `ohos.permission.NOTIFICATION_CONTROLLER` 或 `PUBLISH_AGENT_REMINDER`（以执行期文档为准） | 上课提醒 | 4 |
| `ohos.permission.READ_CALENDAR` / `WRITE_CALENDAR` | 系统日历同步 | 4 |
| 相册/文件访问（如导入课表图片） | 视功能定 | 3 |

---

## 7. 验证方式（每阶段）

```bash
cd D:\HarmonyOS_Develop\XDYou && node "<DevEcoStudio>/tools/hvigor/bin/hvigorw.js" assembleHap --mode module -p module=entry@default -p product=default
```

- 超时 180s；成功标志 `BUILD SUCCESSFUL`。
- 报错循环：读错误 → harmonyos-knowledge 三级检索（T1 grep 参考文件 → T2 `devecocli docs search` → T3 `deveco run`）→ 修 → 重编。
- 单元测试（`entry/src/test` LocalUnit.test.ets）重点覆盖：
  - crypto 对拍：IDS 密码 AES（固定向量）、水机 nonce AES、MD5、RSA。
  - charset：GBK/GB18030 已知字节样本解码。
  - HTML 解析：登录页 hidden form 提取、`#showErrorTip` 文本。

---

## 8. 假设（执行前确认）

1. 编译/运行目标为手机 + 平板（Master-Detail 平板分支），module.json5 已含 phone/tablet/2in1。
2. HTTP 主力在 `@ohos.net.http`（`maxRedirects:0`）与 `rcp`（`autoRedirect:false`）之间由阶段 1 网络尖兵实测定夺（判据：谁能把 302 响应本体返回给应用以读取 Location/Set-Cookie）；如遇 http 无法满足的场景（并发池、流式、代理控制）再评估 rcp。
3. 目标 SDK 6.1.1(24)，API 10+ 能力可用（scanBarcode/customScan/usingProxy 等按需确认）。
4. 源项目保持只读，不修改；移植产物全部落在 XDYou 工程 `entry/` 下。
