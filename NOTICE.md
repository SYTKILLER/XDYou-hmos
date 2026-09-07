# NOTICE — XDYou 开发注意事项

> 记录每次编码过程中犯的错误，一句话概括应避免的问题。编码前先读，修复后按日期追加。
> 全局通用坑见全局记忆 `C:\Users\sytki\.dsh\AGENTS.md`；WhaleChat 历史坑见 `D:\WhaleChat\NOTICE.md`。

---

## 2026-09-05 · 阶段 0 环境基线

- hvigorw 在本机 Git Bash 直跑无沙箱问题；若遇 ENOENT 00308003 属沙箱阻断 hvigor 子进程管道，禁用沙箱重跑即可。
- `PORTING_PLAN.md` 两处旧假设被官方文档推翻：http 默认自动跟随重定向（需 `maxRedirects:0`）；reminderAgentManager 手机端受管控（课程提醒改 Calendar Kit）。

## 2026-09-05 · 阶段 2 登录模块

- rcp 会话可能自动管理 Set-Cookie（与手动注入的 cookie 头并存）→ 真机首验时抓 hilog 确认是否出现重复/丢失 Cookie，必要时改用 rcp CookieRepository 或仅依赖注入。
- ArkTS 无 import() 类型语法（`type X = import('...').X` 编译不过），类型从 @kit 显式 import。
- @StorageProp 绑定的 AppStorage 键在 EntryAbility.onCreate 里 setOrCreate，比 @Entry.aboutToAppear 更可靠。
- `-p module=entry@ohosTest` 会一并编译主代码与测试代码，是比 @default 更严的编译门禁（曾暴露 @default 漏报的 4 处错误）。

## 2026-09-05 · IDE ArkTSCheck 修复

- `NavPathStack` 是 ArkUI 全局声明类（component/navigation.d.ts 的 declare class），**不能** `import { NavPathStack } from '@kit.ArkUI'`（kit 只导出 MultiNavPathStack）——直接使用即可，服务层 .ets 同样可用。
- `InputType` 没有 `User` 成员；合法值 Normal/Number/PhoneNumber/Email/Password/NUMBER_PASSWORD/USER_NAME（API 12+）——学号输入用 `InputType.USER_NAME`。
- DevEco IDE 的 ArkTSCheck 比 hvigor 编译更严（本次两处 IDE 报错 hvigor 均放行），每阶段除 hvigor 门禁外留意 IDE 红线。

## 2026-09-05 · 编译门禁确立

- 带调用签名的 `interface`（成员写成 `(x: T): R;`）编译不过（arkts-no-call-signatures）——回调类型一律用 `type F = (x: T) => R` 别名，用法处（参数类型/联合 null）无需改动。
- 新门禁：每次修改后 assembleHap 必须 0 error 才允许结束任务（用户 2026-09-05 约定，已写入 AGENTS.md §2）。

## 2026-09-06 · UI 规范化

- `resourceManager.getConfigurationSync()` 返回的 `colorMode` 是 `resourceManager.ColorMode`（DARK=0/LIGHT=1），与 `ConfigurationConstant.ColorMode` 是两个不兼容类型，跨枚举比较直接编译报错——各与自己的枚举值比较。
- 深色下种子主色变浅（#9FC9FF），其上文字必须用 `onPrimary` 深藏青（白字对比度仅 2.1:1）；error 同理成对建 on_error 资源（深色 error 是浅红 #FFB4AB，白字 1.6:1）。
- 页面用色规范：静态色一律 `$r('app.color.*')`（base+dark 双 color.json 自动切换，无需状态）；只有随种子色变化的 primary/onPrimary 才需要 `@StorageProp('isDark')`。禁止硬编码 `#808080` 类灰色当正文色。

## 2026-09-06 · reAuth 链路

