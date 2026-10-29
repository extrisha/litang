#!/usr/bin/env node
/**
 * 本地一键极速打包 Release APK 脚本
 *
 * 遵循项目规范文件 (tools/release/set-update.mjs 及 update.json)：
 * 1. 版本号统一不带 'v' 前缀（如 0.5.7，非 v0.5.7），保证 Gitee release tag 与 update.json 严格对应；
 * 2. 安装包统一命名为 app-release.apk，保证 GitHub latest 与 Gitee tag 下载直链可用；
 * 3. 100% 相对路径驱动，无任何机器环境绝对路径；
 * 4. 产物输出至 dist/app-release.apk 并生成 dist/app-release.apk.sha256；
 * 5. 可选联动 tools/release/set-update.mjs 自动更新 update.json 清单。
 *
 * 用法：
 *   node tools/release/build_apk.mjs
 *   node tools/release/build_apk.mjs --skip-test
 *   node tools/release/build_apk.mjs --update --notes "修复课表显示异常"
 */

import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..', '..');
const DIST_DIR = join(ROOT, 'dist');
const PUBSPEC_PATH = join(ROOT, 'pubspec.yaml');
const RELATIVE_ROOT = relative(process.cwd(), ROOT) || '.';

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`) || args.includes(`-${name[0]}`);
const value = (name) => {
  const i = args.findIndex((a) => a === `--${name}` || a === `-${name[0]}`);
  return i >= 0 ? args[i + 1] : null;
};

const skipTest = flag('skip-test');
const splitAbi = flag('split-abi');
const updateManifest = flag('update');
const notes = value('notes') ?? '修复已知问题，提升稳定性与流畅度。';

function runCmd(command, cmdArgs) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, cmdArgs, {
      cwd: ROOT,
      stdio: 'inherit',
      shell: true,
    });
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`命令 "${command} ${cmdArgs.join(' ')}" 退出码异常: ${code}`));
    });
  });
}

async function main() {
  const startTime = Date.now();
  console.log('==================================================');
  console.log(' 🚀 立棠 Project_USST 本地极速打包助手');
  console.log(` 📁 根目录: ${RELATIVE_ROOT} (纯相对定位)`);
  console.log('==================================================');

  // 1. 读取版本号（规范要求：绝不带 v 前缀）
  const pubspecRaw = await readFile(PUBSPEC_PATH, 'utf8');
  const match = pubspecRaw.match(/^version:\s*([^\s+]+)(?:\+([^\s+]+))?/m);
  if (!match) {
    throw new Error('无法从 pubspec.yaml 解析 version 字段！');
  }
  let versionName = match[1].trim();
  if (versionName.startsWith('v')) {
    versionName = versionName.slice(1);
  }
  const versionCode = match[2] || '1';

  console.log(`📌 当前版本: ${versionName} (Build ${versionCode}) [规范：不带 v]`);
  console.log(`🏷️ Release Tag: ${versionName}`);
  console.log(`📋 Release 标题: LiTang-${versionName}`);

  // 2. 静态分析检查
  if (!skipTest) {
    console.log('\n🔍 正在执行静态代码分析 (flutter analyze)...');
    await runCmd('flutter', ['analyze']);
    console.log('✅ 静态代码分析通过');
  } else {
    console.log('\n⚠️ 已跳过静态分析 (--skip-test)');
  }

  // 3. 构建 APK
  console.log('\n🔨 正在编译 Release APK...');
  const flutterArgs = ['build', 'apk', '--release'];
  if (splitAbi) {
    flutterArgs.push('--split-per-abi');
    console.log('💡 已启用架构分包模式 (--split-per-abi)');
  }

  const buildStart = Date.now();
  await runCmd('flutter', flutterArgs);
  const buildSec = ((Date.now() - buildStart) / 1000).toFixed(1);
  console.log(`✅ Release APK 编译完成（耗时 ${buildSec} 秒）`);

  // 4. 收集产物并严格规范命名为 app-release.apk
  const sourceApk = join(ROOT, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
  const apkStat = await stat(sourceApk).catch(() => null);
  if (!apkStat || !apkStat.isFile()) {
    throw new Error(`未找到构建产物: ${sourceApk}`);
  }

  await mkdir(DIST_DIR, { recursive: true });

  const targetApk = join(DIST_DIR, 'app-release.apk');
  await copyFile(sourceApk, targetApk);

  const apkBytes = await readFile(targetApk);
  const sha256 = createHash('sha256').update(apkBytes).digest('hex');
  const sha256Path = join(DIST_DIR, 'app-release.apk.sha256');
  await writeFile(sha256Path, `${sha256} *app-release.apk\n`, 'utf8');

  const sizeMb = (apkStat.size / (1024 * 1024)).toFixed(2);
  const totalSec = ((Date.now() - startTime) / 1000).toFixed(1);

  console.log('\n==================================================');
  console.log(` 🎉 打包成功！总耗时: ${totalSec} 秒`);
  console.log('==================================================');
  console.log(` 📦 规范命名产物: dist/app-release.apk (统一命名规范)`);
  console.log(` 📏 文件大小    : ${sizeMb} MB (${apkStat.size.toLocaleString()} 字节)`);
  console.log(` 🔑 SHA-256     : ${sha256}`);
  console.log(` 📄 校验和文件  : dist/app-release.apk.sha256`);

  // 5. 可选更新 update.json
  if (updateManifest) {
    console.log('\n📝 正在同步写入 update.json...');
    const setUpdateScript = join(__dirname, 'set-update.mjs');
    await runCmd('node', [
      setUpdateScript,
      '--apk', targetApk,
      '--version', versionName,
      '--code', versionCode,
      '--notes', notes,
    ]);
  }

  console.log('\n--------------------------------------------------');
  console.log('⚠️ 发版与上传规范提示：');
  console.log(`   1. Release Tag 必须为: ${versionName}（严禁加 v 前缀，Gitee 依赖 tag 严格一致）`);
  console.log(`   2. Release 标题建议为: LiTang-${versionName}`);
  console.log(`   3. 上传附件文件名必须为: app-release.apk`);
  console.log('--------------------------------------------------');
}

main().catch((err) => {
  console.error('\n❌ 打包流程中断:', err.message || err);
  process.exit(1);
});
