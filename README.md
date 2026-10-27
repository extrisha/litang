# 理堂

上海理工大学校园助手，Flutter 客户端。


⚠Vibe Coding⚠


持续开发中...更多功能敬请等待...



## 功能与开源范围

本仓库是「理堂」的完整源码（**不是裁剪版**），包含：

- 首页：校园通知聚合（全校 63 个二级站点、7000+ 条，按竞赛/教学/讲座等分类筛选，本院优先）
- 地图：自绘校园地图（瓦片加载、地点搜索、双击课程定位教室）
- 我的：课表、成绩、绩点、专业排名、培养计划
- 学习通：课程、作业、考试、讨论、签到（数字口令 / 扫码 / 雷达）
- 一网畅学（Tronclass）：课表、待办、考试、课件
- 校历、作业/考试提醒、自动更新

### 关于登录

- 教务、学习通、一网畅学都走**学校/平台的官方登录页面**（App 内嵌 WebView），
  密码只在你自己的页面上输入，不经过本项目代码，也不会被保存；
- 登录后只把会话 cookie 用系统级加密（Keystore / Keychain）存在本机，
  不上传、不写日志、不经过任何服务器；
- 所有请求都是你自己账号的数据，App 不提供任何代刷、代签、批量操作。

### 免责

本项目为非官方个人学习项目，与上海理工大学、超星学习通、Tronclass 官方无关。
仅供学习和个人使用，请遵守各平台用户协议；如有侵权或不当使用，请联系删除。

目前计划：


1.做完整的信息板块，部分信息可能需要人工提交


2.地图支持校内导航


3.校园生活服务#DONE


4.支持查询宿舍水电费等


5.论坛（？？？）


## 发布流程

```bash
# 1) 打包（从「中性路径」构建，避免把本机用户名写进 libapp.so）
flutter build apk --release

# 2) 写 update.json（会自动算 sha256、拼下载地址）
node tools/release/set-update.mjs \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 0.4.4 --code 20 \
  [--mandatory] --notes "这次改了什么"

# 3) 提交 + 推送，然后在 GitHub / Gitee 建 Release
#    上传 APK 并重命名为 app-release.apk

# 4) 本地备份：Project_USST_backups/v<版本>-full/app-release.apk
#    文件夹名沿用 v0.4.2-full 这种格式，APK 统一叫 app-release.apk
```

**tag 规则**：Gitee 的 tag 必须和 `--version` 完全一致（写成 `0.4.4`，不要 `v0.4.4`），
清单里的 Gitee 地址是按这个拼的；GitHub 侧用的是 `releases/latest/download`，不挑 tag。

**强制更新**：加 `--mandatory` 会把 `minVersionCode` 设成这一版的版本号，
低于它的客户端启动时会被要求先更新（弹窗不可关闭，带「手动下载」兜底）；
不加就是普通可选更新。注意 0.4.1 及更早的客户端不认识这个字段，只有 0.4.2+ 受管。

参考项目：


https://github.com/DanXi-Dev/DanXi


https://github.com/BigSilverFish/usst-jwgl-client


如果你有好的想法，欢迎加入我（们？）！QQ:2897010516

个人学习项目，与上海理工大学官方无关；地图版权归学校所有，仅用于校内信息展示。
