# 通知抓取（服务端）

把全校各站点（学院 + 机关 + 直属单位，共 63 个二级站点）的通知/新闻抓成
一个统一的 `notices.json`，App 只拉这个文件，不再让每台设备各自去爬学校站点。

## 流程

```
sites.json          ← 手工维护：全校 63 个站点的域名 / 部门名
      │
      ▼  discover-all.mjs    （本地跑，几分钟）
discovery/<host>.json      ← 每个站点发现了哪些栏目、有多少文章、最新日期
      │
      ▼  build-sources.mjs   （本地跑，秒级）
sources.json        ← 栏目级配置：分类(kind)、权重、是否启用
      │
      ▼  fetch.mjs           （CI 每天 3 次）
out/notices.json    ← App 拉取的产物
```

只有 `fetch.mjs` 会在 CI 里跑；`discover` / `build-sources` 是改版或想扩源时才在本地重跑。

## 为什么不能"按导航名字配源"

踩过的坑，都写进代码了：

1. **栏目名像通知 ≠ 活跃栏目**。正确做法是从首页文章链接里的 `c<栏目id>a<文章id>` 反推活跃栏目，
   再验证 `list.htm` 非空。
2. **学院站点每页侧栏都挂"学院新闻"**。如果按"本页出现最多的 cid"判断栏目 id，
   所有栏目会塌缩成一个 —— 所以先统计跨页面高频出现的 cid 并剔除。
3. **首页"孤儿栏目"多半有列表页**。首页只链文章、不给"更多"链接而已，
   探一下 `/<cid>/list.htm` 基本都能出来（主站 www 例外，它只认命名目录，所以用 `seeds` 手工补）。
4. **少数栏目连列表页都没有**（`/<cid>/list.htm` 返回"提示信息"）。
   这类用 `type: "home"` 的"首页直链"源兜底：把首页当列表页，只收指定 cid 的文章。
5. **主站 www 的导航是 JS 渲染的**，首页 HTML 里根本没有"通知公告"的链接，
   所以在 `sites.json` 里用 `seeds` 手工补了 `/tzgg/list.htm`。

## 目录

```
tools/notice-sync/
├── sites.json            # 全校站点清单（加站点只改这里）
├── discover-all.mjs      # 栏目发现：抓首页 → 探列表页 → 去侧栏干扰 → 写 discovery/
├── build-sources.mjs     # 由 discovery/ 生成 sources.json（分类、权重、启用开关）
├── sources.json          # 抓取源配置（549 个栏目，启用 470 个，含若干「首页直链」兜底源）
├── fetch.mjs             # 抓取 + 解析 + 合并历史
├── fetch.test.mjs        # 解析器单测（实测到的 8 种模板/坑）
├── check-stats.mjs       # 看一眼产物的分布
├── discovery/<host>.json # 每站点的栏目发现结果（可作为"有没有漏"的审计底稿）
└── out/notices.json      # 产物（CI 自动提交）
```

## 本地运行

```bash
# 1) 重新发现栏目（可选，改版了才需要；全量约 4 分钟）
node tools/notice-sync/discover-all.mjs                 # 全部站点，并发 6
node tools/notice-sync/discover-all.mjs me jcxb www     # 只跑指定站点

# 2) 重新生成源配置
node tools/notice-sync/build-sources.mjs --dry          # 先看分类统计
node tools/notice-sync/build-sources.mjs                # 写入 sources.json

# 3) 抓取
node tools/notice-sync/fetch.mjs --dry                  # 只预览
node tools/notice-sync/fetch.mjs                        # 写入 out/notices.json（约 20 秒）
node --test tools/notice-sync/fetch.test.mjs            # 单测
```

## 分类（kind）

`sources.json` 里每个栏目有一个 `kind`，决定 App 怎么展示、以及要不要默认启用：

| kind | 说明 | 权重 | 默认启用 |
|---|---|---|---|
| `竞赛` | 学科竞赛、创新创业、大创 | 95 | ✅ |
| `教学` | 教学运行、考务、培养计划、教材 | 90 | ✅ |
| `通知` | 通知公告、公示、部务信息 | 88 | ✅ |
| `讲座` | 讲座、论坛、学术报告 | 85 | ✅ |
| `学工` | 学生工作、奖助、宿舍、迎新 | 80 | ✅ |
| `就业` | 就业、招聘、实习 | 75 | ✅ |
| `科研` | 科研动态、项目申报、成果 | 60 | ✅ |
| `招生` | 本科/研究生/留学生招生 | 55 | ✅ |
| `新闻` | 学院新闻、要闻、快讯 | 45 | ✅ |
| `党群` | 党建、工会、团委、纪检 | 25 | ❌ |
| `下载` | 资料下载、规章制度 | 15 | ❌ |

`教务处 / 本科生院 / 研究生院` 的栏目额外 +12 权重，主站 +10。

## 自动化

`.github/workflows/sync-notices.yml`：每天 3 次定时抓取（UTC 08/13/22），
改了 `tools/notice-sync/` 下的脚本或配置也会立刻跑一次；
跑完自动提交 `out/notices.json`；配了 `GITEE_TOKEN` secret 时还会镜像到
`gitee:extrisha/lit-Calendar`（国内加速用）。

