# Appium 接入 Spike 报告

- 日期：2026-10-29
- 分支：`feature/appium-backend`（基线提交 `8d08cdc`）
- 环境：Mac mini M1 / 8 GB / macOS 26.3.1 / Xcode 26.6（iOS 26.5 SDK）
- 结论：**通过** —— Appium 3 + XCUITest 在 iOS 26.5 模拟器上同时跑通「控件定位」和「坐标点击」

## 1. 结果

| 项 | 结果 |
|---|---|
| 基线提交 + 功能分支 | ✅ `8d08cdc` / `feature/appium-backend` |
| 现有工程构建 | ✅ `** BUILD SUCCEEDED **` |
| Appium | ✅ 3.9.0（`.tools/appium`） |
| XCUITest 驱动 | ✅ 12.22.3（`.tools/appium-home`） |
| `appium driver doctor xcuitest` | ✅ 0 个必须修复项 |
| WDA | ✅ 16.17.6，冷构建约 9 分钟，热会话约 30 秒 |
| 创建 session | ✅ 29.9 秒（`bundleId=com.apple.Preferences`，iOS 26.5） |
| 拉取控件树 | ✅ 40,645 字符 |
| 控件定位 | ✅ `-ios predicate string: name == "BackButton"` |
| 坐标点击 | ✅ `mobile: tap {x:201,y:320}` 进入「通用」 |
| 控件点击 | ✅ 点击 BackButton 返回设置首页 |
| 截图 | ✅ 1206×2622 PNG |
| 删除 session | ✅ |

## 2. 验证过程

### 2.1 会话

```bash
curl -X POST http://127.0.0.1:4723/session \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":{"alwaysMatch":{
    "platformName":"iOS",
    "appium:automationName":"XCUITest",
    "appium:udid":"1C408430-2229-47F2-89C0-76F94BDAF16C",
    "appium:platformVersion":"26.5",
    "appium:bundleId":"com.apple.Preferences",
    "appium:noReset":true,
    "appium:derivedDataPath":"/Users/macmini/Desktop/IOStest/.tools/DerivedData"
  }}}'
```

返回 `http=200`，session id `80ca2feb-...`。

### 2.2 控件定位 + 坐标点击

- `POST /session/{id}/element`，`using=-ios predicate string`，`value=label == "通用"`
- `GET /session/{id}/element/{eid}/rect` 返回 `{x:16, y:293, width:370, height:53}`
- 用**坐标**点击中心点：`mobile: tap {x:201, y:320}`
- 重新拉 source，出现「关于本机」「软件更新」，确认进入「通用」页

### 2.3 控件点击返回

- `POST /session/{id}/element`，`value=name == "BackButton"`
- `POST /session/{id}/element/{eid}/click`
- source 回到设置首页（「关于本机」消失），截图确认

## 3. 关键前置：Developer mode

首次 spike 卡在：

```text
WebDriverAgentRunner-Runner[...] [Default] Running tests...
（之后无日志，8100 不监听）
```

testmanagerd 日志停在：

```text
Initiating serialized transport handoff from IDE connection to test host.
Closing session ... waiting to pair with test session ...
```

用纯 `xcodebuild test-without-building`（不经 Appium）、iOS 26.4/26.5、全新模拟器均复现，确认不是 Appium 问题。

根因是两项系统配置：

```text
$ /usr/sbin/DevToolsSecurity -status
Developer mode is currently disabled.

$ xcode-select -p
/Library/Developer/CommandLineTools
```

修复：

```bash
sudo /usr/sbin/DevToolsSecurity -enable
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

修复后 `xcodebuild test-without-building` 立即出现：

```text
Test Case '-[UITestingUITests testRunner]' started.
WebDriverAgentRunner-Runner[...] Server started on port 8100
```

**这条要写进 App 的环境自检**：启动前检查 `DevToolsSecurity -status` 和 `xcode-select -p`，不满足时直接提示用户，而不是让 session 卡死。

## 4. 对本项目的直接影响

1. Appium 方案可行，控件 + 坐标两条通道都验证通过。
2. 冷启动 WDA 构建约 9 分钟，必须做 **WDA 预构建/复用**，否则每次启动会话都不可接受。
3. 8 GB 内存下 Xcode 构建 + 模拟器 + Appium 同时跑很吃紧，App 里要避免并发构建。
4. 真机还差 WDA 签名（P5），iOS 27 还差 macOS 26.4 + Xcode 27（P1 工具链）。
5. 应用内 `ProcessRunner` 的 `DEVELOPER_DIR` workaround 可以保留，但系统级 `xcode-select` 修好后不再是必需。

## 5. 可复现命令

```bash
cd /Users/macmini/Desktop/IOStest
export APPIUM_HOME="$PWD/.tools/appium-home"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 启动服务
.tools/appium/node_modules/.bin/appium --address 127.0.0.1 --port 4723

# 另开终端建会话（见 2.1），然后：
# GET  /session/{id}/source
# POST /session/{id}/execute/sync  {"script":"mobile: tap","args":[{"x":201,"y":320}]}
# POST /session/{id}/element       {"using":"-ios predicate string","value":"name == \"BackButton\""}
# POST /session/{id}/element/{eid}/click
# GET  /session/{id}/screenshot
# DELETE /session/{id}
```

## 6. 产物

- 分支：`feature/appium-backend`
- 基线提交：`8d08cdc`
- 本报告提交：见 `git log`
- 本地 Appium / 驱动 / WDA：`.tools/`（gitignored）
- 日志：`.tools/appium-server*.log`、`.tools/manual-wda*.log`
- 临时模拟器 `WDA-Spike` 已删除；Appium 服务与 WDA 进程已停止
