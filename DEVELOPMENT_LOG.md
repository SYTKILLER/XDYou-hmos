# DEVELOPMENT_LOG

> 鸿蒙移植项目（XDYou = Traintime PDA 移植版）开发日志。
> 格式：日期 · 变更原因 · 改动内容 · 涉及文件

---

## 2026-06-18 · 只读调研完成，输出移植方案

- 原因：开源 Flutter 项目 `traintime_pda-1.6.2`（西电个人数据助手）需移植为鸿蒙原生 ArkTS/ArkUI 应用，本日完成只读调研与 API 映射验证。
- 改动：产出 `PORTING_PLAN.md`（移植方案总纲）；创建本日志。
- 调研结论要点：
  - 源项目 265 个 Dart 文件 / 45,749 行，page 140 文件（UI 重写工作量最大）。
  - 用 harmonyos-knowledge 技能（T1+T2）验证关键 API：`@kit.CryptoArchitectureKit`（AES-CBC/RSA/MD5）、`@ohos.util.TextDecoder`（**原生支持 gbk/gb18030**，风险解除）、`@ohos.net.http`（无 followRedirects → 手动重定向，与源项目一致）、`@ohos.data.preferences`、`@ohos.notificationManager`+`@ohos.reminderAgentManager`、`@ohos.calendarManager`、`@ohos.file.picker`、Scan Kit `scanBarcode`、`@ohos.promptAction`。
  - 核心技术事实：IDS CAS 登录（hidden form + `pwdEncryptSalt` AES-CBC 固定前缀/固定 IV + 手动 PKCS7）、滑块验证码（smallImage 末 16B 为 AES key，自带 manualSolver 人工分支）、Cookie 需自研容器持久化。
- 涉及文件：`PORTING_PLAN.md`（新增）、`DEVELOPMENT_LOG.md`（新增）。

## 2026-09-05 · 阶段 0/1：环境基线 + 基础设施

- 阶段 0：hvigorw assembleHap 基线 BUILD SUCCESSFUL（13.9s）；PORTING_PLAN.md 修订为 1.6.4 基线并修正重定向/代理提醒两处错误；建立项目记忆 AGENTS.md 与 NOTICE.md。
- 网络尖兵定案：`@ohos.net.http` 在 maxRedirects:0 时对 302 reject 2300047（d.ts 证实），无法实现 dio 式手动重定向；**改用 rcp（@kit.RemoteCommunicationKit）`autoRedirect:false`** 作为网络层。
- 新增基础设施（entry/src/main/ets/）：
  - `utils/Log.ets`（hilog 封装）
  - `utils/charset/CharsetDecoder.ets`（TextDecoder utf-8/gbk/gb18030/big5）
  - `utils/crypto/CryptoUtil.ets`（MD5、AES-CBC NoPadding/PKCS7、RSA-PKCS1、Base64、手动 PKCS7）
  - `utils/html/HtmlParser.ets`（自研 DOM 子集解析器 + 选择器：tag/#id/.class/[attr=v] + 后代组合器）
  - `utils/net/UrlUtil.ets`（host/path/scheme/重定向解析/formEncode 纯函数）
  - `service/network/CookieContainer.ets`（自研持久化 Cookie 容器，RFC6265 简化匹配）
  - `service/network/NetworkSession.ets`（rcp 封装：UA/超时/手动重定向/Cookie 注入回收/GBK 解码）
  - `service/SessionManager.ets`（ids/schoolnet/sport/general 四存储 + preferences 持久化）
  - `service/preference/PreferenceService.ets`（preferences 同步封装）
  - `theme/AppTheme.ets`（default/green/orange 种子色 + 深浅色 token，搬运 FlexColorScheme 生成值）
  - module.json5 增 INTERNET/GET_NETWORK_INFO 权限；EntryAbility 初始化偏好与色彩模式
- 设备对拍单测（entry/src/ohosTest/ets/test/）：MD5/AES NIST 向量/PKCS7/Base64/GBK 解码/HTML 解析/Cookie 匹配/重定向解析，待真机运行。
- 教训：`-p module=entry@ohosTest` 可编译主代码+测试代码，比 `entry@default` 更严，纳入每阶段编译门禁；TextEncoder.encodeIntoUint8Array 需双参返回 Info 对象，改用 encode()。

## 2026-09-05 · 阶段 2：IDS 登录闭环（代码完成，待真机验收）

- 精读 Dart 源：ids_session.dart / slider_captcha_client.dart / network_client.dart / ids_fingerprint.dart / login_window.dart / jc_captcha.dart / preference.dart，协议逐字节提取（AES 固定前缀+固定 IV、滑块 key=小图末 16B、form#continue 续跳、30 跳上限、UA 与 ehall 专用头）。
- 新增 service/ids/：IdsCrypto（两类 AES 加密+指纹）、SliderCaptchaClient、SliderCaptchaHandler、IdsSession（login/checkAndLogin/followRedirects/checkWhetherPostgraduate，串行锁）、CaptchaCoordinator。
- 新增 pages/：LoginPage、SliderCaptchaPage（PanGesture 采轨迹 ≥20ms/≥2px）、HomePage 占位、Index 改为 Navigation 根（登录态分流）。
- AppNav 全局 NavPathStack；NetworkSession UA 对齐 Dart（Chrome/130 + XDYou/2.0.0）；AppTheme 种子色改为 int 索引（对齐 Dart color 偏好）。
- 登录成功链路：清 ids Cookie → login（滑块人工）→ 存账号/Cookie → checkWhetherPostgraduate(role) → AppStorage isLoggedIn=true → 首页。
- 与 Dart 的偏差（记录）：reAuth 短信二次认证暂以 LoginFailed 提示「暂不支持」；滑块仅人工分支；学期信息拉取随阶段 3 课表模块接入。
- 编译门禁 @ohosTest BUILD SUCCESSFUL。

## 2026-09-05 · 编译门禁确立 + call-signature 违规修复

- 原因：用户约定「每次修改必须 build 无 error 后才允许完成任务」，门禁已写入 AGENTS.md §2；执行首轮编译即暴露 3 处 arkts-no-call-signatures error。
- 改动：`SliderCaptchaHandler`、`LoginProgressCallback` 由带调用签名的 interface 改为 `type` 函数别名（调用处零改动）；NOTICE.md 记录该语法禁区。
- 涉及文件：`service/ids/SliderCaptchaHandler.ets`、`service/ids/IdsSession.ets`、`NOTICE.md`、`AGENTS.md`。
- 结果：assembleHap（entry@default）BUILD SUCCESSFUL（1.9s），0 error / 36 warn。

## 2026-09-06 · UI 规范化重构：语义色板 + 深浅色跟随 + 控件规格统一

- 原因：页面可读性差——4 个页面全部硬编码 `AppTheme.xxx(false)`（永不跟随深色模式）、正文灰 `#808080` 对比度仅约 3.5:1（低于正文 4.5:1 门槛）、宽度 86% 与间距/圆角各自为政、滑块页硬编码绿色在深色下对比度不足。按《UI开发规范》整改。
- 语义色板：`resources/base/element/color.json` + `dark/element/color.json` 新增 token（app_bg / app_card / text_primary / text_secondary / divider / error / on_error / slider_track_rest / slider_track_active），对比度核算：正文浅色 ≥5.9:1、深色 ≥7.0:1（>4.5:1），error/标题类 >3:1；页面经 `$r('app.color.*')` 引用，深浅色自动切换，零状态管理。
- 深浅色状态：EntryAbility 启动时用 `resourceManager.getConfigurationSync()` 解析生效 colorMode 写入 AppStorage `'isDark'`，`onConfigurationUpdate` 随系统/偏好变更同步；页面 `@StorageProp('isDark')` 仅用于种子色相关（primary/onPrimary），静态色一律走资源。
- 控件规格：输入框/按钮统一高 50、水平 padding 16、按钮圆角 12、基础间距 16 / 模块间距 24、登录按钮禁用态 `opacity(0.6)`；废弃 86% 宽度写法，改根容器 padding 16。
- AppTheme 精简：删除与资源重复的静态色助手（background/card/textPrimary/textSecondary/divider/error），新增 `onPrimary(isDark)`（深色下主色变浅，按钮文字用深藏青 #00325B，白字对比度仅 2.1:1 不达标）。
- 滑块页：轨道/箭头/手柄改语义资源色（rest 浅灰、active 绿），手柄底色跟 app_card；错误文案走 error 资源；重试按钮改用 `login_try_again` 资源文案（原硬编码「重试」），并补足 50 高/12 圆角。
- 编译门禁：entry@default 与 entry@ohosTest 均 BUILD SUCCESSFUL，0 error。

## 2026-09-06 · 补齐 IDS 短信二次认证（reAuth）完整链路

