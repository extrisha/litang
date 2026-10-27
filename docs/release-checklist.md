# 发版清单（Android APK）

> 用途：把「发版」从凭记忆变成固定动作。每次发版复制本清单，逐项勾选；全部完成才算发布结束。
> 适用渠道：GitHub Release + Gitee Release（双源）。

## 0. 发版前

- [ ] 版本号已确定：`pubspec.yaml` 的 `version: x.y.z+build`（build 必须比上一版大）
- [ ] `git fetch --all`，确认 `main` 与 `origin/main` 的差异；自动通知同步提交不要漏
- [ ] 工作区状态清楚：要么干净，要么明确列出本次要带的全部改动
- [ ] `flutter analyze` 无 error（warning 逐条确认，不放大）
- [ ] `flutter test` 全绿
- [ ] 手工冒烟：首页通知、搜索、地图、教务登录、课表、提醒
- [ ] 检查没有把本机路径、调试开关、测试密钥带进包
- [ ] README / 纪要里的版本与状态是否需要同步更新

## 1. 构建

- [ ] 从**中性路径**构建（例如 `C:\build\litang`），不要直接在 `C:\Users\<用户名>\...` 下构建，否则绝对路径会写进 `libapp.so`
- [ ] `flutter build apk --release`
- [ ] 产物：`build/app/outputs/flutter-apk/app-release.apk`
- [ ] 在真机安装一次：能启动、版本号正确、首屏正常

## 2. 生成 update.json

```bash
node tools/release/set-update.mjs \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version x.y.z --code <build> \
  [--mandatory] --notes "用户能看懂的变化"
```

- [ ] `version` 与 tag 完全一致（**不带 `v`**）
- [ ] `versionCode` 已递增
- [ ] `sha256` 与 APK 实际值一致
- [ ] Gitee 下载地址按 `version` 拼接正确
- [ ] `notes` 面向用户，不写内部接口名和实现细节
- [ ] 只有确实需要强制升级时才加 `--mandatory`
- [ ] **三处一致**：`pubspec.yaml` / `update.json` / Release tag

## 3. 发布

- [ ] 提交并推送 `main`
- [ ] GitHub Release：tag 与 `version` 一致，上传 `app-release.apk`
- [ ] Gitee Release：tag 与 `version` **完全一致**（不要 `v` 前缀），附件同名 `app-release.apk`
- [ ] 确认两个 Release 都是已发布状态，不是 draft
- [ ] `node tools/release/check-update.mjs` 全绿
- [ ] 用旧版本客户端实际点一次更新，确认弹窗与下载链接可用（至少确认 200/302）

## 4. 备份

- [ ] `Project_USST_backups/v<版本>-full/app-release.apk`
- [ ] 备份 `update.json` 快照，便于回溯
- [ ] 备份目录不要提交进仓库

## 5. 发布后 24 小时

- [ ] 两个渠道的下载链接都没有 404
- [ ] 没有集中的安装失败 / 启动崩溃反馈
- [ ] 如果本次强制更新，确认低版本客户端能正常弹窗
- [ ] 把本次踩到的坑补进纪要

## 回滚策略

优先发补丁版（`build +1`），而不是把旧包重新挂上去：

- 已经升级的用户不会“降级”，回退 `update.json` 通常无效；
- 严重问题：发修复版，必要时把 `minVersionCode` 设为修复版，强制升级；
- 保留上一版 APK、`update.json` 和 Release，便于对照。

## 常见坑

| 现象 | 原因 |
|---|---|
| Gitee 下载 404 | tag 写成 `v0.4.4`，而清单拼的是 `0.4.4` |
| 用户收不到更新 | 忘记改 `update.json`，或只推了代码没建 Release |
| Release 点了但下载不到 | Release 是 draft，或没上传附件 |
| 包体泄漏本机路径 | 从带用户名的绝对路径构建 |
| 国内下载失败 | 只发了 GitHub，没发 Gitee |
| 强制更新不生效 | 客户端低于 0.4.2，不认识 `minVersionCode` |

## 版本记录（发版后补一行）

| 版本 | 日期 | 主要内容 | 强制 | 备注 |
|---|---|---|---|---|
| 0.4.4 | 2026-10-27 | 通知搜索、签到修复、登录验证码、学院筛选 | 否 | GitHub / Gitee 双源已发布 |
