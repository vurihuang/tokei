# Tokei(时计)

macOS menu bar 小工具(SwiftBar 插件),显示 **Claude Code + Codex** 的本地 token 用量、缓存命中率、Claude 等价花费、Codex 额度。数据全部读自本地会话日志,**不联网、不改动任何 CLI**。

## 数据源与口径

| | Claude Code | Codex |
|---|---|---|
| 路径 | `~/.claude/projects/<proj>/<session>.jsonl` | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |
| 字段位置 | `type:"assistant"` 行的 `message.usage` | `token_count` 事件的 `payload.info` |
| token 性质 | **每条增量**,直接累加 | `last_token_usage` 增量 / `total_token_usage` 累计快照 |
| 缓存字段 | `cache_read` + `cache_creation`(分读/写) | 仅 `cached_input_tokens`(命中) |
| 额度信息 | Claude Desktop 的 Chromium HTTP 缓存(`/usage` 响应,zstd) | `rate_limits`:5h/周 `used_percent` + `resets_at` |

口径要点:
- **命中率** — Claude:`cache_read / (cache_read + cache_creation + input)`;Codex:`cached_input / input`。
- **今日范围** — 按本地时区当天 0 点;记录 timestamp 是 UTC,逐条转本地判断。
- **当前会话** — 取最近修改(mtime)的会话文件;Claude 累计其整段 usage,实时反映正在进行的会话。
- **Codex 跨天会话** — 长会话的今日事件常写在更早日期目录的文件里,因此按文件 mtime(今天有改动)筛选,而非目录日期。
- **今日没用 Codex 时** — 额度回退显示全局最新一次的 `rate_limits`。
- **额度口径** — Codex 原始字段 `used_percent`、Claude 原始字段 `utilization` 都是「已用%」;界面统一按官方面板习惯显示「**剩余%** = 100 − 已用」(剩余 ≤15% 转红)。
- **Claude 套餐额度** — Claude Code/CLI 本身不落地额度;此数据读自 **Claude Desktop** 每 ~10min 轮询 `/usage` 的 HTTP 缓存(`~/Library/Application Support/Claude/Cache/Cache_Data/`,zstd 压缩,纯只读)。因此:**需装 `zstd`**(`brew install zstd`)、**需 Claude Desktop 在跑**才有数据,滞后 ≤ ~10min;缺任一则 Claude 区不显示额度行(其余照常)。依赖内部缓存格式,官方更新可能失效。

## ⚠️ 关于花费

Claude / Codex 的"今日 ≈成本"都是**按 API 单价估算的等价成本,不是订阅实付**。两者都是订阅制,此数字只反映用量强度(等价 API 账单),实际不按此付费。重度使用时会很大。Claude 单价表在脚本顶部 `PRICING`;Codex 按官方分档价(input ≤272K/>272K 走不同档)逐请求估算。价格会变,按需自行核对。

## 两种形态

| | 原生 Swift app(推荐) | SwiftBar 插件 |
|---|---|---|
| UI | 自绘 SwiftUI,真毛玻璃(`.hudWindow`)、进度条、语义色 | 系统 NSMenu,只能调字体/颜色,无毛玻璃 |
| 数据源 | 调 `usage.30s.py --json`(唯一数据源) | `usage.30s.py` 直接输出 |
| 依赖 | 无需 Xcode,SwiftPM `swift build` 即可 | 需装 SwiftBar.app |
| 目录 | `Tokei/` | 本目录脚本 |

两者共用同一份取数逻辑(`usage.30s.py`):SwiftBar 走默认输出,app 走 `--json`。

## 安装(原生 app,推荐)

```bash
cd Tokei
./package.sh          # swift build + 组装 Tokei.app(含 LSUIElement 隐藏 Dock)
open Tokei.app        # 启动,菜单栏出现 ⚡<Claude命中率> ◷<Codex 5h额度>
```

- 点菜单栏图标弹出毛玻璃面板;每 30s 自动刷新,面板内有「刷新 / 退出」。
- 开机自启:系统设置 → 通用 → 登录项 → 加号选中 `Tokei.app`。
- 脚本路径硬编码在 `Sources/Tokei/DataLoader.swift` 的 `scriptPath`,移动仓库后改这里重新 `./package.sh`。

## 安装(SwiftBar 插件,轻量备选)

```bash
# 1. 装 SwiftBar(menu bar 插件宿主)
brew install --cask swiftbar

# 2. 首次启动 SwiftBar,会提示选择 Plugin Folder,选一个目录(如 ~/.swiftbar)

# 3. 把脚本放进该目录(软链,便于跟随本仓库更新)
ln -s "$(pwd)/usage.30s.py" ~/.swiftbar/usage.30s.py

# 4. SwiftBar 菜单 → Refresh All(或重启 SwiftBar)
```

文件名里的 `.30s.` = 每 30 秒刷新一次,改成 `.1m.` / `.10s.` 即可调整间隔。

## 显示说明

- 菜单栏标题(紧凑):`⚡<Claude今日命中率>  ◷<Codex 5h额度%>`
- 下拉顶部 **Tab 切换时间维度:今日 / 昨日 / 本周(周一起) / 本月(1号起)**——切换只影响 token / 命中率 / ≈成本;**额度(5h·周剩余)与本会话恒为「当前」**(额度是即时快照,日志无历史值)。
- Claude 块(命中率 / 输入·输出·缓存读·缓存写 / 等价成本 / 5h·周剩余 / 本会话)+ Codex 块(命中率 / 输入·缓存读·输出·推理 / 等价成本 / 5h·周剩余及重置 / plan)
- 注:SwiftBar 插件形态为静态菜单,只显示「今日」,无 Tab 切换。

## 局限

- 为支持「本周/本月」维度,每次刷新会扫描本月(及跨月时含本周/昨日)有改动的会话文件;日志多时刷新约 3–5 秒(后台执行,不卡 UI)。
- 花费为估算值,未覆盖未知模型(未知模型按 opus 价估,偏保守上限)。
