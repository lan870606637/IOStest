# P3–P6 状态报告

- 日期：2026-10-29
- 分支：`feature/appium-backend`
- 结论：**P3 完成、P4 主体完成、P5 被硬件/工具链阻塞、P6 回归通过**

## 1. P3 事件与执行器（完成）

### 模型
- `TestEvent` 新增 `locator: Locator?`，旧 JSON 没有该字段时解码为 `nil`。
- `EventReportData` 新增 `strategy`，记录本次实际使用的执行策略。
- `ReportGenerator.endEvent` 支持写入 strategy，HTML 报告也会显示。

### 执行器
`EventExecutor` 改为「控件优先 → 坐标 → CLI 兜底」：

- 点击：`waitForElement`（按 `Locator.timeout` 轮询 250ms）→ `element click`；找不到控件回退坐标。
- 双击/长按：定位控件 → 取 `rect` 中心 → 坐标双击/长按。
- 滑动：Appium `mobile: dragFromToForDuration`，失败回退 `DeviceService`。
- 文本/硬件按键/启动/终止/截图：Appium 优先，失败回退 CLI。
- 图像识别/OCR：截图优先走 Appium，点击走统一 `tap` helper。
- 任务开始前预建会话，避免第一条事件等 30 秒。
- 每个事件结束后把策略写进报告。

### 验证
`scripts/smoke-p3.sh` 用真实 `EventExecutor` 跑：

```text
locator roundtrip: Predicate: label == "通用"
old json locator: nil (OK)
session ready
locator click: success
entered general: true
coordinate click: success
back to root: true
report: locator click success strategy= 控件 Predicate: label == "通用"
report: coordinate back success strategy= 坐标 (38, 84)
P3 SMOKE OK
```

耗时约 23 秒（WDA 缓存命中）。

## 2. P4 UI 接入（主体完成）

- **事件编辑器**：点击/双击/长按增加「控件定位」区，支持策略、匹配值、超时、匹配序号，并提示失败回退坐标。
- **控件检查器**：从事件编辑器打开，拉取 `mobile: source` 树，可搜索、点选节点，自动生成 accessibility id / label / predicate，并回填坐标兜底。
- **设置页**：环境检测改为真实自检（Developer mode / xcode-select / Xcode / Appium / XCUITest driver），失败项直接给出可复制命令；新增「Appium 服务」启停与日志入口。
- **屏幕预览**：点击/长按/滑动/Home/音量/锁屏改为 Appium 优先，失败回退 CLI；状态栏不再显示误导性的「真机需 go-ios UI 后端」。
- **报告页**：事件行展示实际策略。
- **服务退出**：`AppiumServerManager.stop()` 递归清理子进程（xcodebuild / WDA runner），已验证 smoke 后无残留。

### 未完成
- 预览第一次点击会触发建会话（约 30 秒），状态栏有「连接自动化会话...」提示；后续可在选中设备时预热。
- 设备管理页未展示会话状态。
- `typeText`、`launchApp`、`terminateApp` 已实现但未纳入 smoke。
- 控件检查器的解析/点选逻辑已编译通过，但未做人工 UI 点选验证。

## 3. P5 真机 / iOS 27（阻塞）

### 现状
```text
xcrun devicectl list devices
iPhonexs. Max ... unavailable   (iPhone XS Max, 最高 iOS 18)

xcodebuild -version → Xcode 26.6
sw_vers → macOS 26.3.1
simctl runtimes → iOS 26.4 / 26.5
```

阻塞原因：
1. 没有可用的 iOS 27 真机（XS Max 最高 iOS 18，且当前未连接）。
2. 项目没有配置 `DEVELOPMENT_TEAM`，无法给 WDA 签名。
3. iOS 27 需要 macOS ≥ 26.4 + Xcode 27 + iOS 27 runtime，当前工具链不满足。

### 解锁步骤
1. 连接真机、信任电脑、打开开发者模式。
2. Xcode 登录开发者账号，确认 Team ID。
3. Appium capabilities 增加：
   ```json
   "appium:xcodeOrgId": "<TEAMID>",
   "appium:xcodeSigningId": "Apple Development",
   "appium:updatedWDABundleId": "com.yourco.WebDriverAgentRunner"
   ```
4. 升级 macOS 26.4+、Xcode 27，安装 iOS 27 runtime。
5. 确认 Appium XCUITest driver ≥ 11.11.2（当前 12.22.3），WDA ≥ 14.0.0。
6. 用真实 UDID 跑 `scripts/smoke-p3.sh`（`SMOKE_UDID=<真机 UDID>`）。

## 4. P6 回归（通过）

| 项 | 结果 |
|---|---|
| App target 构建（Xcode 26.6） | ✅ `** BUILD SUCCEEDED **` |
| P3 集成 smoke | ✅ 23 秒，控件/坐标/报告策略全通过 |
| 进程清理 | ✅ smoke 结束后无 Appium/WDA 残留 |
| 旧任务 JSON 兼容 | ✅ 缺 locator 字段解码为 nil |
| 模拟器矩阵 | iOS 26.5 通过；iOS 26.4 可用同一 runtime 逻辑 |
| 真机矩阵 | ⏸ P5 阻塞 |

### 待补测试
- `typeText` 在真实输入框上的验证。
- `launchApp` / `terminateApp` 的 Appium 路径验证。
- 长按、双击、滑动在 Appium 路径上的行为验证（代码已接入，smoke 只覆盖点击）。
- Locator 各策略（accessibility id / label / class chain / xpath）逐个验证。
- 控件检查器的人工 UI 点选验证。
- 单元测试 target（当前只有集成 smoke）。

## 5. 下一步

1. 接一台 iOS 27 真机并配置签名（P5）。
2. 升级 macOS 26.4 + Xcode 27，跑 iOS 27 模拟器 smoke。
3. 补元素检查器与预览预热（P4 收尾）。
4. 扩 smoke 覆盖 typeText / 长按 / 滑动 / 启动终止。
