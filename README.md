# 盯盘助手 / Stock Alert Assistant — Flutter（源码切片）

A-share（A 股）自选条件提醒：规则引擎本地告警。本仓为 **作品集 / 架构审阅用核心 Dart 切片**，不是完整可上架工程。

**非投资建议。** 非东方财富 / 交易所 / 券商官方应用。

## 重要边界（请先读）

| 项 | 说明 |
|:---|:---|
| 本仓包含 | `lib/`（Dart 核心）、`assets/stock_basic_min.csv`、`pubspec.yaml` |
| 本仓**不含** | `android/`、`ios/`、签名材料、商店上架配置 |
| 能否直接 `flutter run` 出上架包 | **不能**（缺原生工程；完整包为付费交付） |
| API Key | 由终端用户在设置中自行填写，本地安全存储；**仓库内无硬编码密钥** |
| 分享策略 | 默认 **Private**；不在公开主页挂链；verified 客户讨论项目后再提供 sample |

English (clients): *Source samples for architecture review only. Production Android/iOS configs and store builds are delivered as paid work. GitHub access is for verified clients after we discuss your project.*

## Features

- **Watchlist**：批量添加 / 编辑 / 删除
- **Rule engine**：价档、资金过零 / 转向、相关条件提示
- **Trading hours**：仅连续竞价时段轮询（09:30–11:30、13:00–15:00）
- **Local notifications**：应用内历史 + 系统通知（无第三方 webhook）
- **Cooldown persistence**：按交易日冷却等本地状态
- **Foreground service**：Android FGS（完整工程内）；本切片可见对应 Dart 服务层
- **Key management**：Secure Storage；掩码 + 眼睛核对
- **Snapshot sanity**：开盘锚 / 跳空 / 涨跌一致性过滤脏轮

## Tech Stack

- Flutter / Dart（SDK 见 `pubspec.yaml`）
- SharedPreferences + flutter_secure_storage
- `flutter_foreground_task`（Android FGS，完整工程）
- `assets/stock_basic_min.csv`（静态证券基础信息）

## Project Structure

```
lib/
├── app.dart / main.dart
├── core/       # constants, disclaimer, signature guard, trading session…
├── data/       # models, settings, alert history, cooldown, stock basic
├── mx/         # metrics extract + claw/query client
├── rules/      # alert engine, thresholds, snapshot sanity
├── services/   # monitor, notification, foreground keep-alive
└── ui/         # watchlist, alerts, settings, help, theme
```

## Sharing（雇主 / Fiverr 客户）

- 仓库默认 **Private**；不在 Fiverr Profile 放置直链。
- 非技术客户：优先 **脱敏 ZIP**（订单/Milestone 后）。
- 少数需在线看仓：临时 Collaborator 或短效只读凭据；审阅结束后 **立即撤权**。
- 完整可运行包与后续维护走 **付费交付**，不预置在本公开/半公开渠道。

## Disclaimer

见应用内免责声明（`lib/core/disclaimer.dart`）及 `LICENSE`。证券投资有风险；提示≠荐股。

## License

见根目录 [`LICENSE`](./LICENSE)：**All Rights Reserved**。仅供作品集与经授权的架构讨论；禁止未经书面许可的再分发与商用仿制。

Copyright (c) 2026 叶志国. All rights reserved.
