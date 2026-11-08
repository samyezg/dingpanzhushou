# Stock Alert Assistant（盯盘助手）

Hi, I'm Samye — a Flutter developer. This repo shows the core Dart architecture of my shipped A-share stock alert app.

Flutter source slice for an A-share watchlist alert app: rule-based local notifications during continuous auction hours.

This repository is a **core Dart sample for architecture review**. It is **not** a complete store-ready project.

**Not investment advice.** Not an official product of East Money (东方财富), any exchange, or any broker.

## Scope

| | |
|:---|:---|
| **Included** | `lib/` (Dart core), `assets/stock_basic_min.csv`, `pubspec.yaml` |
| **Not included** | `android/`, `ios/`, signing materials, store listing configs |
| **Store build** | Not produced from this repo alone (native projects omitted) |
| **API key** | Entered by the end user in Settings; stored with secure storage; **no hardcoded keys** in the repo |
| **SDK** | See `pubspec.yaml` (`>=3.4.0 <4.0.0`) |

## Features

- **Watchlist** — batch add / edit / remove
- **Rule engine** — price tiers, capital-flow zero-cross / reversal, related condition tips
- **Trading hours** — poll only in continuous auction (09:30–11:30, 13:00–15:00 CST)
- **Local notifications** — in-app history + system alerts (no third-party webhook)
- **Persistence** — per-session cooldown and related local state
- **Foreground keep-alive** — Dart service layer included; native Android FGS wiring is **not** in this repo
- **Key management** — secure storage; masked input with reveal-to-verify
- **Snapshot sanity** — open anchor / gap / pct-change consistency filters for dirty polls

## Tech stack

- Flutter / Dart
- `shared_preferences` + `flutter_secure_storage`
- `flutter_local_notifications`, `flutter_foreground_task` (native wiring outside this slice)
- Static listing metadata: `assets/stock_basic_min.csv`

## Layout

```
lib/
├── app.dart / main.dart
├── core/       # constants, disclaimer, signature guard, trading session
├── data/       # models, settings, alert history, cooldown, stock basic
├── mx/         # metrics extract + API client
├── rules/      # alert engine, thresholds, snapshot sanity
├── services/   # monitor, notification, foreground keep-alive
└── ui/         # watchlist, alerts, settings, help, theme
```

## Disclaimer

See in-app text (`lib/core/disclaimer.dart`) and `LICENSE`. Securities investing involves risk; alerts are not recommendations.

## License

See [`LICENSE`](./LICENSE) (**All Rights Reserved**).

Copyright (c) 2026 Stock Alert Assistant / Dingpan. All rights reserved.
