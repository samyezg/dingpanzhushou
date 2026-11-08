/// 盯盘规则阈值（对齐 PC config 默认；APP 侧可降级处见注释）
library;

const double kGapThresholdPct = 3.0;
const double kMainCrossMinWan = 500.0;
const double kMainCrossMinYuan = kMainCrossMinWan * 10000.0;
const double kRetailCrossMinWan = 1000.0;
const double kRetailCrossMinYuan = kRetailCrossMinWan * 10000.0;

const double kSpikePricePct = 0.65; // PC 0.0065 → 百分数 0.65%
const double kSpikeVolRatioDegraded = 1.3; // 无量比时用成交额环比

const double kPullbackPct = 0.4; // 0.004 → 0.4%
const double kPullbackLegMinPct = 2.0;

const double kMorningPct = 3.0;
const int kMorningRepairMinutes = 15;
const int kMorningWindowEndHour = 10;
const int kMorningWindowEndMinute = 0;

const double kTurnoverHugeYi = 100.0; // 巨量成交额阈值（亿）
const double kTurnoverHighPctMain = 15.0; // 主板换手极高粗阈值（降级，不分板）
const double kTurnoverMorningHighPct = 5.0;
const double kTurnoverDryPct = 0.15;
const int kTurnoverDryMinSamples = 3;
const int kTurnoverDryDisableBeforeMinute = 10; // 开盘后 N 分钟内地量不报

const double kDdxChipMin = 0.08;
const double kDdzDeltaMin = 0.05;

const double kIntegerNearPct = 2.0; // 距整数关口
const int kPlatformMinutes = 20;
const double kPlatformAmpPct = 0.5;
const double kBreakoutDevPct = 1.0;
const double kPlatformVolRatio = 1.5; // 降级

const double kTailDumpPct = 2.0;
const double kTailPumpPct = 1.5;
const int kTailStartHour = 14;

const double kVwapMainMinWan = 0.0;
const int kVwapBelowMinSnaps = 3;

const double kVolRatioHigh = 3.0; // 放量（无5日均量时用额环比累计代理，见规则）
const double kVolRatioLow = 0.5;

const double kMainRatioHighPct = 40.0; // 大单占比降级：|主力|/成交额
const double kMainRatioLowPct = 10.0;

const double kIntradayRevHalf = 0.5; // 回升超跌幅一半
const int kIntradayRevMainStreak = 3;

/// 开盘相对昨收三角：|f17-sessionOpen|/open
const double kSanityOpenAnchorMaxDevPct = 1.0;
const double kSanityJumpMaxPct = 12.0; // 无仓版放宽（PC 无昨收跳变更严）
const double kSanityF3DeltaPct = 0.5;
/// §44：同包 |最新−昨收|/昨收 硬拒（对齐 PC snapshot_f60_f2_max_dev_pct）
const double kSanityF60F2MaxDevPct = 12.0;

/// 极值确认（poll 适配完整 Registry）
const double kExtremeConfirmMin = 15.0;
const double kExtremeVolRatioMin = 1.2;
const double kExtremeCooldownMin = 30.0;
const double kExtremeDistanceNearPct = 2.0;
const double kExtremeDistanceCooldownMin = 20.0;
const double kSamePriceLevelRel = 0.0005; // 0.05%

/// DDZ 轨迹
const double kDdzTrackDeltaEps = 0.05;
const double kDdzInflectGapSkipSec = 20 * 60;

/// 量能首报 / 午报：开盘后首次 ≥10:00 / ≥13:00；额环比阈值
const int kVolDigestFirstHour = 10;
const int kVolDigestFirstMinute = 0;
const int kVolDigestNoonHour = 13;
const int kVolDigestNoonMinute = 0;
const double kVolDigestAmountRatioHigh = 1.2;
const double kVolDigestAmountRatioLow = 0.8;
const int kVolDigestMinSamples = 3;

/// 大单占比首报 / 午报（不占边沿日锁）
const int kMainRatioDigestFirstHour = 10;
const int kMainRatioDigestNoonHour = 13;

/// 伪窗超买/超卖（对齐 PC §46 · 15 轨 J）
const double kObOsHigh = 80.0;
const double kObOsLow = 20.0;
const int kObOsMaxEnterPerDay = 2;
const int kObOsMaxExitPerDay = 2;
const int kObOsOpenGateMinutes = 20;
const int kObOsCooldownMinutes = 20;

/// 按日持久化：保留今日+昨日
const int kDayStateKeepCalendarDays = 2;