### CI 网络：IPv6 坑（重要）

`fetch.mjs` 需要访问全校 63 个 `.usst.edu.cn` 站点。GitHub-hosted `ubuntu-latest`
**没有可用的 IPv6 路由**，而学校域名同时返回 A 和 AAAA；Node 的 `fetch` 有时先试
AAAA，直接 `ENETUNREACH`，在 Actions 里表现为大量 `fetch failed`（实测 432/470，
本地同一份代码只失败 8 个）。

我们在 workflow 里跑过诊断：

- `curl -4` / `https.get({family:4})` 对 `jwc / www / me` 都是 200；
- `curl -6` / `family:6` 全是 `ENETUNREACH`；
- 在第一次 fetch 前调用 `dns.setDefaultResultOrder('ipv4first')` 后，
  `fetch` 对 4 个测试站点全部 200。

但要注意：**只修 IPv4，全量 470 个源实测仍然 432 个 `fetch failed`**。
又把并发降到 1、每请求加 1.5 秒延迟跑 40 个源，仍然 **37/40 失败**。
说明 GitHub runner 的 IP 还被学校 WAF/线路挡着；IPv4 只能解决单个请求的
`ENETUNREACH`，降速也不能绕过。所以 `fetch.mjs` 会在最前面强制 IPv4，
**不要只依赖 `NODE_OPTIONS`**；workflow 里还保留了：

- `Diagnose runner network` 步骤：打印 DNS / IPv4 / IPv6 结果；
- 失败率超过 `MAX_FAILURE_RATIO`（默认 20%）时退出码 1、不写产物；
- `GITHUB_STEP_SUMMARY` 失败统计。

如果强制 IPv4 后仍然大面积失败，再考虑国内出口（见下）。

### 兜底：免费的国内自托管 runner

GitHub 仓库设置 → Actions → Runners → New self-hosted runner，
在一台**国内常开的电脑 / 旧笔记本**上按提示装 runner，加一个 `china` 标签，
然后把 workflow 的 `runs-on` 改成：

```yaml
runs-on: [self-hosted, china]
```

其他步骤（checkout / setup-node / fetch / commit / Gitee 镜像）都不用改，
GitHub 继续负责定时、日志、secrets 和仓库托管，不需要 Gitee Go。
代价是机器要在定时点在线；电脑会关机的话，把 cron 调到常用的时间段，
或者醒来后手动 `workflow_dispatch` 一次。

## 数据结构

```json
{
  "schemaVersion": 2,
  "updatedAt": "2026-10-25T12:41:00.000Z",
  "total": 7456,
  "notices": [
    {
      "dept": "基础学部",
      "kind": "竞赛",
      "scope": "college",
      "title": "【统计建模】2026年（第十二届）全国大学生统计建模大赛上海理工大学校赛获奖名单公告",
      "url": "https://jcxb.usst.edu.cn/2026/0914/c18415a370397/page.htm",
      "date": "2026-09-14"
    }
  ]
}
```

| 字段 | 说明 |
|---|---|
| `dept` | 发布部门 / 学院 |
| `kind` | 见上面的分类表 |
| `scope` | `school` 全校级 / `college` 学院级，用于"本院优先"排序 |
| `title` | 标题（已去掉摘要、导航词） |
| `url` | 原文地址 |
| `date` | `YYYY-MM-DD`；列表页没写日期时用文章 URL 里的归档日期兜底 |

文件不缩进（`JSON.stringify` 无空格），同样的内容能省 30% 体积（7.7k 条约 1.7 MB）。

## 维护

- **加站点**：`sites.json` 加一条 → 跑 `discover-all.mjs <host>` → 跑 `build-sources.mjs`。
- **加栏目**：如果只是某个命名目录没被发现，在 `sites.json` 对应站点加 `seeds: ["...list.htm"]`。
- **临时关掉某个源**：把 `sources.json` 里那条的 `enabled` 改成 `false`。
- **学院改版**：先手动 `curl` 看新结构，再在 `fetch.test.mjs` 补 fixture，最后调 `parseList`。
- **历史**：每次抓取和 `out/notices.json` 合并（按 URL 去重、按标题去重），
  只保留近 2 年、最多 25000 条。

## 抓取节奏

- 同一站点内部串行、站点之间并发 8 个，避免把某个站点打爆。
- 每个源最多翻 12 页（新闻/党群 5 页、科研 6 页）；没有"下一页"链接就停。
- 全量 453 个源约 20 秒抓完（本地网络），CI 里因为跨境一般 3~8 分钟。

## 已知情况

| 站点 | 状态 |
|---|---|
| 就业信息服务网 `91.usst.edu.cn` | SPA（数智就业平台），没有 webplus 列表页，抓不到 |
| 校报 `newspaper.usst.edu.cn` | 独立 CMS，不是 `cXXXaYYY` 结构，暂未接入 |
| 学生档案 `sfile.usst.edu.cn` | 同上，且内容以查询服务为主 |
| 中英国际学院 | `sbc.usst.edu.cn` 502，实际站点在 `www.sbc.usst.edu.cn`（已接入） |
| 计算中心/基建处/技术转移 | 站点本身近两年几乎没更新 |
