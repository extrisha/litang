#!/usr/bin/env node
// 发版助手：把打出来的 APK 写进 update.json（版本号 / sha256 / 下载地址 / 是否强制）
//
// 用法：
//   node tools/release/set-update.mjs --apk path/to/app-release.apk \
//        --version 0.4.2 --code 16 [--mandatory] [--notes "更新说明"]
//
// 说明：
//   - 不给 --mandatory 时 minVersionCode 写 0，也就是「可选更新」，用户可以跳过；
//   - 给了 --mandatory 就把它设成这次的 versionCode —— 低于这个版本的客户端
//     （且是 0.4.2 及以后、认识这个字段的）会被要求先更新才能用；
//   - GitHub 用 releases/latest/download，跟 tag 前缀无关（踩过 v0.4.0 的坑）；
//   - Gitee 没有等价的最新版地址，只能写死 tag，所以发版时 tag 必须和 --version 一致。

import { createHash } from 'node:crypto';
import { readFile, writeFile, stat } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..', '..');
const MANIFEST = join(ROOT, 'update.json');

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const value = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : null;
};

const apkPath = value('apk');
const version = value('version');
const code = Number(value('code'));
const notes = value('notes') ?? '';
const mandatory = flag('mandatory');
const dry = flag('dry');

if (!apkPath || !version || !Number.isFinite(code) || code <= 0) {
  console.error(
    '用法: node tools/release/set-update.mjs --apk <apk> --version 0.4.2 --code 16 [--mandatory] [--notes "…"] [--dry]',
  );
  process.exit(2);
}

const info = await stat(apkPath).catch(() => null);
if (!info || !info.isFile()) {
  console.error(`找不到 APK: ${apkPath}`);
  process.exit(2);
}

const sha256 = createHash('sha256')
  .update(await readFile(apkPath))
  .digest('hex');

const manifest = {
  version,
  versionCode: code,
  minVersionCode: mandatory ? code : 0,
  notes:
    notes ||
    '修复若干问题，提升稳定性。',
  apk_github:
    'https://github.com/extrisha/litang/releases/latest/download/app-release.apk',
  apk_gitee: `https://gitee.com/extrisha/litang/releases/download/${version}/app-release.apk`,
  sha256,
};

console.log('即将写入 update.json:');
console.log(JSON.stringify(manifest, null, 2));
console.log(`\nAPK: ${(info.size / 1048576).toFixed(2)} MB`);
console.log(`强制更新: ${mandatory ? `是（低于 ${code} 的版本必须升级）` : '否（用户可以跳过）'}`);
console.log(`Release 标题: LiTang-${version}（GitHub / Gitee 保持一致）`);
console.log(`Release tag: ${version}（Gitee 必须一致，不要加 v）`);
console.log('上传文件名: app-release.apk');

if (dry) {
  console.log('\n--dry：没有写文件');
  process.exit(0);
}

await writeFile(MANIFEST, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
console.log(`\n已写入 ${MANIFEST}`);