- 排查结论（对照 Dart ids_reauth_client/ids_reauth_dialog/ids_auth_protocol）：阶段 2 缺失三步验证中的短信环节——changeReAuthType/getDynamicCodeByReauth/reAuthSubmit 三接口、重定向每跳的 reAuth 拦截、取消/过期清 Cookie、发送倒计时与信任设备 UI、activeIDSReAuthHandler 全局句柄。
- 新增 service/ids/IdsAuthProtocol.ets（isReAuthLocation/parseSmsDelivery/parseReAuthSubmit/掩码手机号/五类错误类）；service/ids/IdsReAuthClient.ets（prepare：GET 挑战页→指纹→切短信类型；sendSms：含 code_time_fail 已发送态；submitSms：skipTmpReAuth 信任设备→换取票据 URI）。
- IdsSession.ets：resolveReAuthIfNeeded 接入 completeRedirect 与 followRedirects 每跳；独立 reAuth 串行锁（与登录锁分离，允许嵌套）；取消/过期清 ids Cookie；login/checkAndLogin/checkWhetherPostgraduate 透传 reAuthHandler；setActiveReAuthHandler 供阶段 3 刷新复用。
- 新增 pages/ReAuthDialog.ets（@CustomDialog 规范模式：验证码输入、重发倒计时 setInterval、notice+掩码手机号、信任设备 Checkbox、取消/确认；拒绝→清空行内报错；过期→关闭并上报）+ ReAuthCoordinator（solve/finishWithUri/finishCancelled/finishExpired）。
- LoginPage.ets（保留用户自定义样式）：组装 reAuthHandler（关/开进度条）、错误映射补三类、成功后 setActiveReAuthHandler。
- 编译门禁 @default 与 @ohosTest 均 BUILD SUCCESSFUL。

## 2026-09-06 · 滑块自动求解器移植（根因修复）

- 排查链：真机日志 → Node 复现官方 encrypt.js + 滑块协议 → 图像分析（NCC+暗区）+ 小数步进扫描 → 两次 success → 测定服务端容差 |m−X|<0.5 → 定性：人工整数提交命中概率极低，必须自动求解。
- 新增 utils/codec/PixelBuffer.ets（base64→RGBA 像素，Image Kit 链路）；service/ids/SliderAutoSolver.ets（solveOffset NCC 列滑动窗口 + generateTracks S 形轨迹，逐行移植 Dart）。
- SliderCaptchaClient：存解码后 RgbaImage；新增 solveWithAuto（6 轮 × ±1/2/3/4 穷举 + 拟人延时），失败降级 CaptchaCoordinator 人工页（Dart manualSolver 兜底对齐）。
- LoginPage captchaHandler 改走 solveWithAuto；新增 CaptchaSolveFailedError 错误映射。
- TrackPoint/SLIDER_* 常量迁移至 SliderAutoSolver（消除循环依赖），SliderCaptchaPage 同步改 import。
- 编译门禁 @ohosTest BUILD SUCCESSFUL。待真机验证自动求解通过率。

## 2026-09-06 · 滑块诊断增强 + 双路径交叉验证

- 同网络原项目可登录（排除风控）；Node 同协议可成功、App 必败 → 差异锁定在 App 侧 Cookie 内容或 NCC 输出。
- 诊断增强：updatePuzzle 打印实际 Cookie 串全文与各 Cookie 名（长度）；solveOffset 返回 SolveResult{offset,ncc} 并入日志（NCC 峰值 0.7~0.95 为正常，异常低说明解码/匹配层损坏）。
- verify 补齐 Dart 原版 access-control-allow-origin 请求头（字节级对齐）。
- 新增明文路径 verifyPlain（libxduauth 策略：canvasLength+moveLength，无 sign 无 tracks）；solveWithAuto 轮次 0-2 走 sign、轮次 3 走明文——若明文成功而 sign 失败即锁定 App 加密/密钥层问题。
- 编译门禁 --no-daemon @ohosTest BUILD SUCCESSFUL。

## 2026-09-06 · 滑块匹配公式根因修复（最终定案）

- 用户日志实锤：ncc=3.920/1.735/2.076——归一化互相关上界为 1，>1 说明公式错误；offset 四轮散乱（0.84/0.22/0.38/0.78）。Cookie 串四段齐全（含 MULTIFACTOR_BROWSER_FINGERPRINT），Cookie/会话假设排除；明文路径同败与位置检测失效一致。
- 根因：Dart _imageNcc 名为 NCC 实为斜率公式 Σ(w·t)/Σ(w²)，平坦窗口分母趋 ε 时产生虚假峰值，匹配位置散乱导致 42 连败。
- 修复：改为严格归一化 NCC Σ(w·t)/sqrt(Σw²·Σt²)（templateSqSum 随模板构建累计），峰值回到 0.7~0.95 区间（与 Node 实验一致）；DELTAS 窗口 -6..+10 维持不变。
- 编译门禁 --no-daemon 双目标 BUILD SUCCESSFUL。

## 2026-09-06 · 人工滑块页修复（复用求解能力）

- 定量分析：人工页 dx = X − px0×(44/93) ≈ X − 0.47（系统性左偏，piece PNG 内容起于 x=1），叠加 |m−X|<0.5 容差与逐次换图 → 裸人工提交必败。
- SliderCaptchaClient 新增 verifySweepFromCurrent(mode)：当前验证码上 NCC+DELTAS 穷举（sign/plain 双路径）。
- SliderCaptchaPage.finishDrag 重构：释放后先 sign 穷举 → plain 穷举 → 最后才提交用户原始轨迹；成功即回登录取结果。
- 编译门禁 --no-daemon @ohosTest BUILD SUCCESSFUL。

## 2026-09-06 · 滑块最终根因落码（convertKey）+ 明文路径证伪删除

- 用户 14:53 真机日志仍全败（errorCode:0）→ 复查发现上一轮定位的 `generateSymKey()` 随机密钥问题一直未落码，CryptoUtil 四处原样。
- 重建协议 oracle（`.debug/slider_oracle.py`，Python+PIL+pycryptodome 直连，NIST 向量自校验）：**sign 路径 errorCode=1 成功**（baseMove=81，delta=+2，ncc=0.985，协议/单位换算/严格 NCC 几何全部验证正确）；**明文路径 5 发全败**——服务端不接受无 sign 表单。
- 修复：CryptoUtil 四处 `generateSymKey()` → `convertKey({data:key})`（encrypt/decrypt × NoPadding/PKCS7，同时修复登录密码加密 encryptIdsPassword）；删除 verifyPlain、solveWithAuto 轮次 3 明文分支、人工页 plain 穷举阶段（verifySweepFromCurrent 去掉 mode 参数）。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（20s）。待真机验证：自动求解应 1-2 轮内通过；ohosTest NIST 向量用例此刻应转绿（此前从未真正通过过）。

## 2026-09-06 · 真机滑块通过 + reAuth 短信弹窗挂死修复

- 真机重装修复包后完整时序（hilog 实录）：滑块 round0 NCC ncc=0.982，穷举第 4 发 moveLength=129 命中 {"errorCode":1,"errorMsg":"success"}，convertKey 修复端到端生效；凭据 POST 返回 302（账密被 CAS 接受）。
- 卡死根因：302 Location 指向短信二次认证（三步链 密码→滑块→短信），ReAuthCoordinator.solve() 返回永远 pending 的 Promise，设计上由 LoginPage 打开 ReAuthDialog，但 reAuthDialogController 创建后从未调用 .open() → 登录链路无超时无报错悬死，用户侧表现为"页面卡死"。
- 修复：LoginPage reAuthHandler 打开对话框（controller 空值防护抛 IdsReAuthCancelledError + Log.info 打点）；编译门禁 --no-daemon BUILD SUCCESSFUL，已装真机。
- 另证：SystemWatchParameter 两行＝图形子系统噪音，与本应用无关；ohosTest cryptoCharsetTest 真机 7/7 通过（NIST 向量首次真正转绿）；测试模块 entry_test 用后已卸载（其 TestAbility 残留前台曾造成"Hello World 空白页"假象）。

## 2026-09-06 · 登录全链路真机打通（收尾确认）

- 真机实录：滑块 round0 第 4 发命中（本轮图 500x332，ncc=0.598 偏低但 ±4 窗口仍命中）→ reAuth 弹窗正常打开（LoginPage.open() 修复生效）→ sms delivery success → 用户输入验证码提交 → followRedirects 进入 yjspt 跳转链 → 登录完成。
- 确认验证码图尺寸逐张可变（590x360 与 500x332 并存），NCC 按解码自然尺寸计算是正确设计，无需改动。
- 登录三步链（密码→滑块→短信）端到端可用；.debug/ 留有协议 oracle 脚本与 hilog 取证文件。

## 2026-09-06 · 阶段3 M1：登录后三 Tab 悬浮底栏框架（含计划修订）

