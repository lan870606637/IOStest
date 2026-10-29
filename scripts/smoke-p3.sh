#!/usr/bin/env bash
#
# P3/P6 集成 smoke：编译真实 EventExecutor + Appium 后端，跑控件定位与坐标回退。
#
# 前置：
#   1. Xcode 已选中（xcode-select -p 指向 Xcode）
#   2. Developer mode 已启用（DevToolsSecurity -status）
#   3. Appium 与 XCUITest driver 已装在 .tools（见 docs/spike-appium-ios26.md）
#   4. 目标模拟器存在
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
UDID="${SMOKE_UDID:-1C408430-2229-47F2-89C0-76F94BDAF16C}"
APPIUM_BIN="$ROOT/.tools/appium/node_modules/.bin/appium"

if [[ ! -x "$APPIUM_BIN" ]]; then
  echo "缺少 Appium：$APPIUM_BIN"
  echo "先执行：npm install --prefix .tools/appium appium@3"
  exit 1
fi

echo "== 启动模拟器 $UDID =="
xcrun simctl bootstatus "$UDID" -b >/dev/null

OUT="$ROOT/.tools/smoke/p3smoke"
mkdir -p "$(dirname "$OUT")"

echo "== 编译 smoke =="
xcrun swiftc -swift-version 5 -parse-as-library -o "$OUT" \
  iOSStressTestTool/Models/TestEvent.swift \
  iOSStressTestTool/Models/TestTask.swift \
  iOSStressTestTool/Models/TestReport.swift \
  iOSStressTestTool/Models/DeviceInfo.swift \
  iOSStressTestTool/Models/AppConfig.swift \
  iOSStressTestTool/Models/Locator.swift \
  iOSStressTestTool/Utils/Logger.swift \
  iOSStressTestTool/Utils/ProcessRunner.swift \
  iOSStressTestTool/Utils/CoordinateAdapter.swift \
  iOSStressTestTool/Utils/ImageCompareUtils.swift \
  iOSStressTestTool/Utils/GoIOSClient.swift \
  iOSStressTestTool/Utils/HostEnvironment.swift \
  iOSStressTestTool/Services/DeviceService.swift \
  iOSStressTestTool/Services/ScreenshotService.swift \
  iOSStressTestTool/Services/EventExecutor.swift \
  iOSStressTestTool/Services/ImageRecognitionEngine.swift \
  iOSStressTestTool/Services/OCREngine.swift \
  iOSStressTestTool/Services/ReportGenerator.swift \
  iOSStressTestTool/Services/Automation/AutomationBackend.swift \
  iOSStressTestTool/Services/Automation/AppiumClient.swift \
  iOSStressTestTool/Services/Automation/AppiumServerManager.swift \
  iOSStressTestTool/Services/Automation/DeviceSessionManager.swift \
  iOSStressTestTool/Services/Automation/AppiumBackend.swift \
  scripts/smoke/P3Smoke.swift

echo "== 执行 smoke =="
SMOKE_UDID="$UDID" "$OUT"
