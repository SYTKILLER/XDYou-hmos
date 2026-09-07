# XDYou（HarmonyOS 版）项目结构

> 更新：2026-09-07 · 五功能迁移（实验信息/空闲教室/图书馆/体育信息/宿舍水机）完成
> 源项目 `traintime_pda-1.6.4/` 只读；产物全部在 `entry/` 下。

## 工程配置

| 项 | 值 |
|---|---|
| bundleName | `com.xdyou.app` |
| SDK | targetSdk / compatibleSdk 均 6.1.1(24)，runtimeOS HarmonyOS |
| 设备 | phone / tablet / 2in1 |
| 依赖 | 零第三方（仅系统 Kit） |
| 权限 | INTERNET、GET_NETWORK_INFO（system_grant） |
| 签名 | 未配置（signingConfigs 空，真机验证前由 DevEco 自动签名） |

## 目录树（entry/src/main/ets/）

```
entryability/
  EntryAbility.ets          # 偏好初始化、AppContext 注入、登录态注入 AppStorage、色彩模式、窗口背景
entrybackupability/
model/
  FetchResult.ets           # 统一抓取结果（fresh/cache + fetchTime + hintKey）
  HomeArrangement.ets       # 首页日程聚合条目（课程/考试统一形态，M4 使用）
  TimeList.ets              # 22 项节次时间表（偶=开始/奇=结束）
  classtable/
    ClassTableData.ets      # 课表模型（ClassDetail/TimeArrangement/ClassChange）+ 缓存 JSON 序列化
  exam/
    ExamData.ets            # 考试模型（Subject 时间正则解析/ToBeArranged）+ 缓存 JSON 序列化
  score/
    ScoreData.ets           # 成绩模型（Score/gpa映射/ComposeDetail）+ scores.json 缓存序列化
  energy/
    EnergyData.ets          # 能耗模型（MeterInfo/EnergyInfo/本地余量历史）+ 缓存序列化
  schoolnet/
    NetworkUsage.ets        # 校园网模型（GeneralNetworkUsage/CurrentUserNetInfo 防御化解析/formatBytes）
  dormwater/
    DormWaterData.ets       # 水机模型（DormWaterDevice/CaptchaData + favos JSON 解析）
  sport/
    SportModels.ets         # 体育模型（SportScore/年度明细/SportClassItem 学期与时间正则）
  classroom/
    EmptyClassroomData.ets  # 空闲教室模型（Place/Data 11 节占用）
  library/
    LibraryModels.ets       # 图书馆模型（BorrowData/BookInfo/BookLocation fromOpacJson + 检索选项）
  experiment/
    ExperimentData.ets      # 实验模型（物理/其他 + RecognitionResult 成绩识别 + 缓存序列化）
    ScoreHashes.ets         # kScoreHashes 成绩图片 FNV-1a 哈希表 + 13 节时间表
pages/
  Index.ets                 # @Entry：Navigation 根 + 登录态分流 + navDestination 注册
  LoginPage.ets             # 登录页（账号/密码/进度条/错误 toast）
  SliderCaptchaPage.ets     # 滑块验证码 NavDestination（人工拖动采轨迹）
  ReAuthDialog.ets          # 短信二次认证 @CustomDialog（倒计时/信任设备）+ ReAuthCoordinator
  home/
    HomePageView.ets        # 登录后主框架：官方 HdsTabs 三页签 + barFloatingStyle 沉浸光感（API23）+ 启动定时器/静默刷新
    HomeTab.ets             # 首页：今日日程卡（课程+考试聚合时间轴）+ 考试卡（倒计时）+ Refresh 下拉
    AllFeaturesTab.ets      # 全部功能页签（入口注册表 Grid：5 个原生模块 + 工具箱 7 个网址跳转项；随里程碑追加）
    SettingTab.ets          # 设置页签（M1：首字符头像账号区 + 退出登录；M5 补平台账号/偏好）
    HomeLayout.ets          # 框架共享布局常量（TAB_BAR_CLEARANCE 底部避让留白）
  score/
    ScorePage.ets           # 成绩查询 NavDestination：汇总卡 + 学期筛选 + 列表（不及格标红）
    ScoreDetailDialog.ets   # 单科成绩组成 @CustomDialog（cxkckgcxlrcj 协议）
  energy/
    ElectricityPage.ets     # 电费查询 NavDestination：余量大卡（低阈值告警）+ 电表/水表读数 + 本地记录
  schoolnet/
    SchoolnetPage.ets       # 校园网 NavDestination：在线信息卡 + 自助服务用量 + 内联验证码登录
  setting/
    SettingTab.ets          # 设置页签：账号区（displayName 回退学号）/校园网密码/偏好/版本/退出
    SchoolnetPasswordDialog.ets # 校园网自助服务查询密码 @CustomDialog
    ExperimentPasswordDialog.ets # 实验平台密码 @CustomDialog（实验页共用）
    SportPasswordDialog.ets   # 体育平台密码 @CustomDialog（体育页共用）
  classtable/
    ClassTablePage.ets      # 课程表 NavDestination：周视图 Grid + 周次切换 + 缓存/加载/错误态
    CourseDetailDialog.ets  # 课程详情 @CustomDialog：点击格子弹卡片（周次圆点表/老师/教室/节次钟点，冲突课并列）
  exam/
    ExamPage.ets            # 考试安排 NavDestination：分组卡片（未开考/已结束/时间待定/待安排）
  web/
    WebViewPage.ets         # 通用网页 NavDestination（ArkWeb）：pushPath 传 WebNavParam{title,url} 应用内加载工具箱网址；主框架错误态+重载、返回键优先回退网页历史
  dormwater/
    DormWaterPage.ets       # 宿舍水机 NavDestination：收藏设备 + 扫码添加(Scan Kit) + 出水轮询；未登录直接拉起登录页
    DormWaterLoginPage.ets  # 水机登录页：手机号+图片验证码+短信码；已登录态脱敏展示+退出
  sport/
    SportPage.ets           # 体育信息 NavDestination：体测成绩/体育课成绩双页签；未配置密码拉起共用对话框
  classroom/
    EmptyClassroomPage.ets  # 空闲教室 NavDestination：楼栋 Select+日期+过滤+11 节方格
  library/
    LibraryPage.ets         # 图书馆 NavDestination：我的借阅（续借）/完整高级检索双页签
    BookDetailPage.ets      # 图书详情 NavDestination：书目信息+封面+馆藏地点
  experiment/
    ExperimentPage.ets      # 实验信息 NavDestination：物理+其他按 进行中/未开始/已完成 分组；未配置密码拉起共用对话框
service/
  AppContext.ets            # UIAbility 上下文持有者（cacheDir 缓存文件读写，EntryAbility 注入）
  SessionManager.ets        # 会话注册中心：ids/schoolnet/sport/general + Cookie 持久化
  network/
    NetworkSession.ets      # rcp 封装：autoRedirect:false、手动重定向、Cookie 注入/回收、GBK 解码
    CookieContainer.ets     # RFC6265 简化匹配的持久化 Cookie 容器
  ids/
    IdsSession.ets          # CAS 登录闭环 + reAuth 拦截（checkAndLogin/followRedirects/研究生判定）
    IdsCrypto.ets           # IDS 密码加密（固定前缀+手动PKCS7+固定IV）、滑块 payload 加密、设备指纹
    IdsAuthProtocol.ets     # 二次认证协议解析（短信下发/提交结果/错误类）
    IdsReAuthClient.ets     # 短信二次认证客户端（prepare/sendSms/submitSms+信任设备）
    SliderCaptchaClient.ets # 滑块验证码：updatePuzzle / verify / solveWithAuto（自动优先+人工兜底）
    SliderAutoSolver.ets    # NCC 自动求解 + S形轨迹生成（移植 Dart solveOffset/generateTracks）
    SliderCaptchaHandler.ets# 滑块回调接口
    CaptchaCoordinator.ets  # 登录流程↔滑块页桥接
    BackgroundSlider.ets    # 后台续登滑块处理器（仅自动求解，不弹人工页）
    SemesterSession.ets     # 当前学期拉取（ehall dqxnxq / yjspt getUserInfo）
    ClassTableSession.ets   # 课表抓取（ehall 全链含调课合并算法 / yjspt 链）+ ClassTable.json 缓存
    ExamSession.ets         # 考试抓取（ehall wdksap / yjspt wdksxxcx）+ exam.json 缓存
    ScoreSession.ets        # 成绩抓取（ehall cjcx / yjspt wdcj）+ 成绩组成查询 + scores.json 缓存
    EnergySession.ets       # 电费抓取（ignypt 新能耗系统：签名头 + AES-CBC 加密 content）+ 快照/历史缓存
  schoolnet/
    SchoolnetSession.ets    # 校园网抓取（rad_user_info JSONP + zfw 自助服务登录链/HTML 解析/RSA）
  dormwater/
    DormWaterSession.ets    # 慧798 水机（图片验证码+短信登录，token 三键持久化，裸 Authorization）
  sport/
    SportSession.ets        # 体育平台（RSA 登录 /h5/login 根路径、sign=MD5 排序串、401/402 自动重登）
  classroom/
    EmptyClassroomSession.ets # 空闲教室（ehall kxjas 三接口，复用 IDS 会话；weekDaySetting bug 复刻）
  library/
    LibrarySession.ets      # 图书馆（IDS→超星 CAS→OPAC JWT 链 + 检索/借阅/续借全接口）
  experiment/
    ExperimentSession.ets   # 物理实验（wlsy 登录/课表/任课老师 + wgyreport 成绩图片 FNV-1a 识别）
    OtherExperimentSession.ets # 其他实验（sysj OAuth 六步链 + 25 周课表解析合并）
  nav/
    AppNav.ets              # 全局 NavPathStack 持有者
  preference/
    PreferenceService.ets   # @ohos.data.preferences 同步封装
controller/
  GlobalTimerController.ets # 整分对齐定时器（AppStorage nowTick，日程实时切换驱动源）
  SemesterController.ets    # 学期较新者生效 + 变更清课表/考试缓存
  ClassTableController.ets  # 缓存回放/周次计算/某日课程聚合（AppStorage classTableVersion 驱动）
  ExamController.ets        # 考试分组/倒计时/examsOfDay 换算（AppStorage examVersion 驱动）
  ScoreController.ets       # 成绩汇总统计（学分/平均分/绩点，排除规则照搬）/学期筛选/详情桥
  EnergyController.ets      # 电费快照 + 本地余量历史（同日去重/15条上限）+ 低电量阈值
  SchoolnetController.ets   # 校园网双数据线（在线信息/自助服务用量）+ 验证码回调桥
  HomepageController.ets    # 首页聚合（课程+考试日程/21:25换天/过滤已结束/refreshAll 并行刷新）
  DormWaterController.ets   # 水机设备列表内存态（dormWaterVersion）+ 登录态变更信号
  SportController.ets       # 体育双数据线内存缓存（sportVersion）
  LibraryController.ets     # 借阅列表内存态（libraryVersion）+ 检索/筛选项桥
  ExperimentController.ets  # 实验 双源缓存（experimentVersion）+ 学期切换清缓存/清密码钩子
theme/
  AppTheme.ets              # default/green/orange 种子色 + 深浅色 token（保存时 bump themeVersion）
utils/
  Log.ets                   # hilog 封装
  charset/CharsetDecoder.ets# TextDecoder utf-8/gbk/gb18030/big5
  crypto/CryptoUtil.ets     # MD5 / AES-CBC(NoPadding|PKCS7) / RSA-PKCS1 / Base64 / PKCS7
  date/DateUtil.ets         # Dart 对齐的日期工具（解析/格式化/weekday/截断整除）
  html/HtmlParser.ets       # 自研 DOM 子集 + 选择器（tag/#id/.class/[attr=v]/后代组合器）
  media/ImageHasher.ets     # 成绩图片 50×20 像素 FNV-1a 哈希（RGBA/BGRA 适配）
  net/UrlUtil.ets           # host/path/scheme/重定向解析/formEncode 纯函数
```

## 测试

- `entry/src/ohosTest/ets/test/`：CryptoCharset（MD5/AES NIST 向量/PKCS7/Base64/GBK）、HtmlParser（7 例）、NetUtil（formEncode/重定向/Cookie），真机运行。
- 编译门禁：`hvigorw assembleHap -p module=entry@ohosTest`（比 @default 覆盖测试代码，更严）。

## 待办（阶段 3 修订版，详见 PORTING_PLAN.md §5）

~~M1~M5 框架/课表/考试/首页/设置~~ ✅ / ~~M6 成绩~~ ✅ / ~~M6 电费~~ ✅ / ~~M6 校园网~~ ✅（真机验证：电费与校园网需校园网环境；其余待学校发布课表后一并做）→ 五功能（图书馆/空教室/水机/物理实验+其他实验/体育）已于 2026-09-07 完成原生迁移并进全部功能页 → 剩余模块：一卡通→考勤；睿思论坛/猪图鉴赏已放弃移植。五功能待校园网/真实账号真机验证。
