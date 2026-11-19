#!/usr/bin/env bash
# 轻小说文库 iPad —— macOS 一键打包（未签名 ipa，供企业签/侧载工具重签）
#
# 用法：在 macOS 终端进入项目根目录后执行
#   bash build_ipa.sh
#
# 前置：macOS + Xcode 15+、Flutter SDK 在 PATH、CocoaPods（brew install cocoapods）
# 产物：build/ios/ipa/轻小说文库.ipa（未签名，交由企业签/自签工具处理）

set -euo pipefail

APP_DISPLAY_NAME="轻小说文库"

echo "==> 检查环境"
command -v flutter >/dev/null || { echo "错误: 未找到 flutter，请先安装并加入 PATH"; exit 1; }
command -v pod >/dev/null || { echo "提示: 未检测到 CocoaPods，尝试跳过 pod install（插件无原生依赖时可跳过）"; }

echo "==> 安装依赖"
flutter pub get

if command -v pod >/dev/null; then
  echo "==> CocoaPods"
  (cd ios && pod install)
fi

echo "==> 构建未签名 iOS 产物"
flutter build ios --release --no-codesign

if [ -d "build/ios/iphoneos/Runner.app" ]; then
  echo "==> 组装未签名 .ipa"
  rm -rf build/ios/ipa
  mkdir -p build/ios/ipa/Payload
  cp -R build/ios/iphoneos/Runner.app build/ios/ipa/Payload/Runner.app
  IPA_PATH="build/ios/ipa/${APP_DISPLAY_NAME}.ipa"
  rm -f "$IPA_PATH"
  (cd build/ios/ipa && zip -qry "$OLDPWD/$IPA_PATH" Payload)
  SIZE=$(du -h "$IPA_PATH" | cut -f1)
  echo ""
  echo "=========================================="
  echo "  产物: $IPA_PATH ($SIZE)"
  echo "  状态: 未签名（无 embedded.mobileprovision）"
  echo "=========================================="
  echo ""
  echo "接下来交给你的签名工具："
  echo "  - 企业签服务：直接上传此 ipa，由服务方重签后出下载链接"
  echo "  - TrollStore：直接安装此 ipa（免签）"
  echo "  - 自签工具（爱思助手 / Sideloadly / AltStore）：导入此 ipa 重签"
else
  echo "==> 未找到 Runner.app，请检查上方构建日志"
  exit 1
fi