- 计划修订（PORTING_PLAN.md §5 阶段 3 重写，用户确认）：登录后框架改为**三页签**（首页/全部功能/设置，悬浮毛玻璃底栏），替代五 Tab 方案；**睿思论坛、猪图鉴赏（Pig）放弃移植**；UI 按鸿蒙设计语言重设计不复刻 Flutter 布局，数据逻辑与原版对齐；关键 API 逐一核实 SDK d.ts（Swiper@7/Refresh@8/ListItemGroup@10/SymbolGlyph@11/backgroundBlurStyle@11/COMPONENT_THICK@12/expandSafeArea@11/setWindowBackgroundColor）。
- 新增 pages/home/：HomePageView（Swiper 3 页 keep-alive + 悬浮底栏 backgroundBlurStyle(COMPONENT_THICK) 毛玻璃 + 选中胶囊 primaryContainer + SymbolGlyph house/square_grid_2x2/gearshape）、HomeTab（日期头 + 日程/考试占位卡，M4 接真实数据）、AllFeaturesTab（入口注册表 Grid + 空态）、SettingTab（首字符头像账号区 + showAlertDialog 确认退出登录）、HomeLayout（TAB_BAR_CLEARANCE）。
- 沉浸融合：EntryAbility 新增 applyWindowBackground()——主窗口背景设为 app_bg 同值深浅色（'#F7F8FA'/'#121316'），onConfigurationUpdate 时跟随切换，安全区与页面背景无缝。
- 删除 pages/HomePage.ets 占位（引用仅 Index.ets，连带清理 home_placeholder_title/home_logged_in_as 字符串，新增 tab_* 等 15 条字符串资源）。
- 踩坑两条已记 NOTICE.md：@Builder 调用返回 void 不可链式属性；Stack alignContent 须写全 Alignment.Bottom。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。

## 2026-09-06 · 悬浮页签改用官方 HdsTabs + 阶段3 M2：学期与课程表模块

- **悬浮页签官方化（用户指正）**：HomePageView 从自绘 Stack+Row 底栏改为官方 `@kit.UIDesignKit` 的 **HdsTabs**——`barOverlap(true)` 页签叠加内容 + `barFloatingStyle.systemMaterialEffect`（hdsMaterial.MaterialType/MaterialLevel.ADAPTIVE 自适应材质，**@since 6.1.0(23)**，d.ts 核实）实现沉浸光感；页签图标用 TabBarSymbol（normal/selected 双 SymbolGlyphModifier）承载 HarmonyOS Symbol。d.ts 同时证实：tabs.d.ts 中 @23/24 新增是 onContentDidScroll/nestedScroll，悬浮材质本体在 HMS hdsBaseComponent.d.ets。
- **M2 学期+课程表**（对应 Dart classtable_session 28.5KB / semester_session / classtable_controller 全量移植）：
  - model/：ClassTableData（ClassDetail/TimeArrangement/ClassChange，缓存 JSON 字段名与 Dart json_serializable 一致）、TimeList（22 节次）、HomeArrangement、FetchResult、DateUtil（Dart weekday/inDays 截断语义对齐）。
  - service/ids/：SemesterSession（ehall dqxnxq / yjspt getUserInfo 双链路）、ClassTableSession（本科 ehall cxjcs+xskcb+cxxsllsywpk+xsdkkc 全链；**调课/停课/补课合并算法逐行照搬**，含 cache 跨条目配对与无进展 break；研究生 yjspt queryRcap 反推开学日 + 连续节次合并；失败回退 ClassTable.json 缓存）、BackgroundSlider（后台续登仅自动求解不弹人工页）。
  - controller/：SemesterController（学期较新者生效，变更清缓存）、ClassTableController（缓存回放/周次计算 termStartDay+7×weekSwift/getArrangementOfDay 课程聚合，AppStorage classTableVersion 驱动 UI）。
  - pages/classtable/ClassTablePage：周视图 Grid（节次×周一~周日，GridItem 跨节 rowspan、今日列高亮、8 色课程色板 base/dark 双份）+ 周次 Select/箭头切换 + 手动刷新 + 缓存/加载/错误态；注册 NavDestination 'classTable'，全部功能页首枚入口（graduationcap_fill）。
  - 基础设施：AppContext（UIAbility 上下文持有者，cacheDir 文件缓存读写）+ EntryAbility 注入。
- 已知简化：未移植 Dart SingleFlight/_isLatestRequest 过期丢弃（控制器 in-flight 去重替代）；补课条目未从 toDeal 移除的 Dart 原样 quirk 保留（首页 Set 去重兜底）。
- 新坑记 NOTICE.md：@kit.CoreFileKit 导出名是 fileIo（fs 不可用）；OpenMode 截断枚举叫 TRUNC；interface 内嵌套匿名对象类型禁用（须具名）；对象字面量不可传给 Map 形参。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。待真机：登录后打开课程表拉取、周次正确性、调课显示。

## 2026-09-06 · 阶段3 M3：考试安排模块

- model/exam/ExamData：Subject（时间正则解析：本科 "2025-1-10 14:00-16:00" / 研究生 "2025-01-10 星期五(14:00-16:00)"，Dart 命名组改编号组规避 groups 字符串下标禁区；解析失败置哨兵 "cancel_exam"）、ToBeArranged、ExamData（缓存 JSON 与 Dart json_serializable 字段一致）。
- service/ids/ExamSession：本科 ehall wdksap.do + cxyxkwapkwdkc.do（注意 dio queryParameters 是拼 URL 查询串，ArkTS 同样拼 URL）；研究生 yjspt wdksxxcx.do（querySetting JSON 过滤 SFFBKSAP=1 + pageSize 1000）；失败回退 exam.json 缓存。
- controller/ExamController：分组语义照搬（isDisQualified 时间解析失败 / isFinished 已开考含进行中 / isNotFinished 未开考升序）+ examsOfDay 换算 HomeArrangement（M4 首页聚合用）；SemesterController 学期变更时同步清 exam.json 缓存。
- pages/exam/ExamPage：鸿蒙原生分组卡片列表（未开考·最近一场倒计时高亮带主题色描边 / 已结束·弱化 / 时间待定·原始时间串 / 待安排课程），缓存/加载/错误态；NavDestination 'exam' + 全部功能页入口（doc_text_badge_clock）。
- 新坑：RegExpExecArray 不能赋给 RegExpMatchArray 变量（arkts-no-structural-typing），exec 结果统一用 RegExpExecArray 类型。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。待真机：考试列表拉取与时间解析（学校未发布课表，与 M2 一并延后真机验证）。

## 2026-09-06 · 阶段3 M4：首页聚合（今日日程 + 考试卡片）

- controller/GlobalTimerController：整分对齐定时器（下一整分 +100ms，照搬 Dart GlobalTimer），每分钟写 AppStorage 'nowTick'（毫秒时间戳）；poke() 供 EntryAbility.onForeground 回前台立即补算。
- controller/HomepageController：聚合 = 课程（ClassTableController.getArrangementOfDay）+ 考试（ExamController.examsOfDay）升序；换天阈值 21:25（isTomorrow 明天不过滤，今天过滤 endTime≤now——"结束即切下一条"）；头部文案"今天还有 N 件事/明天有 N 件事/今天已结束"照搬；refreshAll = 学期一次 + 课表/考试并行（Promise.allSettled，单源失败不阻断另一源），AppStorage homepageVersion 驱动。
- 控制器重构：ClassTableController/ExamController 拆出 refreshData()（不含学期同步，首页并行用）；SemesterController.ensureSemester 加 in-flight 防并发重复拉取。
- pages/home/HomeTab 从占位改为真实聚合视图：Refresh 系统下拉刷新 + 头部（日期·周次/假期中）+ 今日日程卡（时间轴样式：左时间/中状态点/右课程考试信息，进行中整行 primaryContainer 高亮+"进行中"标记，结束时刻由 nowTick 驱动 1 分钟内自动切换）+ 考试安排卡（未结束升序提前展示，最近一场倒计时加粗）；卡片点击跳转课程表/考试页。
- HomePageView aboutToAppear：启动定时器 + 静默全量刷新（对应 Dart refreshAtStart）。
- 自定义事项/物理实验/其他实验聚合暂未并入（对应源后续里程碑），架构已按可插入设计。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。

## 2026-09-06 · 阶段3 M5：设置页完善（账号区/平台账号/偏好/关于）