- 二次认证锁必须与登录锁分离（Dart _reAuthLock vs _idsLock）：handler 在登录锁持有期间被调用，共用一把锁会死锁。
- @CustomDialog 的 cancel 配置回调（返回键关闭）与按钮内 finishCancelled 都要走 ReAuthCoordinator，否则 Promise 悬挂导致登录卡死。
- setInterval/clearInterval 在 ArkTS 全局可用，对话框 aboutToDisappear 必须清定时器。
- ArkTS 的 Promise `reject` 形参要与标准库 `(reason?: any) => void` 比对，直接把 executor 的 reject 存进自定义函数类型字段会报 arkts-no-structural-typing → 改用「resolve 结果对象」模式（如 ReAuthResult{ok,uri,error}），只用 resolve。
- `Error` 在 ArkTS 是接口式类型：Error 子类实例**赋值给 `Error` 类型字段**同样报 arkts-no-structural-typing → 字段声明为具体子类联合（`IdsReAuthCancelledError | IdsReAuthExpiredError | null`）。
- arkts-limited-throw：`throw` 不接受联合类型（即便都是 Error 子类），必须 instanceof 收窄成单个类再抛；catch 变量本身已是 Error 类型，`e instanceof Error ? e : new Error(String(e))` 模式可用。

## 2026-09-06 · 滑块验证一直失败排查

- Dart 滑块客户端是「全新 Dio 无 CookieManager」：只发登录会话 Cookie 串快照，openSliderCaptcha 新下发的 Set-Cookie 一律丢弃；鸿蒙侧复用共享 general 会话会把响应 Set-Cookie 收进容器、verify 时与登录 Cookie 同名混发 → 改为独立 'slider' 会话 + 每次请求前 clear() 容器。
- GestureEvent.offsetX 单位是 vp（gesture.d.ts 明确 "The unit is vp"），与 Flutter 逻辑像素同语义，滑块轨迹单位无需换算。
- 服务端验证码图实际为 590x360/93x360，Dart 常量 280x155/44x155 仅是显示尺寸，缩放比一致（0.4746），勿把显示常量当图片尺寸。
- verify 响应体必须打日志（Dart 有 payload+result 日志）：只打 statusCode 无法定位 errorCode 失败原因。

## 2026-09-06 · 滑块"一直无法通过"根因定案（Node 协议实验证实）

