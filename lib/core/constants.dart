/// 盯盘助手 — 产品常量（对齐 `模块封装/讨论备忘-模块封装.md` §七）
library;

const String kAppDisplayName = '盯盘助手';
const String kApplicationId = 'com.dingpanzhushou.app';
/// 与 `pubspec.yaml` version 主号对齐（上架/关于展示用）
const String kAppVersionLabel = '0.1.7';

/// 开发者 / 著作权人（与易版权、AGC 实名一致）
const String kCopyrightHolder = '叶志国';

/// 运营联系邮箱（帮助 §10 / 隐私政策 / AGC 一致）
const String kSupportEmail = 'dingpanzhushou@outlook.com';

/// 隐私政策 HTTPS（GitHub Pages；AGC「隐私声明」同 URL）
const String kPrivacyPolicyUrl = 'https://sam-yzg.github.io/dingpanzhushou/';

const String kMxQueryUrl =
    'https://mkapi2.dfcfs.com/finskillshub/api/claw/query';

/// 默认日 API 额度（与现网 daily_api_quota 对齐，可在设置覆盖）
const int kDefaultDailyApiQuota = 500;

/// 额度安全系数（对齐 PC `quota_safety_ratio`，推荐间隔按额度×此比例留余量）
const double kQuotaSafetyRatio = 0.85;

/// 每轮每标预留请求数（对齐 PC monitor：默认开空表重试时 k=2）
const int kRequestsPerSymbolPerRound = 2;

/// 连续竞价粗算分钟数（对齐 PC recommended_interval_sec 的 240）
const double kContinuousAuctionMinutes = 240.0;

/// 推荐轮询间隔下限（秒；对齐 PC `max(60, …)`）
const double kMinRecommendedPollIntervalSec = 60.0;

/// 二期起默认关闭 5 分钟 KDJ 企微/告警（与 PC watchlist `kdj_5_enabled: false` 对齐）
const bool kEnableKdj5Alerts = false;

/// MX HTTP Client 重建：时长（秒）。PC 默认 1500；APP 推荐 A 用 900（手机网更碎）。
const double kMxHttpSessionTtlSec = 900.0;

/// MX HTTP Client 重建：监控轮数。PC 默认 15；APP 推荐 A 用 8（与 ~203s 间隔同量级）。
/// 与 [kMxHttpSessionTtlSec] 为 OR：任一满足即重建（对齐 PC SessionManager）。
const int kMxHttpSessionMaxRounds = 8;

/// 默认股票数提示阈值
const int kDefaultSymbolCount = 3;

/// 价档默认阈值（相对开盘/昨收 %）
const List<double> kDefaultPriceTiersPct = [3.0, 5.0, 8.0];