- 账号区昵称"尽力获取"落地：研究生 SemesterSession 从 getUserInfo.do 响应 data 中 best-effort 提取 xm/name 写入 'displayName' 偏好（协议响应无该字段则不动）；本科当前协议无姓名来源，回退学号显示（M6 校园网 real_name / 成绩接口响应再补）。头像用首字符生成。
- 平台账号管理：确认 Dart 校园网自助服务（zfw.xidian.edu.cn）协议＝用户名复用 idsAccount + 独立的 schoolNetQueryPassword（校园网查询密码）→ 设置页「校园网自助服务」条目 + SchoolnetPasswordDialog（@CustomDialog 规范：controller 可空/autoCancel，TextInput Password 输入，保存/清除经 settingsVersion 通知刷新）。密码明文存 preferences（与原版 SharedPreferences 一致，后续可评估 asset store 加固）。
- 偏好：主题种子色 Select（默认/绿色/橙色）+ 深浅色 Select（跟随系统/浅色/深色）。AppTheme.saveSeedIndex/saveDarkMode 现在同时 bump AppStorage 'themeVersion'——种子色是方法调用读取，必须状态变化触发各页重建；深浅色经 ApplicationContext.setColorMode → onConfigurationUpdate → isDark 全局跟随（含窗口背景）。HomePageView/HomeTab/ExamPage/ClassTablePage/SettingTab 均订阅 themeVersion。
- 关于：版本号 bundleManager.getBundleInfoForSelfSync（@20，d.ts 核实）.versionName。
- SettingTab 迁移 pages/home/ → pages/setting/（与弹窗同目录），HomePageView 引用同步；AppContext 增设公共 applicationContext() 访问器。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。阶段 3 主体框架（M1~M5）全部完成，剩 M6+ 逐模块迭代。

## 2026-09-06 · 阶段3 M6 首模块：成绩查询

- model/score/ScoreData：Score（scoreTypeCode 1/3=三级、2=五级、0=百分制；scoreStr/gpa 映射照搬 Dart；isPassedStr ''=未出分）+ ComposeDetail + scores.json 缓存序列化（数组，字段与 json_serializable 一致）。
- service/ids/ScoreSession：本科 ehall cjcx/xscjcx.do（POST 表单体：*json=1 + querySetting(SFYX=1) + *order=+XNXQDM,KCH,KXH；注意此接口 data 是表单体而 exam 的 queryParameters 是 URL 串，按 Dart 原样区分）；研究生 yjspt wdcj/xscjcx.do；单科成绩组成 cxkckgcxlrcj.do（GCXKHLRCJGS 公式 split(/ \+ |\*| = /) 与 KCGCXKHLRCJ 明细配对，跳过"总评成绩"，占比换算改用四舍五入避免 Dart 的 30.000000000000004% 浮点尾数）；缓存先读后刷失败回退；响应含 XM 字段时尽力写 displayName（补本科生姓名来源）。
- controller/ScoreController：汇总统计（学分/加权平均分/加权绩点，排除规则照搬 _evalCount：CET-4/6、未出分、失败无分、重修失败）+ 学期去重列表 + getDetail（needRelogin=缓存回退时续登）+ detailTarget 弹窗参数桥。原版勾选课程自定义统计（isSelected）后置。
- pages/score/：ScorePage（汇总三格卡 + 学期 Select 筛选 + 成绩列表，不及格标红/未出分灰显，点击查看组成）+ ScoreDetailDialog（组成明细弹窗，加载态）；NavDestination 'score' + 全部功能页入口（doc_plaintext）。
- 老坑复发提醒：嵌套匿名对象类型再次踩中（NOTICE 已有记录），编码时 Datas/Section 一律先拆具名 interface。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。

## 2026-09-06 · 阶段3 M6 第二模块：电费查询（用户调整顺序：校园网后移）

- model/energy/EnergyData：MeterInfo（抄表记录）/EnergyInfo（快照：余量+上次抄表日+电表/水表列表）/ElectricityHistoryInfo（本地余量历史）+ 缓存序列化。
- service/ids/EnergySession（对应 Dart energy_session.dart 388 行，2026-04 新能耗系统 ignypt）：CAS → xxcapp oauth 续跳，落地 URL 取 code；每请求先 POST GetSignature 换 timestamp/signature 头（OpCode=MPAY）；业务参数 JSON + AES-128-CBC-PKCS7（key=iv="1234567812345678"，CryptoUtil.aesCbcEncryptPkcs7 直接复用）→ GET ?content= / POST JSON 体 {"content"}；链路 OauthGetUserInfo → H5UserIDLogIn（取 NodeID）→ H5QueryMeterList（电表下标：rows[0].MediumCode=='2'?0:1）→ GetMetRead（电近一月、水近一年失败留空）；DateUtil 新增 shiftMonths（Dart time 包 months 钳制语义）与 formatDash。
- controller/EnergyController：本地余量历史照搬（同日去重、上限 15 条、仅 fresh 追加）+ 低电量阈值（默认 20 度，偏好可关，M6 仅页面告警，提醒推送后置）+ energyVersion 驱动。
- pages/energy/ElectricityPage：剩余电量大卡（低于阈值红色+"请及时充值"）+ 近一月电表读数表 + 近一年水表（若有）+ 本地记录卡；错误态透传"仅校园网可用"；NavDestination 'electricity' + 全部功能页入口（bolt）。
- ⚠️ 待真机验证：ignypt 全链仅校园网可用；GET content 编码层次存疑（Dart dio 对已 encodeComponent 的值可能二次编码）——若请求失败优先试双重编码；AES 加密链已用 NIST 向量过的 CryptoUtil，风险低。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。

## 2026-09-06 · 修复设置-主题颜色切换失效 + 默认色改宇宙蓝

- 用户报告：主题色切换无效；主题色/深浅色两个 Select 无默认选中值。根因两个：
  1) `themeVersion` 版本号机制失效——各页 `@StorageProp('themeVersion')` 只声明、build 中从未读取（种子色经 AppTheme.primary(isDark) 方法调用读取偏好），ArkUI 依赖追踪下变化不触发任何 UI 更新，颜色重启才生效；
  2) `Select` 只设了 `selected` 没设 `value`——官方文档：selected 仅定菜单初始索引，按钮文本来自 value，选中菜单项后才自动更新，因此初始按钮空白。
- theme/AppTheme 重构：默认种子色 '默认'#3F5F90 → **'宇宙蓝' #0A59F7**（light），深色主色 #9FC9FF → **#5B96FF**（对 #00325B 容器 4.5:1、对深色背景 6.5:1，维持"深色下主色变浅"规范）；新增 `syncStorage()` 统一写 5 个 AppStorage 响应式键（themeSeedIndex/themeDarkMode/themePrimary/themePrimaryContainer/themeOnPrimary），saveSeedIndex/saveDarkMode 改调它，themeVersion 机制删除。
- EntryAbility：onCreate 首帧前 syncStorage 播种 token；onConfigurationUpdate 更新 isDark 后 syncStorage（深浅色翻转重算 token）。
- 全部消费页迁移（13 个）：SettingTab/HomeTab/HomePageView/AllFeaturesTab/ScorePage/ElectricityPage/ExamPage/ClassTablePage/LoginPage/SliderCaptchaPage/ReAuthDialog/ScoreDetailDialog/SchoolnetPasswordDialog——`AppTheme.primary(this.isDark)` → `@StorageProp` token（themePrimary/themePrimaryContainer/themeOnPrimary），直接引用建立刷新依赖；isDark/themeVersion @StorageProp 全部移除（EntryAbility 与 AppTheme 除外）；无用 import 清理。
- SettingTab 两个 Select：`.selected(响应式索引)` + `.value(当前选项文本)`（seedLabel/darkLabel，typeof 收窄 ResourceStr），初始即显示"宇宙蓝"/"跟随系统"。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error，18.4s）。

## 2026-09-06 · 全部功能子页白屏（exam/score/electricity/classTable）修复

- 症状：全部功能页四个入口（课程表/考试安排/成绩查询/电费查询）打开均为白屏（仅返回键、无标题），子页内按系统返回键直接回桌面；登录流程 sliderCaptcha（早期单分支时代）正常。
- 复现：真机断连，临时将 compatibleSdkVersion 降至 6.1.0(23) + Index 调试登录钩子，在 API23 模拟器上完整复现（白屏 + Back 回桌面）；hilog 抓到决定性日志 `AceNavigation: can't find name in config file: exam / load page failed / can't find target destination by index, create empty node`。
- 根因一：Index.pagesMap 写成多个独立 `if` 分支 → navDestination builder 整体解析失效，push 后创建空节点。修复：改 `if / else if` 链（课程表/考试/电费随即正常）。
- 根因二：ScorePage 成员初始化器 `new CustomDialogController({builder: ScoreDetailDialog()})` → ScorePage 实例化失败（aboutToAppear 不执行、无应用日志）仍白屏。修复：`dialogController` 改为 `| null` 延迟创建，onScoreClick 判空 new 后 open（成绩页恢复）。
- 模拟器回归：冷启动自动 push exam ✓、点击 classTable ✓、score ✓（延迟 dialog）、electricity ✓，白屏与返回键退应用均消失。
- 已还原临时改动（compatibleSdkVersion 6.1.1(24)、Index 调试钩子删除），--no-daemon 门禁 BUILD SUCCESSFUL（0 error）。待真机重连后安装验证。
- 新坑两条记 NOTICE.md（else-if 链强制、NavDestination 禁止初始化器创建 CustomDialogController）。

## 2026-09-07 · 成绩/考试页 "Unexpected Text in JSON" 根因修复（角色误判为研究生）

