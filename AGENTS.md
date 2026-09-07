# XDYou 项目记忆（HarmonyOS 移植）

> 项目专属记忆，仅在本工程（D:\HarmonyOS_Develop\XDYou）生效。
> 全局记忆（ArkTS 语法禁区 / 5 阶段工作流 / 指令卡）见 `C:\Users\sytki\.dsh\AGENTS.md`。
> 踩坑日志：本目录 `NOTICE.md`（编码前先读、出错后追加一句话）。
> 完整移植方案：本目录 `PORTING_PLAN.md`（2026-09-05 修订版）。

---

## 1. 项目定位

- **目标**：将 Flutter 应用 traintime_pda-1.6.4（西电校园助手，290 个 Dart 文件/49,422 行）移植为 HarmonyOS API 24 原生应用（bundleName `com.xdyou.app`）。
- **源项目**：`traintime_pda-1.6.4/` **只读**，不修改；产物全部落在 `entry/src/main/ets/`。
- **范围决策（2026-09-05 确认）**：核心优先（登录 + 16 个信息查询模块 + 首页聚合 + 设置）；睿思论坛/上课提醒/日历导出/服务卡片后置里程碑；i18n 首期仅 zh_CN（目录按多语言预留）；真机验证用 DevEco 签名（signingConfigs 当前为空，由用户配置）。
- **范围决策（2026-09-06 修订）**：登录后框架为**三页签**（首页/全部功能/设置，悬浮毛玻璃底栏，详见 PORTING_PLAN.md §5 阶段 3 修订版）；**睿思论坛、猪图鉴赏（Pig）放弃移植**；页面 UI 按鸿蒙设计语言重设计、不复刻 Flutter 布局（数据逻辑与原版对齐）；首页首期仅日程+考试两卡，全部功能页只列已移植功能；图标一律用 HarmonyOS Symbol（SymbolGlyph + sys.symbol，名称以 SDK sysResource.js 符号表为准）。
- **范围决策（2026-09-07 修订）**：首页改版为"此刻"聚焦版（Hero 课程/考试双形态卡 + 需要留意提醒条 + 2×2 信息瓦片：考试/电费/图书/校园网），`refreshAll` 扩源 5 路并行（校园网 zfw 需验证码不可静默刷，只刷免验证码在线信息）；HomeArrangement 加 `type` 字段（course/exam）供 Hero 分形态；`EnergyController.data()` 返回可空，hasData() 后仍须判空。
- **UI 约束**：全部 ArkUI 系统内置组件组合（Navigation/Tabs/List/Grid/WaterFlow/SymbolGlyph…），零第三方依赖、不引组件库、不自绘封装；弹窗用系统 AlertDialog / CustomDialog 规范模式。

## 2. 编译验证（强制）

```bash
cd /d/HarmonyOS_Develop/XDYou && node "C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" assembleHap --mode module -p module=entry@default -p product=default
```

- **完成门禁（2026-09-05 用户约定）**：每次修改（代码/资源/配置）后必须重跑本编译，输出 `BUILD SUCCESSFUL` 且 0 error 才允许结束任务；编译失败必须修复后重跑，不得带 error 交付。
- 成功标志 `BUILD SUCCESSFUL`；基线 2026-09-05（13.9s）。
- 若报 ENOENT 00308003：是沙箱阻断 hvigor 子进程管道，禁用沙箱重跑，不是代码错误。
- 单测：`entry/src/test` LocalUnit.test.ets（crypto 对拍 / GBK 解码 / HTML 解析）。

## 3. 已验证的 API 事实（2026-09-05 官方文档复核，编码直接引用）

