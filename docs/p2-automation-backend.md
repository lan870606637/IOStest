# P2 自动化后端层

- 日期：2026-10-29
- 分支：`feature/appium-backend`
- 结果：**完成并通过端到端 smoke**，App 工程构建成功

## 1. 交付内容

| 文件 | 职责 |
|---|---|
| `iOSStressTestTool/Services/Automation/AutomationBackend.swift` | 后端协议、能力声明、元素句柄、错误类型、硬件按钮 |
| `iOSStressTestTool/Services/Automation/AppiumClient.swift` | Appium W3C 协议 HTTP 客户端（session/source/element/actions/screenshot/keys） |
| `iOSStressTestTool/Services/Automation/AppiumBackend.swift` | 协议到 Appium 命令的映射（tap/swipe/longPress/type/pressButton） |
| `iOSStressTestTool/Services/Automation/AppiumServerManager.swift` | Appium 进程自启、端口选择、健康检查、日志、退出清理 |
| `iOSStressTestTool/Services/Automation/DeviceSessionManager.swift` | 一设备一会话、并发去重、会话复用与关闭 |
| `iOSStressTestTool/Models/Locator.swift` | 控件定位模型（accessibility id / label / predicate / class chain / xpath / point） |
| `iOSStressTestTool/Utils/HostEnvironment.swift` | Developer mode、xcode-select、Xcode、Appium、driver 自检 |

工程接入：`project.pbxproj` 新增 `Automation` 分组与 7 个文件引用，App target 构建通过。

## 2. 关键设计

### 一设备一会话
`DeviceSessionManager` 用 `udid -> sessionId` 复用会话；同一设备的并发创建请求合并到同一个 `Task`，避免重复建会话。目标 `bundleId` 变化时先关闭旧会话再重建。

### Appium 服务自启
`AppiumServerManager` 是 actor：
- 优先复用 `127.0.0.1:4723` 上已经在跑的 Appium；
- 否则在 4723–4740 里找空闲端口，拉起 `appium` 子进程；
- 启动环境带 `APPIUM_HOME`、`DEVELOPER_DIR`、Homebrew PATH；
- 轮询 `/status` 直到 ready（最多 60 秒），日志写到 `~/Library/Application Support/iOSStressTestTool/logs/appium-server.log`；
- 退出时 terminate，1.5 秒后仍在则 SIGKILL。

### Locator 模型
`Locator` 支持 6 种策略，`label` 会自动转成 `-ios predicate string`；`point` 不查元素，直接用 `x/y`。`Codable` 对缺失字段做了容错，为 P3 把 `locator` 挂到 `TestEvent` 做准备。

### 环境自检
`HostEnvironment.checks()` 覆盖本次踩坑的两个系统配置：
- `Developer mode` 关闭 → 直接给 `sudo /usr/sbin/DevToolsSecurity -enable`
- `xcode-select` 指向 CLT → 直接给 `sudo xcode-select -s ...`

后续 P4 接到设置页/启动自检。

## 3. 验证

用独立 CLI harness（`.tools/smoke/Smoke.swift`，编译时把 7 个新文件 + Logger/ProcessRunner 一起编）跑通：

```text
[正常] Developer mode: 已启用
[正常] xcode-select: /Applications/Xcode.app/Contents/Developer
[正常] Appium: .tools/appium/node_modules/.bin/appium
[正常] XCUITest driver: .tools/appium-home
appium: http://127.0.0.1:4723
source chars: 40645
element rect: (16.0, 293.0, 370.0, 53.0)
after tap contains 关于本机: true
screenshot bytes: 319109
SMOKE OK
```

总耗时 **38 秒**（含 Appium 启动 + 建会话），WDA 构建缓存命中。

## 4. 已知边界

1. `typeText` 走 `/keys`，尚未在输入框上验证，P3 补。
2. 真机 WDA 签名未验证（P5）。
3. iOS 27 仍受 macOS 26.4 + Xcode 27 工具链限制。
4. `AppiumServerManager.stop()` 目前只杀 Node 进程，WDA/xcodebuild 子进程可能残留；P4 做进程组清理。
5. `Locator.timeout` 尚未在执行器里使用（P3 实现等待/重试）。

## 5. 下一步（P3）

- `TestEvent` 增加 `locator: Locator?`，保持旧 JSON 可读
- 执行器改为「控件优先 → 坐标 → OCR/图像」降级链
- 等待/重试/超时，报告记录实际使用的策略
