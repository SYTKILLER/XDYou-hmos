<div align="center">

<img src="entry/src/main/resources/base/media/startIcon.png" width="120" alt="XDYou">

# XDYou for HarmonyOS

**本项目移植自 [BenderBlog/traintime_pda](https://github.com/BenderBlog/traintime_pda)** —— 西电校园助手（XDYou / Traintime PDA）的 HarmonyOS 原生版本。

</div>

## 简介

XDYou（代码名 Traintime PDA）是面向西安电子科技大学学生的开源信息查询软件。本项目以原 Flutter 版本（traintime_pda v1.6.4）为蓝本，使用 **ArkTS + ArkUI** 重写为 HarmonyOS 原生应用：

- UI 按鸿蒙设计语言重新设计（不复刻 Flutter 布局），数据逻辑与原版对齐
- **零第三方依赖**：仅使用系统 Kit 与 ArkUI 内置组件
- 面向 HarmonyOS 6.1.1（API 24），支持 phone / tablet / 2in1

## 功能一览

| 模块 | 说明 |
| --- | --- |
| 登录 | 统一身份认证（CAS）三步链：密码加密 → 滑块验证码（NCC 自动求解 + 人工兜底）→ 短信二次认证（可信任设备） |
| 首页「此刻」 | 今日课程/考试聚合时间轴、考试倒计时卡片、下拉一键并行刷新 |
| 课程表 | 本科（ehall）/ 研究生（yjspt）双链路，周视图、调课合并、课程详情 |
| 考试安排 | 未开考 / 已结束 / 时间待定 / 待安排 分组展示 |
| 成绩查询 | 汇总统计（学分/均分/绩点）、学期筛选、单科成绩组成 |
| 电费查询 | 余量显示、电表/水表读数、本地历史记录、低余额提醒 |
| 校园网 | 在线信息、自助服务用量查询（内联验证码登录） |
| 图书馆 | 我的借阅与续借、书目高级检索、图书详情 |
| 空闲教室 | 楼栋 + 日期筛选，11 节方格占用图 |
| 宿舍水机 | 收藏设备、扫码添加（Scan Kit）、出水状态轮询 |
| 体育信息 | 体测成绩 / 体育课成绩双页签 |
| 实验信息 | 物理实验 + 其他实验，按进行中 / 未开始 / 已完成分组 |
| 工具箱 | 常用站点应用内 WebView 访问 |
| 设置 | 种子色主题、深浅色自适应、平台密码管理、退出登录 |

> 原版中的睿思论坛、猪图鉴赏模块不移植；一卡通/考勤等模块在后续里程碑推进。

## 技术要点

- **会话与网络**：RCP 封装（手动重定向 + Cookie 持久化容器），GBK / GB18030 / Big5 解码
- **加密**：`cryptoFramework` 实现 MD5 / AES-CBC(PKCS7) / RSA / 滑块 payload 加密
- **滑块验证码自动求解**：严格归一化 NCC 匹配 + S 形轨迹生成（移植自原版算法）
- **HTML 解析**：自研轻量 DOM 子集与选择器（tag / #id / .class / [attr=v] / 后代组合器）
- **UI**：Navigation + NavPathStack 路由、HdsTabs 悬浮毛玻璃三页签、SymbolGlyph 系统图标
- **状态管理**：AppStorage + @Observed 控制器分层，整分对齐全局定时器驱动首页日程刷新

## 工程结构

```
entry/src/main/ets/
  entryability/   EntryAbility（窗口/生命周期）
  model/          数据模型（对应原 Dart model/）
  service/        网络会话 + 偏好 + 系统能力（对应原 repository/）
    network/      RCP 封装 + Cookie 容器
    ids/          统一身份认证会话（登录/滑块/二次认证/各业务抓取）
    ...           校园网/水机/体育/图书馆/实验等业务会话
  controller/     状态控制器单例（对应原 controller/）
  pages/          ArkUI 页面（Navigation NavDestination）
  theme/          种子色 + 深浅色主题
  utils/          HTML 解析 / 字符集 / 加密 / 日期 / 日志
```

## 构建与运行

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（需支持 HarmonyOS 6.1.1 / API 24）
2. 克隆并用 DevEco Studio 打开工程：

   ```bash
   git clone https://github.com/SYTKILLER/XDYou-hmos.git
   ```

3. **配置签名**：仓库不含任何签名文件与签名配置（`signingConfigs` 为空），真机运行前请通过 File → Project Structure → Signing Configs 完成签名配置
4. 命令行构建：

   ```bash
   hvigorw assembleHap --mode module -p module=entry@default -p product=default
   ```

5. 仪器测试位于 `entry/src/ohosTest`（加密向量 / HTML 解析 / 网络工具对拍）

## 许可证

- 原项目 [traintime_pda](https://github.com/BenderBlog/traintime_pda) 采用 **MPL-2.0** 许可证发布
- 本项目作为其衍生作品，同样以 **MPL-2.0** 发布，详见 [LICENSE](LICENSE)

## 声明

- 本项目是学生个人开发的开源工具，与西安电子科技大学、华为官方均无关联
- 应用仅查询学校官方系统中的个人数据，请妥善保管账号信息并遵守学校相关规定
