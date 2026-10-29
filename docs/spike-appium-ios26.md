# Appium 接入 Spike 报告

- 日期：2026-10-29
- 分支：`feature/appium-backend`（基线提交 `8d08cdc`）
- 环境：Mac mini M1 / 8 GB / macOS 26.3.1 / Xcode 26.6（iOS 26.5 SDK）
- 结论：**Appium 链路搭通、WDA 构建成功，但 XCTest 测试执行被本机开发者模式/工具链配置阻塞**

## 1. 已完成

| 项 | 结果 |
|---|---|
| 基线提交 + 功能分支 | 完成（`8d08cdc`，`feature/appium-backend`） |
| 现有工程构建 | `** BUILD SUCCEEDED **` |
| Appium 3 安装（工作区内） | `appium@3.9.0`，装在 `.tools/appium`（已 gitignore） |
| XCUITest 驱动 | `xcuitest@12.22.3`，装在 `.tools/appium-home` |
| 驱动自检 | `appium driver doctor xcuitest`：0 个必须修复项（仅缺可选的 applesimutils/ffmpeg） |
| Appium 服务 | 正常启动，`GET /status` 返回 ready |
| WDA 构建 | `** TEST BUILD SUCCEEDED **`（WDA 16.17.6） |

## 2. 阻塞现象

创建 Appium session 时，WDA 已安装并启动，但测试用例不执行：

```text
[Xcode] ** TEST BUILD SUCCEEDED **
[Xcode] WebDriverAgentRunner-Runner[81873] [Default] Running tests...
（之后无任何 WDA 日志，8100 端口始终未监听）
```

testmanagerd 日志显示握手在最后一步断掉：

```text
Received new test session connection from process with PID 81873
Initiating serialized transport handoff from IDE connection to test host.
Closing session <XCIDESession: ...> ... waiting to pair with test session ...
DTXSocketTransport for socket 5 disconnected ... waiting to pair ...
```

## 3. 关键判断：不是 Appium 的问题

用**纯 xcodebuild**（不经过 Appium）复现了同样的卡死：

```bash
xcodebuild test-without-building \
  -project .tools/appium-home/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -derivedDataPath .tools/DerivedData \
  -destination 'id=<simulator-udid>' \
  -only-testing:WebDriverAgentRunner/UITestingUITests/testRunner
```

- iOS 26.4 模拟器：卡住
- iOS 26.5 模拟器：卡住
- 全新创建的 `WDA-Spike` 模拟器：同样卡住

因此问题在 **Xcode/本机 XCTest 运行环境**，不在 Appium、也不在模拟器个体状态。

## 4. 本机两个可疑配置

```bash
$ /usr/sbin/DevToolsSecurity -status
Developer mode is currently disabled.

$ xcode-select -p
/Library/Developer/CommandLineTools
```

1. **Developer mode 关闭**：`xcodebuild test` 的 test host 授权可能被 taskgated 拦住，表现为 testmanagerd 握手无法完成。
2. **xcode-select 指向 CommandLineTools**：部分子进程（如诊断阶段调用的 `xcrun simctl`）不继承 `DEVELOPER_DIR`，会报 `unable to find utility "simctl"`。应用内 `ProcessRunner` 已做 workaround，但系统级工具不会。

两项都需要管理员权限修改。

## 5. 解除阻塞（需要 sudo）

在 Mac 上的终端执行：

```bash
sudo DevToolsSecurity -enable
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

验证：

```bash
/usr/sbin/DevToolsSecurity -status   # 应显示 enabled
xcrun simctl list devices | head     # 应能直接找到 simctl
```

## 6. 复验步骤

1. 启动模拟器（推荐 iOS 26.5）：

```bash
xcrun simctl boot 1C408430-2229-47F2-89C0-76F94BDAF16C
xcrun simctl bootstatus 1C408430-2229-47F2-89C0-76F94BDAF16C -b
```

2. 手动跑 WDA：

```bash
xcodebuild test-without-building \
  -project .tools/appium-home/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj \
  -scheme WebDriverAgentRunner \
  -derivedDataPath .tools/DerivedData \
  -destination 'id=1C408430-2229-47F2-89C0-76F94BDAF16C'
```

预期看到 `Server started on port 8100`，且 `Running tests...` 之后有测试用例日志。

3. WDA 能起来后，再跑 Appium session 验证 `source` + `tap`。

## 7. 如果仍然卡住

按优先级尝试：

1. 重启 Mac（清理 CoreSimulator/testmanagerd 状态）。
2. 升级到 macOS 26.4+ / Xcode 27（iOS 27 本来也要求这套工具链）。
3. 用另一台已启用开发者模式的 Mac 交叉验证。
4. 在 Appium 侧加 `-collect-test-diagnostics never` 仅用于排除诊断收集问题（当前卡点在测试启动前，预计无效）。

## 8. 产物与清理

- 基线提交：`8d08cdc`，分支 `feature/appium-backend`
- 本地 Appium：`.tools/appium`（gitignored）
- 驱动与 WDA：`.tools/appium-home`（gitignored）
- WDA 构建缓存：`.tools/DerivedData`（gitignored）
- 日志：`.tools/appium-server*.log`、`.tools/manual-wda*.log`
- 临时模拟器 `WDA-Spike` 已删除，Appium 服务已停止
