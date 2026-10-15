# Sticky

macOS 悬浮便签。纸条约 232pt 宽，无标题，置顶，可拖动。

每一家一行两行字：上面是名字和剩余用量百分比，下面的进度条**长度**是距离重置的天数（30 天铺满轨道），**填充**是剩余用量。天数贴在进度条尾巴上，例如 `3天`、`26天`、`30天`，0 天显示 `今天`。

底部小字：条长是剩余天数，填充是剩余用量。

顺序固定为 Cursor、Grok、Mimo、Grok Bot。Cursor 读本机登录态并请求当前账期；另外三家还没有接口，显示「未接入」，不会填示例数字。

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

## 计算库

`Sources/StickyCore` 不依赖 AppKit。装了 Swift 的机器上可以只跑这部分测试：

```sh
cd Sticky
swift test
```

便签界面是 macOS 应用，用上面的 Xcode 工程编译。Linux 上没有 Xcode，编不了这个界面。