- 症状：成绩查询/考试安排页报 `SyntaxError: Unexpected Text in JSON: Invalid Token`；首页考试卡为空。真机复现抓日志定位：研究生判定 role=true 走 yjspt，模块 POST（wdcjapp/wdksapp/wdkbapp 的 *.do）被 wisedu 应用 ACL 以 **403 + HTML 错误页** 拒绝，`JSON.parse(HTML)` 即抛此错（非 302，不是登录失效）。
- 排障路径：真机 uitest 复现 + 分级诊断日志（status/落点/cookie 头）→ 发现"门户模块（yjsemaphome）200 JSON、其它应用模块 403"的应用级授权模式 → curl 带 CASTGC 真 ticket 逐字节重放（落地 200 + 新 _WEU）仍 403，排除请求构造问题 → 同一 Cookie 访问 getCanVisitAppList.do 返回 `{"res":null,"success":true}` → 对照 Dart 原版定位判定差异。
- **根因**：`IdsSession.checkWhetherPostgraduate` 的移植把 Dart `value.data["res"] != null`（判空）写成了 `parsed.res !== undefined`（判存在）。服务端对无研究生应用授权账号返回 `res` 字段存在但为 null——Dart 判定 false（本科，走 ehall，正常），移植版判定 true（研究生，走 yjspt 被 ACL 403）。该用户实为本科生。
- 修复：`isPostgraduate = parsed.res !== undefined && parsed.res !== null`；HomepageController.refreshAll 冷启动首次刷新前重判定角色一次（`roleRechecked` 进程级标记），自愈历史版本已写入的 role=true 偏好，失败不阻断刷新。
- 真机回归（33Z0224A22015449）：学期改走 ehall（`2026-2027-1`，格式与 yjspt `20261` 不同，SemesterController 正确识别变更并清缓存）；成绩页完整出列表（学分/平均分/绩点/课程）；考试页"待安排 · 4"正常；日志无 error。
- 顺手修复：pages/Index.ets 的 `aboutToAppear` 缺失收尾大括号（上次删除调试登录钩子时删坏，导致编译失败）。
- 编译门禁 BUILD SUCCESSFUL（0 error）。临时诊断代码与含 Cookie 的取证文件已全部清理。

## 2026-09-07 · 全部 Select 组件默认值/占位文本规范整治

- 全项目共 4 处 Select：课表页周次、成绩页学期筛选、设置页主题色/深色模式，逐一按配置表核对（`.selected(-1)`/省略＝空态须配 `.value('占位文本')`；`.selected(0)`＝默认选中第一项）。
- 判定：4 处均有恒有效的默认选中项（周次索引恒被 clampWeek 钳在 [0, len-1]、学期 0＝"全部学期"、主题设置项经 AppTheme.currentSeedIndex/currentDarkMode 钳制持久化），全部走"selected(有效索引) + .value(当前项文本)"组合，无需空态。
- 修复：课表页新增 weekLabel()、成绩页新增 semesterLabel() 并补 `.value()`（此前缺 value，按钮初始文本可能为空——selected 只定菜单高亮）；设置页 seedLabel()/darkLabel() 越界回退由返回 `''` 改为钳回首项（与 AppTheme.seedByIndex 回退一致），typeof 守卫兜底返回占位文案，杜绝空文本。
- 编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-07 · 电费页查询触发时机修复（进页必查 + 缓存先行）

- 问题：ElectricityPage.aboutToAppear 原逻辑为 `if (!hasData()) refresh()`——有缓存时进页只展示缓存、永不联网刷新，且页面无手动刷新入口，数据会一直陈旧（页面顶部"当前为缓存数据"提示形同虚设）。
- 修复：aboutToAppear 改为 loadCache() 后无条件 refresh()（NavDestination 每次 push 均新建实例，aboutToAppear 每次进入触发，Controller 的 inflight 去重防并发）；内容区 busy && hasData 时在缓存提示下新增一行 LoadingProgress + "正在刷新…"（新增 string electricity_refreshing），查询成功后数据与提示自动切换为 fresh（busy 切换驱动重建，EnergyController 静态量在重建时重读）。
- 对齐原版：Dart 版由 HomepageController.refresh 每次统一拉电费 + 卡片手动刷新按钮；移植版首页无电费卡，进页自动查询即等价语义。失败仍走 EnergySession 缓存回退，页面静默保留缓存展示。
- 编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-07 · 电费页"上次抄表"显示 [object Object] 修复

- 根因：RemainCard 里把 `$r('app.string.electricity_last_read')` 直接塞进模板字符串——`$r()` 返回 Resource 对象，不解析为文本，插值后变成 `[object Object]: 日期`（全项目 grep `\${$r(` 仅此一处）。
- 修复：改用 Text/Span 组合（Span 原生接受 Resource，样式继承父 Text）：Span(资源) + Span(`: 日期`)。
- 编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-07 · 成绩/考试/课表页查询触发时机统一修复（进页必查 + 缓存先行）

- 排查：全项目 grep loadCache-then-refresh 模式，发现与电费页相同的"仅无数据才查询"问题共 3 处——ScorePage、ExamPage、ClassTablePage 的 aboutToAppear 均为 `if (!hasData()) refresh()`，有缓存时进页永不联网刷新（成绩/考试页连手动刷新入口都没有，缓存提示形同虚设）。
- 修复：三页 aboutToAppear 统一改为 loadCache() 后无条件 refresh()；有缓存数据且 busy 时展示刷新中反馈——成绩/考试页在缓存提示下新增 LoadingProgress + "正在刷新…"小行，课表页在学期行内追加"正在刷新…"文本（其刷新按钮已有 opacity 反馈）。新增公共字符串 common_refreshing。
- 边界确认：refresh 成功后 busy 复位驱动重建重读 Controller 静态量；课表页刷新成功重算周次的逻辑在 aboutToAppear 自动刷新场景下无副作用（用户尚未切换周次）；冷启动 HomepageController.refreshAll 与进页刷新由各 Controller inflight 去重防并发。
- 编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-07 · 阶段3 M6 第三模块：校园网

- 编码前重读 NOTICE/AGENTS（用户要求）：确认后续会话已修复的三类坑（AppTheme token 化、pagesMap else-if 链、NavDestination 弹窗判空延迟创建）并全部沿用；本次新代码遵守 Select .value() 帮手、themePrimary/themeOnPrimary token、判空语义、具名 interface、resolve-only Promise 桥。
- model/schoolnet/NetworkUsage：GeneralNetworkUsage（IpUsageRow 显式化 Dart 三元组）+ CurrentUserNetInfo（Dart late 非空模型改全可选+默认值，error 非空按"未在线"呈现——离线响应字段不全时原版会崩，ArkTS 防御化）+ formatBytes；realName 顺带写 displayName（补本科生姓名来源）。
- service/schoolnet/SchoolnetSession（对应 Dart miscellaneous_session/schoolnet_session.dart 307 行全量移植）：
  - rad_user_info JSONP（general 会话，去头去尾解析照搬）；
  - zfw 自助服务：/home 未重定向直接抓取 → 重定向走登录链（/login 提取 csrf+RSA 公钥 → 验证码 refresh=1+抓图 → UI 回调输验证码 → RSA-PKCS1 加密密码（PEM→DER→convertKey，位长按 DER 长度 1024/2048 启发）→ /site/validate-user 校验（用户名/密码错误不再重试）→ POST /（_csrf-8800 字段名照搬）→ /home 抓取）；
  - HTML 解析照搬：tr 7td=设备行(ip,在线时长,流量)、tr 4td=用量行且跳过含 联通/移动/电信 的运营商行；失败/验证码放弃/网络异常回退内存缓存（密码错误/未配置不回退）。
- controller/SchoolnetController：双数据线独立 inflight + schoolnetVersion 驱动；验证码经 SchoolnetCaptchaHandler（type 别名）由页面承接。
- pages/schoolnet/SchoolnetPage：在线信息卡 + 自助服务三格（已用/剩余/结算日）+ 在线设备列表；验证码为内联卡片（Image data URL 按魔数分 jpeg/png + TextInput + 换一张/取消/确认），Promise 桥只存 resolve；密码未配置给设置页指引；schoolnet 会话登录后 SessionManager.save 持久化。
- UI 独立重构确认：不照抄原版 WebView/表单页，按现有卡片体系 + token 主题实现。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。待真机：需校园网环境验证 rad_user_info 与 zfw 登录链（验证码图显示、RSA 加密、会话 Cookie 保持）。

## 2026-09-07 · 校园网页崩溃修复（验证码 Uint8Array 进 @State）

