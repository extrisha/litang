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

# 解析 pubspec.yaml 版本（规范要求：不带 v）
PUB_VER=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}')
VERSION_NAME=$(echo "$PUB_VER" | cut -d'+' -f1 | sed 's/^v//')
VERSION_CODE=$(echo "$PUB_VER" | cut -d'+' -f2)

echo "📌 当前版本: $VERSION_NAME (Build $VERSION_CODE) [不带 v]"
echo "🏷️ Release Tag: $VERSION_NAME"
echo "📋 Release 标题: LiTang-$VERSION_NAME"

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

# 规范命名：必须统一为 app-release.apk
TARGET_APK="$DIST_DIR/app-release.apk"
cp "$SRC_APK" "$TARGET_APK"

# 计算 SHA256
if command -v sha256sum >/dev/null 2>&1; then
    SHA256=$(sha256sum "$TARGET_APK" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    SHA256=$(shasum -a 256 "$TARGET_APK" | awk '{print $1}')
else
    SHA256="unknown"
fi

echo "$SHA256 *app-release.apk" > "$TARGET_APK.sha256"

echo "=================================================="
echo " 🎉 打包完成！"
echo " 📦 规范命名产物: $TARGET_APK"
echo " 🔑 SHA-256     : $SHA256"
echo " 📄 校验文件    : $TARGET_APK.sha256"
echo "=================================================="
echo "⚠️ 发版与上传规范提示："
echo "   1. Release Tag 必须为: $VERSION_NAME（严禁加 v 前缀，Gitee 依赖 tag 严格一致）"
echo "   2. Release 标题建议为: LiTang-$VERSION_NAME"
echo "   3. 上传附件文件名必须为: app-release.apk"
echo "=================================================="
