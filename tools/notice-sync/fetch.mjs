#!/usr/bin/env node
// 校园通知抓取：并发抓各学院列表页 → 解析成统一结构 → 与历史合并 → 输出 notices.json
//
// 用法：
//   node fetch.mjs                 # 抓取并写入 ../out/notices.json
//   node fetch.mjs --dry           # 只打印结果，不写文件
//   node fetch.mjs --limit 3       # 每个源只取前 3 条（调试用）

import { readFile, writeFile, mkdir, appendFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import dns from 'node:dns';

// GitHub-hosted runner 没有可用的 IPv6 路由，但 usst.edu.cn 同时返回 A 和 AAAA。
// undici 有时先试 AAAA，直接 ENETUNREACH，表现为大量 “fetch failed”。
// 在第一次 fetch 之前强制 IPv4，避免把网络问题误判成站点改版。
dns.setDefaultResultOrder('ipv4first');

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(__dirname, 'out');
const OUT_FILE = join(OUT_DIR, 'notices.json');

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/** 历史保留上限（条数） */
const MAX_HISTORY = 25000;
/** 每条源最多取多少条 */
const PER_SITE_LIMIT = 200;
/** 每个源最多翻多少页（防止改版后无限翻页）
 *  实测只有十来个「大栏目」真的会翻到 10 页以上，其余一页就没「下一页」了。
 *  跟学生关系不大的分类（新闻 / 党群）少翻几页，别把人家服务器打爆。 */
const MAX_PAGES = 12;
const MAX_PAGES_BY_KIND = { 新闻: 5, 党群: 5, 科研: 6 };
/** 只保留近 N 年的通知 */
const KEEP_YEARS = 2;
/** 同时抓多少个站点（同一站点内部串行，避免把人家服务器打爆） */
const HOST_CONCURRENCY = 8;

const args = process.argv.slice(2);
const dry = args.includes('--dry');
const limitArg = args.indexOf('--limit');
const perSiteLimit =
  limitArg >= 0 ? Number(args[limitArg + 1]) || PER_SITE_LIMIT : PER_SITE_LIMIT;

// ---------------------------------------------------------------- HTML 工具

const ENTITIES = {
  '&nbsp;': ' ',
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&ldquo;': '“',
  '&rdquo;': '”',
  '&mdash;': '—',
  '&middot;': '·',
};

function decodeEntities(text) {
  let out = text;
  for (const [k, v] of Object.entries(ENTITIES)) out = out.split(k).join(v);
  // 数字实体
  out = out.replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)));
  return out;
}