- 服务端判定公式：**|moveLength − X| < 0.5**（X=缺口期望位置，严格小于）——约 ±1px 内才通过；errorMsg 对失败统一返回 {"errorCode":0,"errorMsg":"error"}，成功 {"errorCode":1,"errorMsg":"success"}。
- 协议/加密/Cookie/会话全部正确（Node 用官方 encrypt.js 复现两次 success）；用户 App 失败根因＝人工拖动 + 整数取整提交，命中 ±0.5 窗口概率极低。
- **必须走自动求解**（Dart solveOffset 的 NCC 模板匹配 + ±1/2/3/4 邻域穷举 ×6 轮）；人工滑块页只作兜底。NCC 检测位置已经视觉标记图人工复核确认精确。
- openSliderCaptcha 响应含 tagWidth(恒93)/yHeight(恒0) 无用字段；验证码图实际是 JPEG(590x360)+PNG(93x360 带alpha)，显示尺寸 280x155/44x155 只是 Dart 时代常量，NCC 匹配要用解码后原始像素。
- libxduauth（PyPI 权威实现）走的是**明文 canvasLength+moveLength（无 sign 无 tracks）**路径，服务端 sign/明文双路径并存——排障时可用明文路径做交叉验证。
- Image Kit 解码链：createImageSource(ArrayBuffer) → createPixelMap({desiredPixelFormat: RGBA_8888}) → readPixelsToBuffer；base64 先经 util.Base64Helper。
- hvigor 守护进程对"新增文件"的增量判定可能漏编译并仍报 BUILD SUCCESSFUL（假绿）——新增 .ets 后必须用 `--no-daemon` 全量编译验证，或以 DevEco IDE 报错为准。
- NCC 峰值偏差逐张变化（0~+4px+，源码级原因＝服务端生成验证码时内容摆放偏移），穷举窗口按命中概率排序扩至 -6..+10（DELTAS=[2,3,1,4,0,5,6,-1,7,-2,8,-3,9,-4,10,-5,-6]），轮数 6→4 平衡最坏耗时；人工滑块在 ±0.5 容差下本质是抽奖，仅作兜底。
- Dart _imageNcc 实际是「斜率公式」Σ(w·t)/Σ(w²)（未除以模板范数），在平坦窗口会因分母→ε 产生 >>1 的虚假峰值（真机日志 ncc=3.9），导致匹配位置散乱——移植时改用严格归一化 NCC：Σ(w·t)/sqrt(Σw²·Σt²)（峰值 0.7~0.95，与 Node 验证一致）。**移植算法要先理解公式语义再照抄，注释里的名字（ncc）不一定名实相符。**
- 滑块 Cookie 链路已实证完好：route + JSESSIONID + UqZB(WAF) + MULTIFACTOR_BROWSER_FINGERPRINT 四段齐全（后者证明 bfp 指纹注册生效）。
- 人工滑块页存在 ~0.47px 系统性左偏（piece PNG 内容从 x=1 起，Cover 缩放 44/93 后内容左缘偏移）叠加服务端 ±0.5 容差 → 裸人工提交几乎必败；人工页释放后改为在当前验证码上复用 NCC+邻域穷举（sign→plain），NCC 不可用才提交原始轨迹。
- cryptoFramework 对称加密：`generateSymKey()` 是"随机生成密钥"（d.ts 原文 Generate a symmetric key object randomly），注入指定密钥必须 `createSymKeyGenerator(alg).convertKey({data: key})`——滑块 sign 与登录密码加密曾因此全部失效（2026-09-06 协议 oracle 实验证实服务端正确后落码修复）。
- 服务端滑块验证只认 sign 加密路径：明文 canvasLength+moveLength（无 sign）5 发全败（oracle 直连实测），此前"libxduauth 明文双路径并存"的记录不成立；verifyPlain 已删除，排障勿再走明文岔路。
- 协议 oracle 脚本：`.debug/slider_oracle.py`（Python+PIL+pycryptodome 直连 IDS 复现 fetch→NCC→sign 全链，含 NIST 向量自校验；直连时需 `s.trust_env=False` 绕过失效系统代理）。协议疑义时先跑它再改 App。
- 验证码图尺寸逐张可变（实测 590x360 与 500x332 并存）：NCC/显示一律按解码后自然尺寸，禁止硬编码宽高；ncc 低至 0.6 时邻域穷举窗口仍可命中，DELTAS 宽窗保留有价值。
- CustomDialog 桥接类 Coordinator（solve 存 resolver 永远 pending）：UI 侧 handler 必须负责 .open()，漏掉 open() 就是无超时无报错的全链路悬死（reAuth 卡死教训）；新增此类桥接时先验证弹窗真的弹出来。
- @Builder 方法调用返回 void：调用点后面不能链 `.margin()/.padding()` 等属性修饰（编译错 "Property 'margin' does not exist on type 'void'"）——留白要么写进 @Builder 内部，要么给 @Builder 加参数传入。
- Stack 的 alignContent 参数必须写全枚举 `Alignment.Bottom`，裸写 `Bottom` 编译报 Cannot find name。
- `@kit.CoreFileKit` 的文件 IO 导出名是 `fileIo`（`import { fileIo as fs }`），`fs` 名不存在；fs.OpenMode 截断枚举叫 `TRUNC`（无 TRUNCATE）。
- ArkTS interface 里禁止嵌套匿名对象类型（`datas?: { rows?: T[] }` 报 arkts-no-obj-literals-as-types），一律拆具名 interface；对象字面量也不能直接传 Map 形参（须 new Map + set）。
- 悬浮沉浸光感页签官方组件是 HMS 侧 `HdsTabs`（@kit.UIDesignKit）：barOverlap(true) + barFloatingStyle.systemMaterialEffect(hdsMaterial ADAPTIVE) @6.1.0(23)；开源 tabs.d.ts 里只有 barOverlap/barBackgroundBlurStyle(@11/12) 无自适应材质。

## 2026-09-06 · 主题切换失效修复

- **@StorageProp 只声明不读取＝零刷新依赖**：themeVersion 各页都 `@StorageProp` 了但 build 里从未引用（种子色全靠方法调用间接读偏好），变化时一个 UI 节点都不更新——"订阅了版本号"不等于"订阅生效"，状态变量必须在 build 中被真实读取（直接或经方法嵌套）才建立依赖。全局版本号+方法取值模式作废，改为 AppTheme.syncStorage 写 themePrimary/themePrimaryContainer/themeOnPrimary token，页面 @StorageProp 绑定后直接引用。
- **Select 按钮初始文本必须 `.value()`**：官方文档明确 `selected` 只设下拉菜单初始索引，按钮文本来自 `value`（"选中菜单项后按钮文本才自动更新"）——不设 value 时按钮一直空白，用户会误报"没有默认值"。
- SelectOption.value 是 ResourceStr（string|Resource），取按钮文本用 `typeof v === 'string'` 收窄，勿用 `as` 断言。

## 2026-09-06 · 子页白屏 + 返回键退应用根因（模拟器实证）

