# Sticky

macOS 悬浮便签。纸条约 232pt 宽，无标题，置顶，可拖动。

每一家一行两行字：上面是名字和剩余用量百分比，下面的进度条**长度**是距离重置的天数（30 天铺满轨道），**填充**是剩余用量。天数贴在进度条尾巴上，例如 `3天`、`26天`、`30天`，0 天显示 `今天`。

底部小字：条长是剩余天数，填充是剩余用量。

顺序为 Cursor、Mimo、MiniMax、MiniMax 周、Grok Bot。Cursor 和 MiniMax 读本机登录态。MiniMax 是 5 小时额度，MiniMax 周是周额度。没有登录或没有套餐时只显示灰色原因，不会填示例数字。

## 在 Xcode 里打开并运行

需要 macOS 13 或更新版本，以及 Xcode 15 或更新版本。

1. 把仓库放到 Mac 上。
2. 打开工程：

   ```sh
   open Sticky/Sticky.xcodeproj
   ```

3. 方案选择 **Sticky**，运行目标选择 **My Mac**。
4. 按 Run（Command-R）。

如果签名失败，在 Signing & Capabilities 里选 **Sign to Run Locally**。工程没有打开 App Sandbox，否则读不到 Cursor 的登录数据库，也发不出用量请求。

窗口没有关闭按钮。左键拖动便签；右键可以选择「刷新」或「退出」。菜单栏 **Sticky → 退出**，或按 Command-Q，同样可以退出。

窗口出现时会刷新，之后大约每 5 分钟再刷新一次。位置会记住。

## Cursor 用量

令牌来自当前登录的 Cursor：

`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`

表 `ItemTable`，键 `cursorAuth/accessToken`。请先在这台 Mac 上登录 Cursor。

请求：

`POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`

正文是 `{}`。剩余百分比是 `planUsage.remaining / planUsage.limit`（两者都是美分）。不用 `totalPercentUsed`，那个字段是已用百分比。重置天数来自 `billingCycleEnd`。令牌缺失或请求失败时，这一行只显示名字和一句灰色原因，不会编造百分比。

## Mimo 用量与恢复

平时读 gitignore 的 `Sticky/.mimo-session`（Cookie 行），请求 `tokenPlan/usage` 与 `tokenPlan/current`。失败或未登录时，名字右侧会出现外链图标，点开套餐页。

可选恢复：Chrome 打开 `chrome://extensions` → 开发者模式 →「加载已解压的扩展程序」→ 选 `chrome-extension/`。打开套餐页后，扩展用 `chrome.cookies` 读取 HttpOnly Cookie，把用量 JSON 推到本机 `http://127.0.0.1:17321/mimo-usage`。页面控制台过滤 `[StickyMimo]`。也可继续用 `userscripts/mimo-usage.user.js`（Tampermonkey）；不要把 Cookie 写进仓库。

## MiniMax 用量

令牌来自本机已登录的 MiniMax Code，不会写入仓库。先读 `~/.minimax/local-runtime.auth.json` 的 `auth.accessToken`，没有再读 `~/Library/Application Support/MiniMax/Cookies` 里 `www.minimaxi.com` 的 `_token`。

请求：

`GET https://www.minimaxi.com/backend/account/token_plan/remains_percent`

请求头是 `token`。只取 `model_name` 为 `general` 的编程额度，不把视频次数算进来。已用百分比是 `current_interval_used_percent / current_interval_total_percent`（周额度用 `current_weekly_*`）。字段可以是数字，也可以是 `4%` 这样的字符串。重置时间用 `start_time`/`end_time`，周额度用 `weekly_start_time`/`weekly_end_time`，都是 unix 毫秒。

## 计算库

`Sources/StickyCore` 不依赖 AppKit。装了 Swift 的机器上可以只跑这部分测试：

```sh
cd Sticky
swift test
```

便签界面是 macOS 应用，用上面的 Xcode 工程编译。Linux 上没有 Xcode，编不了这个界面。