- 真机 jscrash：点击校园网入口，验证码分支首帧渲染时 `base64Encode` 收到 length 0 的 Uint8Array（"must be Uint8Array and the length greater than zero"，error 401），栈指向 build→captchaDataUrl→encodeToStringSync。
- 根因：`@State captchaBytes: Uint8Array` 承载 TypedArray——不在 ArkUI @State 支持的观测类型清单内，赋值非空但渲染读到空数组；且 build 里每次 rerender 都重复 base64 转换。
- 修复：@State 改存 `captchaDataUrlStr`（data URL 字符串，按魔数分 jpeg/png）；转换移到赋值处（handler 与"换一张"回调），带空字节守卫（空则 abortCaptcha 按放弃处理回全会话）；build 只读字符串。rcp Response.body 类型已核实为 ArrayBuffer|undefined，会话层字节链无问题。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error）。教训已记 NOTICE.md。

## 2026-09-07 · 工具箱纯网址跳转功能移植（通用 WebViewPage，ArkWeb 应用内加载）

- 梳理原项目：简单网址跳转功能全部集中在 `page/toolbox/toolbox_page.dart`（7 个 WebViewAddresses 项，经 url_launcher 拉起外部浏览器）；其余 launchUrl 均为页面内联辅助（关于页链接/更新下载/QQ 群/文章外开），非独立功能。睿思论坛不纳入（用户确认；睿思导航 nav.xdruisi.cn 是独立导航站，予以保留）。
- 新增 pages/web/WebViewPage.ets：通用网页 NavDestination，`@kit.ArkWeb` Web 组件（zoomAccess/javaScriptAccess/domStorageAccess/fileAccess/darkMode(Auto)），参数经 pushPath param（显式类 WebNavParam{title,url}）+ onReady 取用；顶部线性进度条（loadProgress 0~100 显隐）+ 主框架加载失败错误卡（isMainFrame 过滤，重新加载按钮）；NavDestination.onBackPressed 优先 accessBackward 回退网页历史（try/catch 防 controller 未附着）。图标名经 SDK sysResource.js 符号表核对。
- AllFeaturesTab：FeatureEntry 增 url 字段；追加工具箱 7 项——缴费系统(creditcard)/订水系统(drop)/后勤报修(wrench_and_screwdriver)/空间预约(building)/网络查询(wifi)/物理计算(calculator)/睿思导航(compass)，url 非空时 pushPath webView 并传参，导航逻辑抽 openEntry 方法；Index.pagesMap 注册 webView（else-if 链）。
- 权限确认：module.json5 已声明 ohos.permission.INTERNET，无需改动。
- 编译门禁 BUILD SUCCESSFUL（0 error）。待真机：各站点 CAS 登录在 Web 内完成（与原生会话 Cookie 不互通，属预期）；空间预约为 http 明文站（API 18+ 默认放行）。

## 2026-09-07 · 校园网"在线信息"栏改造为原版"正在使用"（账户概览 + 流量使用情况）

- 原因：用户反馈"在线信息"栏（姓名/在线IP/套餐/累计流量/剩余）用处不大，要求换成原项目"正在使用-账户概览"内容并补"已使用流量"栏。对照原版 current_net_info_page.dart：账户概览＝账号/套餐类型/余额(¥)，流量使用情况＝进度条(已用%)+已使用流量/剩余流量/总流量（sum_bytes 口径，1000 进制）。
- model/schoolnet/NetworkUsage：CurrentUserNetInfo 补 `sumBytes`（解析 rad_user_info 的 `sum_bytes`，此前漏抓）+ `periodTotalBytes()`（sum+remain，原版同口径）；formatBytes 由 1024 改 **1000 进制**、正数两位小数（对齐原版 _formatBytes 与计费口径，唯一使用点在本页）。
- pages/schoolnet/SchoolnetPage：UserInfoSection 重构——区块标题改"正在使用"；在线时渲染：橙色提示条（数据口径说明，warning_* 色 token）+ 账户概览卡（账号 userName/套餐类型 productsName/余额 `¥xx.xx`）+ 流量使用情况卡（Progress 线性进度条 themePrimary + `已使用 x.x%` + 已使用流量/剩余流量/总流量三行）；离线/错误/加载态保持。姓名/IP/累计流量三行删除（realName 仍抓取用于 displayName 同步）；percent 计算经私有方法（@Builder 内禁声明变量）。
- 资源：string.json 删 schoolnet_real_name/schoolnet_ip/schoolnet_total_used，改 schoolnet_online_section="正在使用"、schoolnet_product="套餐类型"，新增 schoolnet_current_notice/schoolnet_overview/schoolnet_account/schoolnet_balance/schoolnet_usage_situation/schoolnet_used_traffic/schoolnet_total_traffic；color.json（base+dark）新增 warning_bg/warning_border/warning_text 三 token。
- 编译门禁 BUILD SUCCESSFUL（0 error，16.4s）。待真机：rad_user_info 的 sum_bytes 数值与进度条百分比展示。

## 2026-09-07 · 校园网页"一直正在查询"修复（成功路径无 @State 触发）

- 现象：用户打开校园网页，在线信息卡永久停在"正在查询…"。排查：NetworkSession 超时配置正常（连接 10s/传输 30s，请求必落定）；根因在响应式链——`loadUserInfo()` 成功路径只写控制器静态字段 + bumpVersion（AppStorage），页面无任何 @State 变化；`@StorageProp('schoolnetVersion') version` 声明后 build 中零引用，按 2026-09-06 教训不建立刷新依赖 → 数据到达 UI 不重渲染。失败路径（infoError @State）不受影响，故只坏成功分支。rad_user_info 离线时返回 error 载荷也走成功路径，未在线同样卡死。
- 修复：`loadUserInfo()` 补 `.then` 翻转 `@State infoLoaded`（与 ScorePage/HomeTab 的 busy/refreshing 同款已证范式：状态翻转强制重渲染，重渲染时重读 `SchoolnetController.hasUserInfo()`）；version 注释改为"仅作外部信号备用"，写明未读取不建依赖。
- 附带发现：rad_user_info 请求与 zfw 链路无时序耦合，此前仅当 zfw 先落定（触发重渲染）时在线信息卡才被顺带救回，时序相反即永久 loading——与用户"一直正在查询"吻合。
- 编译门禁 BUILD SUCCESSFUL（0 error，7.3s）。待真机：进页面后在线信息卡应在数秒内渲染（校园网环境）；未在线/离校应显示"当前未在线"或错误卡而非卡死。

## 2026-09-07 · 课表页只渲染出"节次"一格修复（GridItem 行列索引 0/1-based 错位）

- 症状：课表页第一周只看到"节次"两字，表头/时间行/课程格全部缺失；用户误报"课表没刷新出来"。数据链路实际正常（hilog 证明 ehall 四请求全通、缓存 ClassTable.json 内容正确，今日无课＝开学首日周一无排课属预期）。
- 取证：真机 uitest dumpLayout——"节次" Text bounds [27,552][1233,2696] 撑满整个 Grid 区域，其余 GridItem 全部不存在；学期行 2026-2027-1 正常。
- 根因：ArkUI GridItem 的 rowStart/rowEnd/columnStart/columnEnd 行列编号为 **1-based**，本页按 0-based 数据坐标直传（表头 row 0 / col 0）。rowStart(0) 非法 → 该格占满整个网格 → 其余 GridItem 与之冲突被布局引擎全部丢弃，仅剩"节次"。
- 修复：GridItem 修饰统一 +1（.rowStart(cell.row+1) / .rowEnd(cell.row+cell.rowSpan) / .columnStart(cell.col+1) / .columnEnd(cell.col+1)），cell 数据坐标保持 0-based 不动。
- 顺手修复（上轮排查确认的响应式债）：HomeTab 删除未被 build 读取的 @StorageProp('homepageVersion')，aboutToAppear 改为 refreshAll().then 翻转 @State silentRefreshed（SchoolnetPage 同款范式）——静默刷新完成后日程/考试卡立即重渲染，不再等下一个整分 nowTick；ClassTablePage 删除未被读取的 classTableVersion 声明（busy/errorMsg 翻转已覆盖渲染驱动），留注释说明。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error，8.1s）。待真机：课表页第 1 周应见"工程概论(IV) 周三 1-2 节 B-306"课程格 + 完整表头/时间行；首页静默刷新完成后日程卡即时更新。

## 2026-09-07 · 校园网页卡死二轮修复（ hdc 真机复现闭环）+ error 字段语义对齐原版

