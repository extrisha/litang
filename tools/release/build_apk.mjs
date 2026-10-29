#!/usr/bin/env node
/**
 * 本地一键极速打包 Release APK 脚本
 *
 * 特性：
 * 1. 100% 相对路径驱动，自动通过模块路径锚定项目根目录，跨盘符、跨机器、跨平台开箱即用；
 * 2. 动态读取 pubspec.yaml 版本号，绝不硬编码；
 * 3. 产物规范化归档至 ./dist/，自动计算 SHA-256 并生成校验文件；
 * 4. 可选自动联动 tools/release/set-update.mjs 更新 update.json；
 * 5. 耗时仅约 1 分钟，完全绕过 GitHub Actions 云端虚拟机的冗长冷启动排队。
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
  console.log(` 📁 项目根目录: ${RELATIVE_ROOT} (纯相对定位)`);
  console.log('==================================================');

  // 1. 读取版本号
  const pubspecRaw = await readFile(PUBSPEC_PATH, 'utf8');
  const match = pubspecRaw.match(/^version:\s*([^\s+]+)(?:\+([^\s+]+))?/m);
  if (!match) {
    throw new Error('无法从 pubspec.yaml 解析 version 字段！');
  }
  const versionName = match[1];
  const versionCode = match[2] || '1';
  console.log(`📌 当前版本: v${versionName} (Build ${versionCode})`);

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

  // 4. 收集产物与校验
  const sourceApk = join(ROOT, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
  const apkStat = await stat(sourceApk).catch(() => null);
  if (!apkStat || !apkStat.isFile()) {
    throw new Error(`未找到构建产物: ${sourceApk}`);
  }

  await mkdir(DIST_DIR, { recursive: true });

  const targetName = `litang-v${versionName}.apk`;
  const targetApk = join(DIST_DIR, targetName);
  const standardApk = join(DIST_DIR, 'app-release.apk');

  await copyFile(sourceApk, targetApk);
  await copyFile(sourceApk, standardApk);

  const apkBytes = await readFile(targetApk);
  const sha256 = createHash('sha256').update(apkBytes).digest('hex');
  await writeFile(`${targetApk}.sha256`, sha256, 'utf8');

  const sizeMb = (apkStat.size / (1024 * 1024)).toFixed(2);
  const totalSec = ((Date.now() - startTime) / 1000).toFixed(1);

  console.log('\n==================================================');
  console.log(` 🎉 打包成功！总耗时: ${totalSec} 秒`);
  console.log('==================================================');
  console.log(` 📦 产物路径: dist/${targetName}`);
  console.log(`    标准副本: dist/app-release.apk`);
  console.log(` 📏 文件大小: ${sizeMb} MB (${apkStat.size.toLocaleString()} 字节)`);
  console.log(` 🔑 SHA-256 : ${sha256}`);
  console.log(` 📄 校验文件: dist/${targetName}.sha256`);

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

  console.log('\n👉 产物已输出至 dist 目录，可直接传输安装或发布至网盘/Releases。');
}

main().catch((err) => {
  console.error('\n❌ 打包流程中断:', err.message || err);
  process.exit(1);
});
