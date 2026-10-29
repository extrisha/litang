# 理堂

上海理工大学校园助手，Flutter 客户端。


⚠Vibe Coding⚠


持续开发中...更多功能敬请等待...



## 功能与开源范围

本仓库是「理堂」的完整源码（**不是裁剪版**），包含：

- 首页：校园通知聚合（全校 63 个二级站点、7000+ 条，按竞赛/教学/讲座等分类筛选，本院优先）
- 搜索：本地通知检索（标题/部门/分类，离线 BM25，不依赖服务端）
- 地图：离线校园地图（基于 OpenStreetMap 离线瓦片引擎、校区切换、地点检索、课表一键定位教室）
- 今日课表：全校排课日程展示（Canvas 精细排版网格、智能防冲突莫兰迪配色引擎、多周次平滑切换）
- 校园服务：空教室实时查询、全校课程检索、空间预约、宿舍电费余量监测
- 学习通：课程、作业、考试、讨论、活动签到（数字口令 / 扫码 / 雷达 / 拍照）
- 一网畅学（Tronclass）：课程、待办、考试、课件与签到
- 学业档案：成绩、绩点、专业排名、培养方案进度
- 校历联动、作业与考试临期提醒、客户端版本自动检测与平滑更新
- 论坛：找搭子功能**尚未开放**，当前页面为示例数据；入口暂时保留

### 关于登录（请以本节为准）

三个系统的登录方式并不相同，凭据都只保存在本机：

| 系统 | 登录方式 | 本地保存 |
|---|---|---|
| 教务 | App 内通过学校 CAS 登录 | 会话 cookie；勾选「记住登录」时，学号与密码也会用系统密钥库（Keystore / Keychain）加密保存 |
| 学习通 | 内嵌学习通官方登录页，密码只输入在对方页面 | 只保存会话 cookie |
| 一网畅学 | 复用教务登录态静默认证 | 只保存会话 cookie |

- 「记住登录」**默认开启**，可在登录页关闭；关闭后只保存会话 cookie。已保存的教务凭据可在「我的」点「退出」清除。
- 密码与 cookie 只在本机使用，不上传、不写日志、不经过本项目服务器（本项目没有服务器）。
- 登录后只读取当前账号本人可见的数据，不提供代刷、代签、批量操作。

### 数据来源与边界

- 通知来自学校各二级单位**公开网页**上的公开信息，只保存标题、发布单位、分类、发布日期与原文链接。
- 本项目**不做加密破解、不逆向登录协议**；页面结构变化可能导致部分功能暂时失效。
- 地图数据来源于 [OpenStreetMap](https://www.openstreetmap.org/)，遵循 Open Database License (ODbL)；地图瓦片与校内标注仅用于校内信息展示与学习交流。

### 免责

本项目为非官方个人学习项目，与上海理工大学、超星学习通、Tronclass 官方无关。
仅供学习和个人使用，请遵守各平台用户协议；如有侵权或不当使用，请联系删除。

## 目前计划

1. **信任与稳定（当前主线）**：发版纪律、文档与实现一致、数据源健康监控、本地诊断。
2. 信息板块继续完善，部分信息可能需要人工提交。
3. 校内导航：仍在规划，方案与数据来源未定；确定后只做少量高频路线。
4. 校园生活服务：已上线，按反馈迭代。
5. 论坛：暂停，等待学校服务器或授权；不采用需要把写权限打包进 App 的方案。
6. AI 问答 / RAG：暂不做。现有本地检索已覆盖主要查询场景，后续有明确需求再评估。

## 架构与工程化规范

项目遵循职责单一、高内聚低耦合的组件化架构设计：

- `lib/pages/classroom/`：空教室与全校排课双 Tab 检索、筛选 BottomSheet 与课程/教室展示卡片。
- `lib/pages/life/`：校园生活服务模块（宿舍电费、签到调度、作业/待办统一聚合、考试列表、快捷服务入口）。
- `lib/pages/today/`：课表主页面、Canvas 高性能网格绘制器、教学周下拉速切组件、智能防冲突莫兰迪配色引擎。
- `lib/data/geo/`：基于 `flutter_map` 的军工路校区离线 OSM 瓦片源、校区经纬度边界与瓦片缓存适配器。
- `lib/data/`：教务系统 CAS 客户端、一网畅学 / 学习通数据桥接层与离线持久化缓存。

## 自动化 CI/CD 与发版流程

本项目已配置基于 GitHub Actions 的自动化中性路径构建流水线（`.github/workflows/release.yml`）：

### 1. 自动打包（Push CI）
- **分支推送自动构建**：每次向 `main` 分支执行 `git push`，CI 将自动拉取代码、运行完整测试用例、以中性路径构建 Release APK 并计算 SHA256，产物可在该次运行的 **Artifacts** 中直接下载测试。
- **防止路径泄露**：中性路径（Ubuntu Runner 根路径）构建避免了 Windows 本机绝对路径或私人用户名被编译进 `libapp.so` 产生隐私泄露。

### 2. 正式发版（Release 触发）
- **方式一（推送 Tag，推荐）**：
  ```bash
  git tag 0.5.8
  git push origin 0.5.8
  ```
  GitHub Actions 检测到版本 Tag 后将自动构建 APK 并直接创建正式的 GitHub Release，附带文件哈希与版本信息。
- **方式二（GitHub 页面一键触发）**：
  进入 GitHub 仓库的 **Actions** 标签页 -> 选择 **release-apk** -> 点击 **Run workflow**，输入版本号与更新说明即可一键发布。

### 3. 本地发版与热更配置（可选备用）

```bash
# 1) 本地打包
flutter build apk --release

# 2) 生成 update.json 配置（计算 sha256 并拼接下载地址）
node tools/release/set-update.mjs \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 0.5.8 --code 34 \
  [--mandatory] --notes "这次改了什么"

# 3) 提交并推送到 Gitee / GitHub
# 4) 发布后自查
node tools/release/check-update.mjs
```

**Release 标题与 tag 规范**：标题统一为 `LiTang-<version>`（如 `LiTang-0.5.8`）；tag 统一为 `<version>`（如 `0.5.8`）。Gitee 侧下载地址按 tag 拼接，GitHub 侧支持 `releases/latest/download`。

**强制更新说明**：添加 `--mandatory` 会将 `minVersionCode` 设定为该版本，低于该版本代码的旧客户端打开时将强制阻断并提示更新；不加则为普通平滑可选更新。

参考项目：


https://github.com/DanXi-Dev/DanXi


https://github.com/BigSilverFish/usst-jwgl-client


如果你有好的想法，欢迎加入我（们？）！QQ:2897010516

## 开源协议

本项目采用 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 开源协议。
地图数据基于 [OpenStreetMap](https://www.openstreetmap.org/) 贡献者（© OpenStreetMap contributors，ODbL 许可）。
本项目为个人非官方学习项目，与上海理工大学官方无关。
