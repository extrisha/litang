# 理堂

上海理工大学校园助手，Flutter 客户端（Android 为主）。非官方个人项目。

## 功能

- **首页**：全校 63 个二级单位站点通知聚合（7000+ 条），按竞赛 / 教学 / 讲座等分类筛选，本院优先
- **搜索**：本地通知检索（标题 / 部门 / 分类），完全离线，不依赖服务端
- **今日课表**：Canvas 绘制网格，多周次切换
- **校园服务**：空教室查询、全校课程检索、研讨空间预约、宿舍电费
- **上理体育**：内嵌网页版，查体测成绩、订体育场馆（手机号登录，会话留在 WebView）
- **学习通**：课程、作业、考试、讨论、活动签到（数字口令 / 扫码 / 雷达 / 拍照）
- **一网畅学（TronClass）**：课程、待办、考试、课件与签到
- **学业档案**：成绩、绩点、专业排名、培养方案进度
- **提醒**：作业与考试提醒、校历联动、客户端版本自动检测与更新
- **地图**：官方手绘校园图（已配准到真实经纬度）、地点检索、课表一键定位教室
- **论坛**：仍在规划，当前页面为示例数据，入口暂时保留

## 隐私

- 「记住登录」**默认开启**，可在登录页关闭；关闭后只保存会话 cookie。已保存的教务凭据可在「我的」点「退出」清除。
- 密码与 cookie 只在本机使用，不上传、不写日志、不经过本项目服务器（本项目没有服务器）。
- 登录后只读取当前账号本人可见的数据，不提供代刷、代签、批量操作。

## 数据来源与边界

- 通知来自学校各二级单位**公开网页**上的公开信息，只保存标题、发布单位、分类、发布日期与原文链接。
- 本项目**不做加密破解、不逆向登录协议**；页面结构变化可能导致部分功能暂时失效。
- 地图底图为学校官方发布的校园示意图，仅用于校内信息展示；其经纬度由 [OpenStreetMap](https://www.openstreetmap.org/)（ODbL）的建筑轮廓做控制点配准反推，平均误差约 17 m。配准脚本见 `tools/map/georef_campus_map.py`，参数与精度见 `scratch/georef_report.md`。

## 开发

需要 Flutter stable（Dart SDK `^3.13.5`）、Android SDK 与 JDK 17。

```bash
flutter pub get
flutter test                # 单元与 widget 测试，必须全绿
dart analyze lib test       # 必须 No issues found
dart format lib test        # 提交前跑一次，应幂等
```

### 目录

```
lib/
├─ data/       网络、解析、缓存、模型
│  ├─ auth/        CAS / 教务登录态
│  ├─ chaoxing/    学习通
│  ├─ lms/         一网畅学（TronClass）
│  ├─ jwc/         教务：成绩、排名、空间预约、排课
│  ├─ geo/         坐标转换（WGS-84 ↔ GCJ-02）
│  └─ campus_labels.dart / campus_tiles.dart  图内标签与底图瓦片的经纬度
├─ pages/      页面（classroom / life / today …）
├─ services/   跨页面服务：提醒、天气、更新、小组件同步
└─ widgets/    复用组件：三态视图、遮罩式异步任务、带 cookie 的 WebView
```

## 发版

发版本地打包（CI 自动发版已停用，见下方说明）：

```bash
# 1. 改版本号（两处都要，versionCode 必须递增）
#    pubspec.yaml: version: 0.6.1+36
#    update.json : version / versionCode / notes / sha256
# 2. 打包
node tools/release/build_apk.mjs
# 3. 校验
node tools/release/check-update.mjs
```

- **产物**：`dist/app-release.apk` 与 `dist/app-release.apk.sha256`
- **Release 标题**：`LiTang-<version>`；**tag**：`<version>`（不带 `v`，Gitee 下载地址按 tag 拼接）
- **更新说明**：`node tools/release/build_apk.mjs --update --notes "…"` 会回写 `update.json`
- **强制更新**：加 `--mandatory` 会把 `minVersionCode` 设为该版本，旧客户端打开即阻断；不加则为平滑可选更新

> **为什么不用 GitHub Actions 发版**：正式包用本地密钥签名，且 `update.json` 钉住了 APK 的
> SHA-256。CI 构建出的包哈希必然不同，没有签名密钥时还会退回 debug 签名，用户装不上也校验不过。
> 因此 `.github/workflows/release.yml` 已停用，只保留通知同步流水线。

## 参考项目

- [DanXi-Dev/DanXi](https://github.com/DanXi-Dev/DanXi)
- [BigSilverFish/usst-jwgl-client](https://github.com/BigSilverFish/usst-jwgl-client)

## 开源协议

本项目采用 [GNU General Public License v3.0 (GPL-3.0)](LICENSE)。
地图数据 © OpenStreetMap contributors（ODbL）。

本项目为非官方个人学习项目，与上海理工大学、超星学习通、TronClass 官方无关。仅供学习和个人使用，
请遵守各平台用户协议；如有侵权或不当使用，请联系删除。

有想法或问题欢迎提 Issue。