| 主题 | 结论 |
|---|---|
| 重定向 | `@ohos.net.http` 默认自动跟随 30x、无 followRedirects；API 23+ `maxRedirects`（0=关闭，超限错误码 2300047）。302 本体能否返回 → 阶段 1 尖兵实测；备选 rcp `autoRedirect:false` |
| 二次认证 | 登录三步链＝密码→滑块→短信验证码；重定向每跳查 `reAuthCheck/reAuthLoginView.do`，reAuth 串行锁须与登录锁**分离**（handler 在登录锁内被调用）；取消/过期清 ids Cookie；信任设备＝reAuthSubmit 的 `skipTmpReAuth` |
| 滑块容差 | verifySliderCaptcha 判定 **\|moveLength−X\|<0.5**（X=缺口期望位），人工拖动几乎必败 → 必须自动求解（严格归一化 NCC+邻域穷举，2026-09-06 oracle 直连复现成功）；失败统一 `{"errorCode":0,"errorMsg":"error"}`；**服务端只认 sign 加密路径**，明文 canvasLength+moveLength 不被接受（oracle 5 发全败），verifyPlain 已删 |
| Cookie | 请求侧手动塞 header；响应侧 `HttpResponse.cookies`（8+）读原始 Set-Cookie；**手动 header 的 Cookie 重定向时不自动携带** |
| 明文 http | API 18+ 默认放行，无需配置（可选 `resources/base/profile/network_config.json`） |
| 响应上限 | 默认 5MB，必须设 `maxLimit`（API 23+ 单请求上限 50MB）；http 的 `body`/`queryParams` 是 API 26+，**禁用** |
| AES | `cryptoFramework.createCipher('AES128\|CBC\|PKCS7')` + `IvParamsSpec`（16B）；IDS 密码加密为手动 PKCS7 + 固定 IV `xidianscriptsxdu`；**对称密钥必须 `createSymKeyGenerator(...).convertKey({data:key})` 注入，`generateSymKey()` 是随机密钥**（曾致滑块/密码加密全错） |
| RSA | `createAsyKeyGenerator('RSA1024\|PRIMES_2')`；服务端公钥用 `AsyKeyGenerator.convertKey/convertPemKey` 或 `createAsyKeyGeneratorBySpec`（**无模块级 convertKey**） |
| MD5 | `cryptoFramework.createMd('MD5')` + update/digest |
| GBK | `util.TextDecoder.create('gbk'\|'gb18030'\|'big5')` 官方支持 |
| 扫码 | Scan Kit `scanBarcode.startScanForResult` **无需 CAMERA 权限**（预授权）；customScan 才需要 |
| 提醒 | reminderAgentManager 手机/平板**受华为管控**（需豁免）→ 课程提醒用 Calendar Kit 带提醒日程（后置） |
| 路由 | `@ohos.router` API 18 废弃 → **Navigation + NavPathStack**（平板 `NavigationMode.Split`） |
| Toast | 全局 `promptAction.showToast` API 18 废弃 → `this.getUIContext().getPromptAction().showToast(...)` |
| 富文本 | RichText 组件停止维护 → Text/Span 组合 |
| 权限 | INTERNET/GET_NETWORK_INFO/PUBLISH_AGENT_REMINDER＝system_grant；CAMERA/READ_CALENDAR/WRITE_CALENDAR＝user_grant 需 reason+usedScene |
| 文档镜像 | 含 API 25/26 预览 API，**API 24 工程编码以 SDK d.ts 为准**（`C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\`） |
| 深浅色 | 静态色一律 `$r('app.color.*')`（base + dark 双 color.json 自动切换，token 见 2026-09-06 色板）；种子色用 `@StorageProp` 绑定 AppStorage token `themePrimary/themePrimaryContainer/themeOnPrimary`（`AppTheme.syncStorage()` 统一写，启动/切种子色/深浅色生效三入口调用）——**状态变量必须在 build 中被真实读取才建立刷新依赖**，只声明版本号不引用＝切换失效（2026-09-06 教训）；`Select` 按钮初始文本必须 `.value()`，`selected` 只定菜单高亮；`getConfigurationSync()` 的 colorMode 是 resourceManager.ColorMode，与 ConfigurationConstant 不互通 |
| 悬浮页签 | 官方组件＝HMS 侧 `HdsTabs`（`@kit.UIDesignKit`）：`barOverlap(true)` + `barFloatingStyle.systemMaterialEffect(hdsMaterial ADAPTIVE)`＝沉浸光感（**@6.1.0(23)**）；页签图标用 `TabBarSymbol`（normal/selected 双 `SymbolGlyphModifier`）；开源 tabs.d.ts 只有 barOverlap/barBackgroundBlurStyle(@11/12) 无自适应材质 |
| 文件IO | `@kit.CoreFileKit` 导出名是 `fileIo`（无 `fs`）；`fs.OpenMode` 截断枚举为 `TRUNC`；文件缓存走 AppContext（cacheDir + fs.readTextSync/writeSync/statSync.mtime(秒)） |

## 4. UI 控件规格（2026-09-06 起，新页面直接沿用）

- 输入框/按钮高 50，水平 padding 16，按钮圆角 12；基础间距 16、模块间距 24；禁用态 `opacity(0.6)`。
- 正文/辅助文字用 `$r('app.color.text_primary'/'text_secondary')`，禁止硬编码灰（#808080 对比度仅 3.5:1 不达标）。

## 5. 借鉴自 WhaleChat 的既证模式

- CustomDialog：`controller?: CustomDialogController`（可空，禁 `!`），`this.controller?.close()`。
- AlertDialog：`this.getUIContext().showAlertDialog(...)`（非全局 `AlertDialog.show()`）。
- Select 默认值/占位规范（2026-09-07 约定）：`.selected(-1)` 或省略＝空态，**必须**配 `.value('占位文本')`；`.selected(0)`＝默认选中第一项；`.selected` 传 undefined/null＝框架自动选中第一项。有合法默认值时一律"selected(有效索引) + .value(label())"组合（selected 只定菜单高亮，按钮文字必须 value 提供）；label 助手索引越界时钳回首项或回退占位文案，禁止返回空字符串。
- `@State` 数组下标赋值不触发 UI：用 `splice(index,1,x)` 或整体重建赋值。
- JSON/HTTP header 动态键：声明显式 interface 后点号访问，禁 `obj['field']` / `as Record<string,Object>` 解析。
- `@Watch` 位置精确到目标属性；Promise 禁 `.catch(() => {})` 吞错，必须 hilog 记录。
- `Select` 用 `.font({size:n})`；`SelectOption` 显式 `{value:string}`；`ListItem` 单子节点；`@Builder` 内不能声明变量；`@Provide` 配 `@State`。
- `TabsController.changeIndex()` 切 Tab；`BottomTabBarStyle` 的 normal/selected 收 `SymbolGlyphModifier`，`@Builder` 直接传 `.tabBar()`。
- 删组件连带 grep 清引用；新页面若用 `@Entry` 必须注册 `main_pages.json`（Navigation 的 NavDestination 不需要）。
- T3 `deveco run` 前注入：`export DEEPSEEK_API_KEY=$(powershell -Command "[Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY','User')" | tr -d '\r')`。

## 6. 目录约定（entry/src/main/ets/）

```
entryability/   EntryAbility（窗口/生命周期）
model/          数据模型（对应 Dart model/，纯类）
service/        网络会话 + 偏好 + 系统能力（对应 Dart repository/）
  network/      NetworkSession + CookieContainer
controller/     状态单例（对应 Dart controller/，@Observed/AppStorage）
pages/          ArkUI 页面（对应 Dart page/，Navigation NavDestination）
theme/          种子色 + 深浅色主题
utils/          html 解析 / charset / crypto / 日志
```

文档：`DEVELOPMENT_LOG.md`（每次变更追加条目）、`PROJECT_STRUCTURE.md`（结构变更时更新）、`NOTICE.md`（踩坑一句话）。