function stripTags(html) {
  return decodeEntities(html.replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

/** 清洗候选标题：有的站点把整段 <a> 塞进了 title 属性，需要再剥一层 */
function cleanTitle(raw) {
  let s = String(raw ?? '');
  // title="<a href='...' title='真正的标题'>...</a>" —— 取内层 title
  const nested = s.match(/title\s*=\s*['"]([^'"]{4,})['"]/i);
  if (nested) s = nested[1];
  s = stripTags(s);
  // 剥完还有尖括号说明是残缺标签，宁可丢掉
  return /[<>]/.test(s) ? '' : s;
}

/** 有些模板把「日期 + 标题 + 浏览量」全塞进一个 <a> 里，标题会被带上日期和数字 */
function tidyTitle(raw) {
  let s = String(raw ?? '').trim();
  const hadDate = /^\d{4}[-./年]\d{1,2}[-./月]\d{1,2}日?\s+/.test(s);
  if (hadDate) {
    s = s.replace(/^\d{4}[-./年]\d{1,2}[-./月]\d{1,2}日?\s+/, '');
    // 同一行里的浏览量
    s = s.replace(/\s+\d{1,6}$/, '');
  }
  // 标题后面跟着摘要时，摘要常以「 10月22日上午…」开头，空格 + 日期是很强的分界信号
  const cut = s.replace(/\s+(?=\d{1,2}月\d{1,2}日|\d{4}年).*$/s, '');
  if (cut.length >= 8 && cut.length < s.length) s = cut;
  return s.trim();
}

function absoluteUrl(href, base) {
  try {
    return new URL(href, base).toString();
  } catch {
    return null;
  }
}

/** 解析多种日期写法，统一成 YYYY-MM-DD；失败返回 null
 *  @param yearHint 只有「月-日」时用于补年份（通常从文章 URL 里的 /2026/1022/ 推断）
 */
export function parseDate(raw, yearHint = null) {
  if (!raw) return null;
  const text = String(raw).trim();
  let m = text.match(/(\d{4})[-./年]\s*(\d{1,2})[-./月]\s*(\d{1,2})/);
  if (m) return normalize(m[1], m[2], m[3]);
  // 只有 月-日：用传入的年份，没有再退回当前年
  m = text.match(/^(\d{1,2})[-./](\d{1,2})$/);
  if (m) return normalize(String(yearHint ?? new Date().getFullYear()), m[1], m[2]);
  m = text.match(/(\d{1,2})[-./](\d{1,2})/);
  if (m) return normalize(String(yearHint ?? new Date().getFullYear()), m[1], m[2]);
  return null;
}

/** 从文章链接里取年份：/2026/1022/c... → 2026 */
export function yearFromUrl(url) {
  const m = String(url).match(/\/(\d{4})\/\d{2}\d{2}\//);
  return m ? Number(m[1]) : null;
}

/** 从文章链接里直接取发布日期：/2026/0914/c18415a370397/page.htm → 2026-09-14
 *  webplus 的归档路径就是发布日期，列表页解析失败时这是最可靠的兜底。
 */
export function dateFromUrl(url) {
  const m = String(url).match(/\/(\d{4})\/(\d{2})(\d{2})\/c\d+a\d+/);
  if (!m) return null;
  return normalize(m[1], m[2], m[3]);
}

function normalize(y, mo, d) {
  const year = Number(y);
  const month = Number(mo);
  const day = Number(d);
  if (!(month >= 1 && month <= 12 && day >= 1 && day <= 31)) return null;
  const pad = (n) => String(n).padStart(2, '0');
  return `${year}-${pad(month)}-${pad(day)}`;
}

// ---------------------------------------------------------------- 解析器

/**
 * 解析通知列表。学校各站点用的模板不统一，实测到 5 种容器：
 *   1. <li class="news n1">  + .news_title + .news_date / .news_meta
 *   2. <li class="news">     + .news_wz > .news_title + .news_text
 *   3. <div class="listDetailsItem"> + .listDetailsItemTitle + .listDetailsItemTime
 *   4. 纯 <table> 行：<td><a title="..">..</a></td><td>日期</td>
 *   5. 兜底：任何指向 cXXXaYYY 的 <a>，向前后各取一小段当容器
 *
 * 所以不按容器 class 匹配，而是「以文章链接为锚点」倒推出标题和日期。
 */
export function parseList(html, source) {
  const items = [];
  const seen = new Set();

  // 所有文章链接（webplus 的文章页形如 /2026/1022/c10239a372764/page.htm）
  // 注意：<a> 里常嵌套 <div>/<font>/<img>，所以用「贪婪到下一个 </a>」并单独取 href 属性，
  // 而不是用 <a ...>文本</a> 的整段匹配（遇到嵌套标签会断）。
  const anchorRe = /<a\b([^>]*)>/gi;
  let m;
  while ((m = anchorRe.exec(html))) {
    const attrs = m[1];
    const hrefMatch = attrs.match(/href\s*=\s*["']([^"']+)["']/i);
    if (!hrefMatch) continue;
    const href = hrefMatch[1];
    // webplus 文章页：/2026/1022/c10239a372764/page.htm
    // 页码位数不固定（实测有 a372764、也有 a2），所以都允许
    if (!/\/c\d+a\d+\/|page\.(htm|html|psp)/i.test(href)) continue;

    const url = absoluteUrl(href, source.url);
    if (!url || seen.has(url)) continue;

    // 链接内部的 HTML：从当前 <a> 到它对应的 </a>
    const closeIdx = html.indexOf('</a>', anchorRe.lastIndex);
    const innerHtml = closeIdx > 0
      ? html.slice(anchorRe.lastIndex, closeIdx)
      : '';
    const innerText = stripTags(innerHtml);

    // 标题优先级：
    //   1. 链接附近（内部或其外层最近容器）的明确标题元素，最可靠、不含摘要
    //   2. <a title="...">
    //   3. 链接内文本
    let title = null;
    // 取链接外层一小段（模板1把 .news_title 包在 <a> 外面）
    const outerStart = Math.max(0, m.index - 300);
    const outerHtml = html.slice(outerStart, (closeIdx > 0 ? closeIdx : anchorRe.lastIndex) + 200);
    const titleEl = outerHtml.match(
      /class="[^"]*(?:news_title|ItemTitle|article_title)[^"]*"[^>]*>([\s\S]*?)<\/(?:div|p|h\d|span)>/i,
    );
    if (titleEl) {
      const candidate = cleanTitle(titleEl[1]);
      // 必须包含链接内文本，才认定是这条的标题（避免拿到相邻条目的标题）
      if (candidate && (innerText.length < 4 || candidate.includes(innerText) || innerText.includes(candidate))) {
        title = candidate;
      }
    }
    if (!title) {
      // 注意：有的站点 title 属性里又塞了一整段 <a>（单双引号混用），
      // 所以引号要成对匹配，不能写成 [^"']
      const titleAttr = attrs.match(/\btitle\s*=\s*(?:"([^"]*)"|'([^']*)')/i);
      const raw = titleAttr ? (titleAttr[1] ?? titleAttr[2]) : null;
      if (raw) title = cleanTitle(raw);
    }
    if (!title && innerText.length >= 4) {
      title = cleanTitle(
        innerText.replace(/\s*\d{4}[-./]\d{1,2}[-./]\d{1,2}\s*$/, ''),
      );
    }
    if (!title || title.length < 4) continue;
    title = tidyTitle(title);
    // 兜底截断：标题后面被拼进摘要时，按句号/省略号/长度截
    if (title.length > 60) {
      const cut = title.search(/[。！？；]|\.\.\./);
      title = (cut > 10 ? title.slice(0, cut) : title.slice(0, 60)).trim();
    }
    // 过滤导航类短词
    if (/^(更多|查看更多|ViewMore|阅读全文|详细|详见|查看详情|详情|点击查看|next|prev)/i.test(title)) continue;

    seen.add(url);

    // 文章 URL 里带年份：/2026/1022/c10239a372764/page.htm
    // 列表页只写「10-22」时，用这个年份补全，避免把 2018 年的通知当成今年的。
    const yearHint = yearFromUrl(url);

    // 日期：优先链接内部，其次紧邻的父容器（而不是整个前后窗口，
    // 否则会把相邻条目的日期当成自己的）
    let date = null;
    const innerDate = innerHtml.match(/(\d{4}[-./]\d{1,2}[-./]\d{1,2})/);
    if (innerDate) {
      date = parseDate(innerDate[1], yearHint);
    } else {
      const tailStart = closeIdx > 0 ? closeIdx : anchorRe.lastIndex;
      const window = html.slice(tailStart, Math.min(html.length, tailStart + 4000));
      // 截到本条真正结束的位置（</li> / </tr>），避免跨到下一条
      const endTag = window.search(/<\/li>|<\/tr>/i);
      let after;
      if (endTag >= 0) {
        after = window.slice(0, endTag);
      } else {
        // 没有 li/tr 的模板：切到「下一条文章链接」之前。
        // 紧邻自己的那条摘要链接要跳过，所以取第 2 个匹配位置。
        const re = /<a\b[^>]*href=["'][^"']*\/c\d+a\d+/gi;
        let k = 0;
        let cut = -1;
        let mm;
        while ((mm = re.exec(window))) {
          if (++k === 2) {
            cut = mm.index;
            break;
          }
        }
        after = cut > 0 ? window.slice(0, cut) : window.slice(0, 1200);
      }
      // 去掉本条内部的摘要链接：摘要正文里常写到「截止时间 2026-10-13」，
      // 直接正则会把截止日期当成发布日期
      const noAnchors = after.replace(/<a\b[\s\S]*?<\/a>/gi, ' ');
      let dm = noAnchors.match(/(\d{4}[-./]\d{1,2}[-./]\d{1,2})/);
      if (dm) {
        date = parseDate(dm[1], yearHint);
      } else {
        const sm = noAnchors.match(/(?<!\d)(\d{1,2})[-./](\d{1,2})(?!\d)/);
        if (sm) date = parseDate(`${sm[1]}-${sm[2]}`, yearHint);
      }
    }
    // 兜底：webplus 的归档路径 /2026/0914/c... 就是发布日期
    if (!date) date = dateFromUrl(url);
    // 日期明显晚于今天（比如把文章里的未来日期当成了发布日）就不采信
    if (date && date > new Date().toISOString().slice(0, 10)) date = null;

    items.push({
      id: `${source.id}:${url}`,
      dept: source.dept,
      category: source.category,
      kind: source.kind ?? source.category,
      column: source.column,
      scope: source.scope,
      weight: source.weight ?? 50,
      title,
      url,
      date,
    });
  }

  return items;
}

// ---------------------------------------------------------------- 抓取

async function fetchSite(source, timeoutMs = 25000) {
  const collected = [];
  const seenUrls = new Set();
  let lastError = null;
  let pages = 0;

  // webplus 翻页：list.htm → list2.htm → list3.htm …
  const maxPages = MAX_PAGES_BY_KIND[source.kind] ?? MAX_PAGES;
  for (let page = 1; page <= maxPages; page++) {
    const url = pageUrl(source.url, page);
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const resp = await fetch(url, {
        headers: { 'User-Agent': UA, Accept: 'text/html,*/*' },
        redirect: 'follow',
        signal: ctrl.signal,
      });
      // 第 2 页起 404 = 没有更多页，正常结束
      if (!resp.ok) {
        if (page > 1) break;
        throw new Error(`HTTP ${resp.status}`);
      }
      const html = Buffer.from(await resp.arrayBuffer()).toString('utf8');

      let added = 0;
      for (const item of parseList(html, source)) {
        if (seenUrls.has(item.url)) continue;
        // 「首页直链」类型的源只收指定栏目的文章（学院首页上那些没有列表页的栏目）
        if (source.onlyCids?.length) {
          const cid = (item.url.match(/\/c(\d+)a\d+\//) || [])[1];
          if (!cid || !source.onlyCids.includes(cid)) continue;
        }
        seenUrls.add(item.url);
        collected.push(item);
        added++;
      }
      pages++;

      // 本页没有新内容 = 到底了
      if (added === 0) break;
      if (!hasNextPage(html)) break;
    } catch (e) {
      lastError = e;
      if (page === 1) {
        return {
          source,
          items: [],
          pages: 0,
          status: 'error',
          error: e.name === 'AbortError' ? 'timeout' : String(e.message || e),
        };
      }
      break; // 后续页失败就停，已抓到的保留
    } finally {
      clearTimeout(timer);
    }
  }

  return {
    source,
    items: collected,
    pages,
    status: collected.length > 0 ? 'ok' : 'error',
    error:
      collected.length === 0
        ? String(lastError?.message ?? '无数据')
        : undefined,
  };
}

/** webplus 翻页地址：list.htm → list2.htm */
function pageUrl(base, page) {
  if (page === 1) return base;
  return base.replace(/list(\d*)\.htm(\?.*)?$/i, `list${page}.htm$2`);
}

/** 页面是否还有下一页 */
function hasNextPage(html) {
  // 明确的分页链接（list2.htm / list3.htm …）
  if (/href=["'][^"']*list\d+\.htm["']/i.test(html)) return true;
  return false;
}

// ---------------------------------------------------------------- 合并

function loadPrevious(raw) {
  try {
    const json = JSON.parse(raw);
    if (Array.isArray(json)) return json;
    if (Array.isArray(json.notices)) return json.notices;
  } catch {
    /* 没有历史就当空 */
  }
  return [];
}

function merge(previous, fresh) {
  // 按 URL 去重（一篇文章一个 URL），新的优先
  const byUrl = new Map();
  for (const n of fresh) byUrl.set(n.url, n);
  for (const n of previous) if (n.url && !byUrl.has(n.url)) byUrl.set(n.url, n);

  const all = [...byUrl.values()];
  // 排序：有日期的按日期倒序，没日期的排后面
  all.sort((a, b) => {
    if (a.date && b.date) return b.date.localeCompare(a.date);
    if (a.date) return -1;
    if (b.date) return 1;
    return 0;
  });
  return all.slice(0, MAX_HISTORY);
}

/** 同一标题（去标点空格）只留最新一条，避免同一通知在多个栏目重复出现 */
function dedupe(list) {
  const seen = new Map();
  const out = [];
  for (const n of list) {
    const key = n.title.replace(/[\s\p{P}]/gu, '');
    const prev = seen.get(key);
    if (prev) {
      // 保留日期更新的那条
      if (!prev.date && n.date) {
        seen.set(key, n);
        const i = out.indexOf(prev);
        if (i >= 0) out[i] = n;
      }
      continue;
    }
    seen.set(key, n);
    out.push(n);
  }
  return out;
}

// ---------------------------------------------------------------- main

async function main() {
  const sourcesPath = join(__dirname, 'sources.json');
  const config = JSON.parse(await readFile(sourcesPath, 'utf8'));
  // schemaVersion 3：sources 数组 + enabled 开关；旧版是 sites
  const all = config.sources ?? config.sites ?? [];
  const sites = all.filter((s) => s.enabled !== false);

  console.log(
    `开始抓取 ${sites.length} 个源` +
      (all.length !== sites.length ? `（另有 ${all.length - sites.length} 个未启用）` : '') +
      `，并发 ${HOST_CONCURRENCY} 个站点…`,
  );
  const started = Date.now();

  const results = await runByHost(sites);

  let failed = 0;
  const fresh = [];
  const cutoff = twoYearsAgo();
  let dropped = 0;
  const byKind = new Map();
  const failures = [];
  for (const r of results) {
    const all = r.items;
    // 按近两年截断：无日期的保留（可能只是解析不到，不该丢）
    const kept = all.filter((n) => !n.date || n.date >= cutoff);
    dropped += all.length - kept.length;

    if (r.status === 'ok') {
      const k = r.source.kind ?? r.source.category ?? '其他';
      const s = byKind.get(k) ?? { sources: 0, items: 0 };
      s.sources++;
      s.items += kept.length;
      byKind.set(k, s);
      fresh.push(...kept.slice(0, perSiteLimit));
    } else {
      failed++;
      failures.push(`${r.source.dept} / ${r.source.column ?? r.source.category}  ${r.error}`);
    }
  }

  console.log('\n按分类统计：');
  for (const [k, s] of [...byKind].sort((a, b) => b[1].items - a[1].items)) {
    console.log(`  ${k.padEnd(4)} ${String(s.sources).padStart(3)} 个源  ${String(s.items).padStart(5)} 条`);
  }
  if (failures.length) {
    console.log(`\n失败的源（${failures.length} 个，通常是站点改版或临时不可达）：`);
    for (const f of failures.slice(0, 40)) console.log(`  ❌ ${f}`);
    if (failures.length > 40) console.log(`  …另有 ${failures.length - 40} 个`);
  }

  const failureRatio = sites.length === 0 ? 0 : failed / sites.length;
  const maxFailureRatio = Number(process.env.MAX_FAILURE_RATIO ?? 0.2);
  console.log(
    `\n失败率：${(failureRatio * 100).toFixed(1)}%（${failed}/${sites.length}）`,
  );
  if (process.env.GITHUB_STEP_SUMMARY) {
    const summary = [
      '## 通知抓取',
      `- 源：${sites.length}，失败：${failed}（${(failureRatio * 100).toFixed(1)}%）`,
      `- 新抓：${fresh.length} 条`,
      '',
      ...failures.slice(0, 15).map((f) => `- ${f}`),
      failures.length > 15 ? `- …另有 ${failures.length - 15} 个` : '',
    ];
    await appendFile(process.env.GITHUB_STEP_SUMMARY, `${summary.join('\n')}\n`);
  }
  // 失败太多通常不是“站点改版”，而是 runner 到学校站点的网络不通。
  // 这种情况下不要写一份缺数据的 notices.json，也不要把 CI 装成绿色。
  if (failureRatio > maxFailureRatio) {
    console.error(
      `\n失败源过多（${failed}/${sites.length}，上限 ${(maxFailureRatio * 100).toFixed(0)}%）。` +
        ' 本次不写入产物，保留上一版；请检查 runner 网络 / 改用国内出口。',
    );
    process.exitCode = 1;
    return;
  }

  // 读历史
  let previous = [];
  try {
    previous = loadPrevious(await readFile(OUT_FILE, 'utf8'));
  } catch {
    /* 首次运行 */
  }
  // 历史里也把超过两年的老数据清掉
  const beforePrune = previous.length;
  previous = previous.filter((n) => !n.date || n.date >= cutoff);
  const pruned = beforePrune - previous.length;

  const merged = dedupe(merge(previous, fresh));
  // 输出只留 App 需要的字段：字段名越短、文件越小，手机上拉得越快
  const notices = merged.map((n) => {
    const o = {
      dept: n.dept,
      kind: normalizeKind(n.kind || n.category),
      scope: n.scope || 'school',
      title: n.title,
      url: n.url,
      date: n.date || null,
    };
    return o;
  });
  const payload = {
    schemaVersion: 2,
    updatedAt: new Date().toISOString(),
    total: notices.length,
    notices,
  };

  const elapsed = ((Date.now() - started) / 1000).toFixed(1);
  console.log(
    `\n抓取完成：${fresh.length} 条，合并后 ${merged.length} 条，` +
      `失败 ${failed} 个源，耗时 ${elapsed}s`,
  );
  if (dropped || pruned) {
    console.log(`（超出 ${KEEP_YEARS} 年的旧数据：本次过滤 ${dropped} 条，历史清理 ${pruned} 条）`);
  }

  if (dry) {
    console.log('\n--- 前 5 条 ---');
    for (const n of merged.slice(0, 5)) {
      console.log(`  [${n.date ?? '无日期'}] ${n.dept} | ${n.title}`);
      console.log(`      ${n.url}`);
    }
    return;
  }

  await mkdir(OUT_DIR, { recursive: true });
  // 不缩进：这份文件是给 App 读的，缩进白占 30% 体积
  await writeFile(OUT_FILE, JSON.stringify(payload), 'utf8');
  console.log(`\n已写入 ${OUT_FILE}`);
}

/** 按站点分组：同一站点串行抓，站点之间并发 */
async function runByHost(sources) {
  const byHost = new Map();
  for (const s of sources) {
    let host;
    try {
      host = new URL(s.url).host;
    } catch {
      host = s.url;
    }
    if (!byHost.has(host)) byHost.set(host, []);
    byHost.get(host).push(s);
  }

  const queues = [...byHost.values()];
  const results = [];
  let i = 0;
  async function worker() {
    while (i < queues.length) {
      const q = queues[i++];
      for (const s of q) results.push(await fetchSite(s));
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(HOST_CONCURRENCY, queues.length) }, worker),
  );
  // 保持与配置相同的顺序，日志好读
  const order = new Map(sources.map((s, k) => [s.id, k]));
  results.sort((a, b) => (order.get(a.source.id) ?? 0) - (order.get(b.source.id) ?? 0));
  return results;
}

/** 老数据里存的是栏目名（category），统一归一成 App 认识的 kind */
const KIND_ALIASES = {
  公告信息: '通知',
  公告公示: '通知',
  通知公告: '通知',
  公告: '通知',
  学院新闻: '新闻',
  新闻动态: '新闻',
  要闻: '新闻',
  教学培养: '教学',
  科研通知: '科研',
  产学研合作: '科研',
  职业领航: '就业',
  部务信息: '通知',
  学工动态: '学工',
};

function normalizeKind(raw) {
  const k = String(raw ?? '').trim();
  if (!k) return '通知';
  return KIND_ALIASES[k] ?? k;
}

/** 近 N 年的起始日期（YYYY-MM-DD） */function twoYearsAgo() {
  const d = new Date();
  d.setFullYear(d.getFullYear() - KEEP_YEARS);
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// 只在直接运行时执行（被 import 做单测时不跑）
if (process.argv[1] && process.argv[1].endsWith('fetch.mjs')) {
  main().catch((e) => {
    console.error('抓取失败：', e);
    process.exit(1);
  });
}
