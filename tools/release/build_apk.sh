#!/usr/bin/env bash
set -euo pipefail

# 纯相对路径定位仓库根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/../.." && pwd))"
cd "$REPO_ROOT"

echo "=================================================="
echo " 🚀 立棠 Project_USST 本地极速打包脚本 (Bash)"
echo " 📁 项目根目录: $REPO_ROOT"
echo "=================================================="

# 解析 pubspec.yaml 版本
PUB_VER=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}')
VERSION_NAME=$(echo "$PUB_VER" | cut -d'+' -f1)
VERSION_CODE=$(echo "$PUB_VER" | cut -d'+' -f2)

echo "📌 当前版本: v$VERSION_NAME (Build $VERSION_CODE)"

# 静态分析
echo ""
echo "🔍 正在执行静态代码分析 (flutter analyze)..."
flutter analyze

# 编译 APK
echo ""
echo "🔨 正在编译 Release APK..."
flutter build apk --release

SRC_APK="build/app/outputs/flutter-apk/app-release.apk"
DIST_DIR="dist"
mkdir -p "$DIST_DIR"

TARGET_APK="$DIST_DIR/litang-v$VERSION_NAME.apk"
cp "$SRC_APK" "$TARGET_APK"
cp "$SRC_APK" "$DIST_DIR/app-release.apk"

# 计算 SHA256
if command -v sha256sum >/dev/null 2>&1; then
    SHA256=$(sha256sum "$TARGET_APK" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    SHA256=$(shasum -a 256 "$TARGET_APK" | awk '{print $1}')
else
    SHA256="unknown"
fi

echo "$SHA256" > "$TARGET_APK.sha256"

echo "=================================================="
echo " 🎉 打包完成！"
echo " 📦 产物路径: $TARGET_APK"
echo " 🔑 SHA-256 : $SHA256"
echo "=================================================="