- Navigation 的 navDestination @Builder 路由函数**必须用 if / else if 链**：写成多个独立 `if`（各创建不同自定义组件）时框架整体解析失效——日志 AceNavigation "can't find name in config file: xxx" → "create empty node"，表现为子页白屏（无标题无内容只有返回键）、按返回键直接退应用。单分支或 else-if 链均正常；与 HdsTabs/页面代码无关。
- NavDestination 页面**禁止在成员初始化器里 `new CustomDialogController({builder: XxxDialog()})`**：会使页面实例化失败（白屏、aboutToAppear 不执行、无任何应用日志）；改为 `CustomDialogController | null = null`，在事件回调里判空创建后 `.open()`（ScorePage 实证修复）。WhaleChat 的初始化器模式只在普通 @Entry 页验证过，NavDestination 场景不成立。
- 排障利器：模拟器（API 略低可临时降 compatibleSdkVersion）+ uitest dumpLayout/hilog 抓 "create empty node"，比真机点按复现快得多；/data/log/faultlog/faultlogger/ 的 sysfreeze 可读。

## 2026-09-07 · 角色误判致 403 HTML 排障

- 判空语义移植陷阱：Dart `data["res"] != null` 是**判空**（字段存在但值为 null 时为 false），ArkTS 顺手写成 `res !== undefined` 就变成**判存在**（null !== undefined 为 true）——`{"res":null}` 这类"成功但空"的响应两者语义相反。移植布尔判定先问：原语义是"有值"还是"有键"。
- wisedu 平台的 403 是**应用级 ACL**：门户公共模块（yjsemaphome 等）任何登录用户可访问；各业务 app 模块（wdcjapp/wdksapp/wdkbapp）需账号有该应用授权，无授权 → 403 + HTML（scenes_abnormalPage，title=403，无原因文字），不是 302 登录失效。JSON.parse 直接吃 HTML 就报 "Unexpected Text in JSON: Invalid Token"——见到此错先查响应是不是 HTML，别急着怀疑 JSON。
- `*default` 路径里的裸 `*` 直接发给 openresty 网关会 400 Bad Request；rcp 会编码成 %2A 正常路由。手工 curl 重放时要用 %2A。
- yjspt 与 ehall 的学期代码格式不同（`20261` vs `2026-2027-1`），角色/数据源切换后 SemesterController 靠值比较识别变更清缓存，天然兼容。
- 排障利器补充：hdc 可直接读 debug 版应用沙箱偏好（`/data/app/el2/100/base/<bundle>/haps/entry/preferences/`），里面有序列化 Cookie 罐（含 CASTGC），配合 curl 从 PC 逐字节重放整条 CAS 链路，可把"App 里才有的问题"变成"PC 上可二分的问题"。用完删文件（含敏感凭据）。
- hvigor 编译报 Index.ets 一堆 Declaration expected 时先看是否上次删代码删坏了括号，别急着怀疑自己刚改的文件。
- **@State 不要承载 TypedArray（Uint8Array）**：赋值非空、首帧渲染却读到 length 0（真机 jscrash：base64Encode 报 "must be Uint8Array and the length greater than zero"，栈在 build 的 If 分支）——TypedArray 不在 @State 支持的观测类型清单（Object/class/string/number/boolean/enum/Array/Date/Map/Set）。@State 只存展示就绪形态（如 data URL 字符串），字节转换在赋值处完成、build 里不做数据变换（顺带避免每次 rerender 重复转换）。

## 2026-09-07 · 工具箱网址跳转

- Stack 的 alignContent 参数取值是 `Alignment.TopStart` 等完整枚举（裸写 TopStart 编译不过），与 Column 的 HorizontalAlign/VerticalAlign、Flex 的 FlexAlign 是三套不同枚举，不能混用。
- @Builder 直接调用另一 @Builder（如 Stack 内 if 分支里 this.ErrorView()）时，外层容器对齐不继承——错误卡需自包一层 Column 撑满后内部居中。

## 2026-09-07 · 校园网页"一直正在查询"

- 控制器静态字段 + AppStorage bumpVersion 的页面，**成功路径也必须翻一个 @State**（boolean/计数器均可）驱动重渲染——失败路径有 @State（error 串）所以只坏成功分支：数据到了 UI 永远停在 loading（@StorageProp version 声明而 build 中零引用＝不建立依赖，2026-09-06 教训的变体，M6 页面又犯）。已证范式：ScorePage/HomeTab 的 busy/refreshing 翻转，重渲染时顺带重读控制器 getter。

