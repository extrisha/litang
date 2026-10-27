#!/usr/bin/env node
// 发版后自查：清单里的下载地址到底通不通
//
// 用法：node tools/release/check-update.mjs
//
// 会检查：
//   1. update.json 本体是否可访问（GitHub / Gitee 两个源，App 就是这么取清单的）
//   2. 清单里的安装包地址（GitHub latest / Gitee 指定 tag / tag 换个 v 前缀）
//   3. 最新 Release 到底有没有挂附件（这是最常见的 404 来源）

import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..', '..');

const UA = 'Litang-Release-Check';

const manifests = [
  'https://raw.githubusercontent.com/extrisha/litang/main/update.json',
  'https://gitee.com/extrisha/litang/raw/main/update.json',
];

async function head(url) {
  try {
    const res = await fetch(url, {
      method: 'HEAD',
      redirect: 'manual',
      headers: { 'User-Agent': UA },
    });
    return { status: res.status, size: res.headers.get('content-length') };
  } catch (e) {
    return { status: 0, error: e.message };
  }
}

function ok(status) {
  return status >= 200 && status < 400;
}

let failed = 0;

console.log('=== 清单 ===');
for (const url of manifests) {
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA } });
    const json = JSON.parse(await res.text());
    console.log(
      `${ok(res.status) ? '✅' : '❌'} ${url.includes('gitee') ? 'gitee ' : 'github'} ` +
        `${json.version} (${json.versionCode}) min=${json.minVersionCode ?? 0} sha=${String(json.sha256).slice(0, 12)}`,
    );
    if (!ok(res.status)) failed++;
  } catch (e) {
    console.log(`❌ ${url} 取不到：${e.message}`);
    failed++;
  }
}

console.log('\n=== 安装包地址 ===');
const local = JSON.parse(await readFile(join(ROOT, 'update.json'), 'utf8'));
const primary = [local.apk_github, local.apk_gitee].filter(Boolean);
let primaryOk = false;
let reachable = 0;

for (const url of primary) {
  const r = await head(url);
  const size = r.size ? ` ${(Number(r.size) / 1048576).toFixed(1)}MB` : '';
  if (r.status === 0) {
    // 本机网络到不了这个源（常见于 GitHub 直连），不代表 Release 有问题
    console.log(`⚠️  连接失败（本机网络？）  ${url}`);
    continue;
  }
  reachable++;
  console.log(`${ok(r.status) ? '✅' : '❌'} ${r.status}${size}  ${url}`);
  if (ok(r.status)) primaryOk = true;
  else failed++;
}

if (primary.length > 0 && reachable === 0) {
  console.log('⚠️ 两个源都连不上，安装包地址这项跳过（请换网络后再查）');
}

// tag 的 v 前缀是客户端会自动兜底的写法，主地址通了就不算问题
const m = /\/download\/([^/]+)\//.exec(local.apk_gitee ?? '');
if (m) {
  const tag = m[1];
  const alt = tag.startsWith('v') ? tag.slice(1) : `v${tag}`;
  const altUrl = local.apk_gitee.replace(m[0], `/download/${alt}/`);
  const r = await head(altUrl);
  const label = ok(r.status) ? '✅' : primaryOk ? '➖' : '❌';
  console.log(`${label} ${r.status}  ${altUrl}   ← 备选写法（客户端会自动试）`);
  if (!ok(r.status) && !primaryOk) failed++;
}

console.log('\n=== 最新 Release ===');
try {
  const res = await fetch(
    'https://api.github.com/repos/extrisha/litang/releases?per_page=3',
    { headers: { 'User-Agent': UA, Accept: 'application/vnd.github+json' } },
  );
  const list = await res.json();
  // 只要求「最新那个」有附件：latest 就是指向它，老版本空着无所谓
  list.forEach((rel, index) => {
    const assets = (rel.assets ?? []).map((a) => a.name).join(', ');
    const hasAsset = (rel.assets ?? []).length > 0;
    const mark = hasAsset ? '✅' : index === 0 ? '❌' : '➖';
    const note = hasAsset ? '' : index === 0 ? '（没有附件，latest 会 404）' : '（历史版本，忽略）';
    const title = rel.name ?? '（无标题）';
    console.log(`${mark} ${rel.tag_name}  ${title}  ${assets || '（无）'}${note}`);
    if (index === 0 && title !== `LiTang-${rel.tag_name}`) {
      console.log(`   ⚠ 标题建议改为 LiTang-${rel.tag_name}（只改标题，不影响下载）`);
    }
    if (!hasAsset && index === 0) failed++;
  });
} catch (e) {
  console.log(`❌ 查询 Release 失败：${e.message}`);
  failed++;
}

console.log(
  failed === 0
    ? '\n全部通过，更新链路是通的'
    : `\n有 ${failed} 项不通过 —— 最常见的原因是 Release 建好了但没传 APK（文件名要叫 app-release.apk）`,
);
process.exit(failed === 0 ? 0 : 1);