- 用户反馈仍卡"正在查询"。上轮修复（回调翻 infoLoaded）无效，且当时成功路径零日志、用户抓的 hilog 无应用域输出，无法定位。本轮给 SchoolnetController/SchoolnetSession 补 Log.info 观测（start/done/http码/关键字段），并 hdc 遥控真机全程复现：冷启→全部功能→校园网，`uitest dumpLayout` 定位入口、`uiInput click` 进页、`hilog -x -D 0xD001` 抓日志。
- 日志实锤：rad_user_info/zfw 两条请求 ~150ms 均成功落定、字段解析完整，但顶部卡仍转圈而 zfw 卡正常渲染 → 定位到真机制：**infoLoaded 只被赋值、未被任何 if 条件读取，不建立刷新依赖**（ArkUI 按节点依赖重渲染）；busy 因写在 UsageSection 条件里所以 zfw 卡能出。修复：数据分支条件改为 `infoLoaded && hasUserInfo() && userInfo()!==null`，aboutToAppear 按缓存命中预置 infoLoaded 防重进闪加载。
- 顺带发现并修正一处语义偏差：真机 rad_user_info 返回 error≠"ok" 但账号字段完整（手机 IP 会话与 PC 不同所致），原用 isOnline() 做闸门会永久显示"未在线"；核对原版 Dart——CurrentNetInfoPage 不校验 error、有数据即渲染。改为 userName 为空才显示离线卡，其余照常渲染。
- 真机验证截图通过：账户概览（账号/套餐/余额¥560.00）+ 流量使用情况（进度条/已使用 2.51TB·100.0%/总 2.51TB，remain=0 系融合套餐接口口径，与原版同公式）+ 自助服务卡全部渲染，无卡死。
- 编译门禁 BUILD SUCCESSFUL（0 error）。教训已更新 NOTICE.md（@State 须被条件读取 + hdc 遥控排障法）。

## 2026-09-07 · 课表表格塌陷根因修订（模板串 vp 单位）+ 表格布局重构

- 前条日志"GridItem 1-based 索引"结论**有误**，已修订。三轮真机对照实验（0-based 闭区间 / +1 / 线号语义）布局完全相同：Grid 下仅剩 1 个 GridItem 撑满全区域、ForEach 其余 item 不挂载——与行列号无关。静态 GridItem 对照 + 纯 fr 模板二分定位真正根因：**rowsTemplate/columnsTemplate 混入 '34vp'/'30vp' 固定单位导致网格解析塌陷**；改纯 fr 后网格立即建立（20 item 全渲染）。
- 重构 ClassTablePage 表格：表头行（节次+7 天，今日列高亮）与节次时间列移出 Grid，用 Row/Column + layoutWeight(1) 对齐实现；Grid 只放课程格（columnsTemplate 7×1fr、rowsTemplate 11×1fr）；行列号回归官方语义 rowStart(row)/rowEnd(row+rowSpan−1)（0-based 闭区间，单格 start==end）。CellSpec 删 kind/isToday 字段，GridCell 只留课程格分支。
- 真机回归（33Z0224A22015449）：表头/节次列/课程格全部正常渲染，"工程概论(IV) B-306"正确落在周三 1-2 节，截屏确认视觉无误。
- 编译门禁 --no-daemon BUILD SUCCESSFUL（0 error，7.9s）。NOTICE.md 已按正确结论改写。

## 2026-09-07 · 五功能完整迁移（实验信息 / 空闲教室 / 图书馆 / 体育信息 / 宿舍水机）