## 2026-09-07 · 课表页表格塌陷（三次试错后定案：模板串 vp 单位才是根因）

- **Grid 模板串（rowsTemplate/columnsTemplate）混入 vp 固定单位（如 '30vp 1fr...'）会使整个网格解析塌陷**：首格撑满全 Grid、其余 GridItem 全部不挂载，且与行列号写法无关（0-based/1-based/线号三种写法同崩，静态 GridItem 也崩）。**模板只用纯 fr**；固定高度的行/列（表头、节次列）移出 Grid 用 Row/Column + layoutWeight 组合实现（真机三轮实验定案）。
- GridItem 行列号正确语义（官方文档原文）：**0-based 行/列号、闭区间，跨度 = end − start + 1**，合理取值 0~总行数−1，四个属性须同时设置；单格写法 rowStart(r) rowEnd(r)。d.ts 英文注释的 "line number" 措辞有误导性，以文档"占据行数(rowEnd-rowStart+1)"公式为准。
- 排障组合拳：uitest dumpLayout 看 Grid 下 GridItem 数量与 bounds（撑满父容器＝网格塌陷）+ 静态 GridItem 对照实验区分"参数语义错"与"网格未建立" + 改纯 fr 二分定位。

## 2026-09-07 · 校园网页二轮修复（真机 hdc 复现定案）