- **平台账号体系**（用户决策）：设置-平台账号新增 3 个入口——实验平台（ExperimentPasswordDialog）、体育平台（SportPasswordDialog，均克隆 SchoolnetPasswordDialog，账号=学号只读展示）、宿舍水机（dormWaterLogin 登录页，副标题脱敏手机号）。功能页未配置账号时**直接拉起对应登录界面**（共用同一对话框/页面组件），页内不保留登录入口；登录/保存后经 settingsVersion 刷新副标题并自动加载数据。新增偏好键 experimentPassword / sportPassword / dormWaterToken·Uid·Eid·Phone。
- **宿舍水机**（DormWaterSession + DormWaterPage + DormWaterLoginPage）：i.ilife798.com 手机号+图片验证码+短信码登录（sessionId 客户端自生成 16 位数字、验证码接口专用 UA），token 裸 Authorization；设备列表/扫码添加（Scan Kit startScanForResult，QR 校验 hnkzy.com 取末段）/开始出水确认+1s×60 轮询连续 3 次 status==99 判空闲/移除收藏。控制器内存态 + dormWaterVersion。
- **体育信息**（SportSession + SportController + SportPage）：SessionManager.sport() 独立 Cookie 域；RSA-PKCS1(2048 内嵌公钥) 加密密码 POST /h5/login（注意 dio Uri.resolve 落根路径）；每请求 channel/version/type/token/timestamp/sign(MD5 排序串)；401/402 或失效关键词自动重登重试一次；体测成绩（总览+年度明细）+体育课成绩（学期正则/星期映射照搬）；双页签页。打卡子功能原版已废弃不移植。
- **空闲教室**（EmptyClassroomSession + EmptyClassroomPage）：复用 IdsSession CAS 底座（后台滑块），ehall kxjas 三接口（楼栋/日期转周次/教室 JC1~JC11 含 "1_"=占用）；weekDaySetting 上游 bug 忠实复刻。页面：楼栋 Select（emptyClassroomLastChoice 记忆）+默认今天+名称过滤+11 节 4+4+3 方格。
- **图书馆**（LibrarySession + LibraryController + LibraryPage + BookDetailPage）：IDS→超星 CAS→libsp OPAC 认证链，JWT 内存态（Location query/fragment 双提取）、groupCode 从 JWT payload 解出默认 200755；OPAC 全接口（字段表/条件/馆藏地/简单检索/**完整高级检索**多字段组合+全量筛选+分页/封面/馆藏 groupitems/借阅 loanList/续借 reNew）。借阅页签含续借确认（逾期禁续借）；检索不要求登录。
- **实验信息**（ExperimentSession + OtherExperimentSession + ExperimentController + ExperimentPage）：物理实验=校园网检测(GB18030)+wlsy 明文表单登录(302 判定)+手工 Cookie 串(伪造 PhyEws_StuName/跳 HttpOnly/每请求清容器)+select.aspx 表格+course.aspx 任课老师(TimeN/Teacher span 配对)+wgyreport 六步事件链→成绩图片→FNV-1a 像素哈希查 kScoreHashes 表（@ohos.multimedia.image 解码，RGBA/BGRA 适配）；其他实验=sysj OAuth 六步链+周次 1..25 课表解析（do-labReservation 定位、???标记切字段、连续节次合并、timeList 时间映射）。页面按 进行中/未开始/已完成 分组（now+1 天窗口对齐原版）。学期切换钩入 SemesterController：删双缓存+清实验密码。
- **公共改动**：SessionResponse 增加 setCookies（原始 Set-Cookie 列表）与 headers（每名首值）两个字段（wlsy Cookie 串与 wgyreport session_id 依赖）；Index.ets 注册 7 个新 NavDestination（experiment/emptyClassroom/library/bookDetail/sport/dormWater/dormWaterLogin）；AllFeaturesTab 新增 5 条原生入口（订水系统 webView 与宿舍水机为不同系统，并存）。
- **渲染依赖自查**：DormWaterPage/LibraryPage 借阅区按 NOTICE 教训补 busy @State 翻转（条件链中读取），避免"数据到了 UI 不动"。
- 编译门禁：assembleHap @default 与 @ohosTest 双 BUILD SUCCESSFUL（0 error）。待真机/校园网验证：wlsy/wgyreport/sysj 需校园网；水机需真实手机号；体育/图书馆需真实账号。逻辑全部 1:1 对拍 Dart 源码，边界行为（302 判定/错误文案正则/字段兼容映射）照搬。

## 2026-09-07 · 首页改版："此刻"Hero 聚焦版 + 课程/考试双形态 + 信息瓦片

- 用户确认 B 方案并要求考试优化：Hero 展示合并时间线（课程+考试）最近一条未结束日程——课程上完被 currentSchedule 过滤后考试自然顶到首位，无需专门判断分支；Hero 五态（课程进行中[Progress 进度条+剩 N 分钟] / 课程未开始 / 考试进行中 / 考试未开始[时间·考场·座位富信息行+分钟级倒计时] / 空态），21:25 切明日逻辑沿用。
- HomeArrangement 增加 type 字段（'course' 默认 / 'exam'），ExamController.examsOfDay 传 'exam'；Hero 展示用 displayTitle 还原课程名 + "考试"chip，不再依赖 "{课程名}考试" 命名后缀。
- 需要留意提醒条（三条条件渲染，全不满足整卡隐藏）：电费低于阈值（EnergyController.lowThreshold）/ 图书 7 天内到期（BorrowData.lendDay，含逾期/当天文案）/ 考试临近（Hero 为考试态时去重）；各带动作词与跳转（去充值/去续借/详情）。
- 2×2 信息瓦片：考试倒计时 / 宿舍电费 / 图书借阅 / 校园网流量（rad_user_info remainBytes·sumBytes，免验证码），点击进对应页面，无数据占位文案。
- HomepageController.refreshAll 扩源至 5 路 allSettled：课表 / 考试 / 电费（EnergyController.refreshData）/ 图书（LibraryController.refreshBorrowList）/ 校园网在线信息（SchoolnetController.refreshUserInfo）；**需验证码的 zfw 自助用量不做静默刷新**（仍由校园网页面拉取）。HomeTab.aboutToAppear 补 EnergyController.loadCache()。
- 删除旧"今日日程卡+考试卡"全宽列表（ScheduleRow/ExamRow），全天日程与完整考试列表归位课表页/考试页；头部改时段问候；保留 Refresh 下拉全量刷新 / TAB_BAR_CLEARANCE / 16 圆角 / 深浅色 token 规范。
- 刷新依赖自查：silentRefreshed 在 build 中经"正在同步数据…"条件真实读取（NOTICE 2026-09-06 教训），冷启动刷新完成后立即重建各卡，不等整分 tick。
- 编译门禁 BUILD SUCCESSFUL（0 error）。待真机验证：五路并行刷新耗时、考试日 Hero 切换、电费/图书/网流无数据降级文案。

## 2026-09-07 · 课表课程详情卡片（点击格子查看完整排课信息）

- 需求：点击课表上的课程弹小卡片展示上课周次、任课老师等全部信息；对应 Dart `arrangement_detail/course_detail_card.dart`（ArrangementList 冲突课并列语义一并保留）。
- 新增 `pages/classtable/CourseDetailDialog.ets`（@CustomDialog）：每条排课一卡——课程名 + 课程代码 | 班级号（均空时隐藏）+ 任课老师/教室（sys.symbol.person / pin，空回退"未知老师/未知地点"）+ 周 X 第 a-b 节 + TIME_LIST 钟点区间（节次越界退化为纯节次文案）+ 周次圆点表（有课填充 app_card、无课 0.6 淡化、点击所在周 themePrimary 2vp 描边）；卡底色沿用 course_0..7 色板（COURSE_BG 独立副本，避免 页⇄弹窗 循环导入）。
- ClassTableController 增 `detailTargets` / `detailWeek` 静态桥（ScoreController.detailTarget 同款参数桥模式）；ClassTablePage 格子 `.onClick` → arrangementsAt（同日 + 节次区间交集 + 本周有课）取全部冲突排课，延迟创建 CustomDialogController 后 open（ScorePage 同款，规避成员初始化器白屏问题）。
- 编译门禁：assembleHap BUILD SUCCESSFUL（0 error）。

## 2026-09-07 · 课程详情弹窗拉满整屏修复（layoutWeight 误用）

- 真机截图反馈：详情卡被拉满近整屏，时钟行上下出现大片空白（时钟行垂直居中于被撑高的行内），周次圆点被压到底部。
- 根因：IconLine 的 @Builder 根 Row 内置 `.layoutWeight(1)`——横向并排（老师/教室）是分半宽度，但时钟行单独放在纵向卡片 Column 里时，layoutWeight 按约束剩余可用高度分配，把行撑到占满弹窗剩余空间。
- 修复：IconLine 增加 weight 参数（横向传 1、纵向传 0），卡片高度恢复内容包裹；详见 NOTICE.md 同日条目。编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-07 · 课程详情弹窗双层容器形状统一（同心圆角）

- 真机反馈：系统弹窗白底（默认大圆角）与内部课程色卡（12 圆角）形状不一致，四角白边明显偏厚；根 padding 原为 20/20/20/12 上下左右不均。
- 修复：CustomDialogController 增加 `cornerRadius: 24`（API 10+ 选项，SDK d.ts 已核），弹窗根 padding 统一为 12——满足同心圆角（外 24 = 内 12 + padding 12），四周白边均匀、四角自然嵌套。编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-07 · 课程表页日期行 + 周缩略图条 + 主表滑动切周

- 需求（对应 Dart classtable_date_row.dart / week_choice_view.dart）：① 周几表头上方加日期行（`[5月][2][3]...`，月份格对齐节次列、跨月周只标首日所在月、今日列高亮）；② 原版同款周缩略图条——每卡"第N周 + 5×5 课程圆点预览"（11 节压 5 时段桶 [1-2][3-4][5-6][7-8][9-11]，圆点透明度 有课1.0/已上完0.45/无课0.15），横向 List 自由浏览、点击切周；③ 主表 Swiper 左右滑动切周。交互取"原版同款"（条=浏览+点选，主表=滑动切周），顶部 Select/箭头/刷新保留。
- ClassTableController 新增 `weekStartDate(week)`（startDay+week*7 天，null 安全）、`WeekDot{occupied,completed}`、`getWeekDots(week)`（25 格：occupied=该周该天存在与桶相交排课；completed=过去周恒真/未来周恒假/当前周按日期与桶内最大 stop 的 TIME_LIST 结束时刻判定）。
- ClassTablePage：`weekIndex` 挂 `@Watch`（唯一状态源，四路切换统一），变化时 `ListScroller.scrollToIndex(weekIndex, true, ScrollAlign.CENTER)` 居中缩略图（首定位放 List `onAreaChange` 首次回调——onAppear 时布局未完成 scrollToIndex 不生效）；主表整体进 Swiper（每页=日期行+周几行+节次列+Grid，原版同构，`index(weekIndex)`+`onChange` 幂等回写防联动环、`loop(false)`/`cachedCount(1)`）；新增 `@State dataVersion` 进两处 ForEach key——页内容不读 weekIndex，数据刷新后必须靠 key 变更强制重建（ForEach key 不变则复用旧子树的坑）。
- 对齐修正：日期行/周几行列改 `Row({space:2})×7` 与 Grid `columnsGap(2)` 逐像素对齐（消除旧表头累计 1.7vp 漂移）；节次列加 `space:2` 对齐 `rowsGap(2)`；周几今日高亮修正为"仅显示当前周时命中"（旧实现恒高亮今天周几列）。
- 编译门禁：assembleHap BUILD SUCCESSFUL（0 error）。待真机验证：缩略图居中跟手、Swiper 与 List 联动、跨月周月份标签、今日高亮仅当前周。

## 2026-09-08 · 应用图标替换（样图裁剪版 XDY）

- 用户样图 `C:\Users\sytki\Downloads\XDYou.png`（白圆角块 + 深蓝 XDY 字标）裁剪为应用图标：Python/PIL 按亮度阈值定位 Logo 精确框（499,284)-(909,531)，Alpha 由亮度平滑映射（≤110 全显、≥190 全透），LANCZOS 缩放。
- 分层图标规范化：`foreground.png`（1024²，透明底 + Logo 居中，宽度占比 0.70——样图原始占比 0.76 超出鸿蒙前景安全区，模板参考 0.42）+ `background.png`（1024² 全幅纯白，圆角由启动器遮罩呈现）；entry 与 AppScope 两套同步覆盖。`startIcon.png`（144²）单独烤入圆角白块（启动页无遮罩，直接显示）。
- 产物预览留在工程根目录 `icon_preview.png`（桌面合成效果）/ `icon_preview_start.png`（启动页效果），确认后可删。编译门禁 assembleHap BUILD SUCCESSFUL（0 error）。
- 居中修正（同日）：首版按整包围盒垂直居中，但 Y 的下摆尾巴（行剖面 200~247 行，仅稀疏像素）把包围盒下撑，主体字符中心比画布中心高约 45px，视觉偏上。改为按主体字符行剖面（计数骤降点 0~199 行）做垂直光学居中（下伸部垂入下方留白，上下边距 338/254），水平仍按包围盒居中（字形质量中心偏移仅 9px，属字形本身不对称）。`icon_debug_center.png` 十字线校验主体中线与画布中心重合。编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-08 · 设置页平台账号卡片间距

- SettingTab「平台账号」区 4 张卡片（校园网自助服务/实验平台/体育平台/宿舍水机）由零间距堆叠改为卡间 8vp：后三张卡各加 `.margin({ top: 8 })`（首卡不加以免与 SectionHeader 底距叠加）。编译门禁 BUILD SUCCESSFUL（0 error）。
- 校园网页同款修复：SchoolnetPage「正在使用」节内警示条/账户概览卡/流量使用卡三块由零间距堆叠改为卡间 8vp（概览卡与流量卡各加 `.margin({ top: 8 })`）。编译门禁 BUILD SUCCESSFUL（0 error）。

## 2026-09-08 · 初始化 Git 仓库并发布 GitHub

- 新增 `README.md`（注明移植自 BenderBlog/traintime_pda，含功能表/技术要点/工程结构/构建指南/声明）、`.gitignore`（构建产物、oh_modules、IDE、本地环境、签名与证书、原始 Flutter 工程、调试临时文件）与 `LICENSE`（随原项目采用 MPL-2.0）。
- 签名材料不入库：仓库版 `build-profile.json5` 清空 `signingConfigs`；本地真实签名配置原样保留，用 `git update-index --skip-worktree` 屏蔽差异。README 构建说明已注明克隆后需自行配置签名。
- 排除范围：`traintime_pda-1.6.4/`（上游只读参考，README 链接）、`.debug`/`.zcode`/`.reasonix`/`hap_extract`/`oh_modules`/`local.properties`/各类日志与临时 dump；`icon_preview.png` 保留作为 README 头图。
- 远程仓库：https://github.com/SYTKILLER/XDYou-hmos.git（main 分支）。