- **@State 翻转必须被"受影响的 if 链条件表达式"读取**——仅在回调里赋值、条件里不读，等于没翻：ArkUI 只重渲染读取了变化状态的节点，控制器静态字段无人观测。第一轮修复（翻 infoLoaded 但条件里没读它）因此无效，第二轮把 infoLoaded 写进数据分支条件才通过。已证范式即 ScorePage 的 `else if (... && this.busy)`：状态在条件里，翻转时整条 if 链重评估、顺带重读控制器 getter。
- 排障正道：`hdc shell uitest dumpLayout/uiInput click` 可全程遥控真机复现（Git Bash 记得 MSYS_NO_PATHCONV=1，hdc 本地路径用 `\` 反斜杠相对形式）；hilog 域过滤 `hilog -x -D 0xD001`。成功路径也打 Log.info（fetch start/done + 关键字段），否则抓到的日志是空的。
- rad_user_info 的 error≠"ok" 时接口仍返回完整账号数据（真机实证：手机 IP 会话状态与 PC 不同）——**原版 Dart 页不校验 error、有数据即渲染**，移植版以 userName 是否为空做离线闸门，勿用 error 字段拦数据。

## 2026-09-07 · 五功能迁移（实验/空教室/图书馆/体育/水机）新增踩坑

- **dio baseUrl 的 Uri.resolve 语义**：体育平台 baseUrl=`.../app/` 而 login 传 `/h5/login`（带前导斜杠）→ 解析落在**站点根** `.../h5/login`，丢弃 `/app/`；其余不带斜杠的子路径才拼在 baseUrl 后。移植时逐字核对 Dart 的相对路径解析，勿想当然。
- **wlsy 手工 Cookie 规则**：登录成功以 302 为准；Cookie 串 = `PhyEws_StuName` 项替换为固定伪造值 + 跳过含 HttpOnly 的项 + 其余取分号前段。rcp 容器每次响应都会自动吞 Set-Cookie，必须**每次请求后 cookies.clear()**，否则容器行与手工行重复注入。
- **wgyreport.dll**：会话 id 在响应头 `session_id`（非常规头），点击登录后的 `sid=` 在 Set-Cookie 里——NetworkSession 已扩展 `headers`（每名首值）与 `setCookies`（原始列表）两个字段。
- **cxjsqk.do 的 weekDaySetting 上游 bug**：name 本应是 XQ 但原版写 ZC，服务端实际接受的就是这个——移植照抄，勿"修复"。
- **FNV-1a 像素哈希**：Dart image 包取 alpha==255 像素的 r,g,b；HarmonyOS 解码默认 RGBA_8888 但要按 `info.pixelFormat` 兼容 BGRA_8888（R/B 互换）；乘法用 `Math.imul` 再 `>>>0` 保持 32 位。
- **ArkTS 数字键 JSON**：`row['2']`（wgyreport rows 字段名是数字）对 interface 直接索引会报 arkts-no-props-by-index，需 `as Record<string, ...>` 桥接（Record 是 ArkTS 唯一允许索引访问的形态）。
- **ArkTS interface 内禁止内联嵌套对象字面量类型**（`datas?: { rows?: ... }` 报 no-obj-literals-as-types），全部拆成具名 interface；跨文件传 JSON 形状时两侧必须**同一 interface**（结构相同也不行，no-structural-typing）。
- **querySelectorAll 的 [attr=v] 值含逗号会撞上选择器逗号分组歧义**——sysj 课表 `td[do-labReservation='1,2']` 改用"遍历全部 td + attr() 精确比对"更稳；HtmlNode 无 innerHtml，`th 内 <br> 之后的日期`用"递归找 br 后拼接文本节点"替代 innerHtml.split('<br>')。
- **jwt base64url payload**：util.Base64Helper 不吃 url-safe 字母表，先 `-`→`+`、`_`→`/` 再补 `=` 到 4 的倍数。
- **图书馆 JWT 认证链**：token 只在内存（initInflight 去重）；跳转链中 jwt 可能藏在 Location 的 query 或 **fragment 内的 query**（#/xxx?jwt=...）两处都要试；遇 open.weixin.qq.com / wx.chaoxing.com / 路径含 /weixin/ 直接报错。
- **EnergyController.data() 返回 `EnergyInfo | null`**（与 ExamController.data() 的非空约定不同），hasData() 为 true 后仍须判空收窄再取字段，直接链式 `.electricityRemain` 编译报 Object possibly null。
- **layoutWeight 在纵向 Column/未定高容器里会吃掉"约束剩余可用高度"而非剩余内容高度**——@Builder 通用行组件内置 `.layoutWeight(1)` 被单独放进弹窗卡片 Column，导致时钟行被撑到整屏高、卡片拉满全屏；横向并排分宽才传 weight，纵向单独用必须 0（CourseDetailDialog IconLine 参数化）。

## 2026-09-08 · Git 仓库初始化（发布 GitHub）

- **build-profile.json5 的 signingConfigs 不入库**：仓库版清空签名配置，本地真实签名配置保留并以 `git update-index --skip-worktree build-profile.json5` 屏蔽差异（防止 git add . 误传签名材料）；需提交该文件的结构性改动时先 `git update-index --no-skip-worktree build-profile.json5`。
- 原始 Flutter 工程 `traintime_pda-1.6.4/` 与 `.debug`/`.zcode`/`hap_extract`/日志/临时 dump 均被 .gitignore 排除，仓库只含 HarmonyOS 工程本体与项目文档；README 使用的 `icon_preview.png` 有意保留入库。

## 2026-09-08 · Swiper 程序化切页默认无动画

- **Swiper 的 `index` 属性变更与 `SwiperController.changeIndex()` 默认都是无动画瞬跳**（d.ts/官方文档：changeIndex 的 useAnimation 默认 NO_ANIMATION）——程序化翻页必须 `changeIndex(t, true)`；API 15+ 远距跳页用 `SwiperAnimationMode.FAST_ANIMATION`（先瞬移邻页再短滑）。先 changeIndex 起播动画再写绑定的状态变量（属性同目标更新幂等），顺序反过来属性更新会先瞬跳、changeIndex 到位后不再有动画。Swiper 默认 interpolatingSpring 曲线下 `.duration()` 不生效，除非显式换非弹簧 curve（会牺牲手势回弹手感）。
- **Swiper 混用 index 属性与 SwiperController 时，属性只许作首帧定位**：`.index()` 绑响应式变量后，changeIndex 动画期间任何状态变更引发的属性重应用都会瞬跳目标页吞掉动画——绑普通成员（值不变），运行期切换全走 changeIndex / onChange，数据刷新重建子组件后用 `changeIndex(index, false)` 无动画重定位。
- **rad_user_info 成功响应的 `error` 字段是 `"ok"`**（非空）→ `CurrentUserNetInfo.isOnline()`（判 error.length===0）对在线设备也返回 false。展示"正在使用/流量使用情况"数据一律别拿 isOnline 当门禁（照抄 SchoolnetPage：只看 hasUserInfo/数据非空）。
- **首页瓦片类"静态字段直读"的刷新依赖**：只在 build 某个 if 条件里读 @State 救不了兄弟节点；必须让展示数据的取数方法内真实读取会变化的 `@StorageProp('xxxVersion')`（控制器 bumpVersion 自增），该 Text 节点才会在数据到达后重建。
