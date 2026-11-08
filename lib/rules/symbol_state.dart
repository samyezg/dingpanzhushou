import '../mx/metrics_extract.dart';

class AlertHit {
  final String ruleId;
  final String title;
  final String body;
  final Duration? cooldown;

  AlertHit({
    required this.ruleId,
    required this.title,
    required this.body,
    this.cooldown,
  });
}

class PricePoint {
  final DateTime at;
  final double price;
  final double? amount;
  final double? volume;
  final double? mainNet;
  final double? turnover;

  PricePoint({
    required this.at,
    required this.price,
    this.amount,
    this.volume,
    this.mainNet,
    this.turnover,
  });
}

/// 单标的当日轮询状态（内存；换日由 MonitorService 清 map）
class SymbolRoundState {
  double? lastMainNet;
  double? lastMainDelta;
  double? peakPctOpen;
  double? peakPctPc;
  final Set<String> firedTiersOpen = {};
  final Set<String> firedTiersPc = {};

  double? sessionOpen;
  double? sessionHigh;
  double? sessionLow;
  double? lastValidF2;
  double? lastPrice;
  double? lastAmount;
  double? lastVolume;
  double? lastTurnover;
  double? lastDdz;

  bool gapFired = false;
  final Set<String> pullbackFiredPeaks = {};
  bool morningRiseFired = false;
  bool morningFallFired = false;
  DateTime? morningExtremeAt;
  double? morningExtremePct;

  final Set<String> integerFired = {};
  bool dayHighFired = false;
  bool dayLowFired = false;
  /// §43：已告警日内高/低；突破但未超过则抑制
  double? lastAlertedHigh;
  double? lastAlertedLow;

  bool mainCrossedUp = false;
  bool mainCrossedDown = false;
  bool mainReversalUpFired = false;
  bool mainReversalDownFired = false;

  int? ddxChipSide; // 1 吸筹 -1 出逃 0 无
  int ddxChipRearm = 0;

  bool retailPosArmed = false;
  bool retailNegArmed = false;
  bool retailPosFired = false;
  bool retailNegFired = false;

  bool brokeBelowOpen = false;
  bool openBreakAmFired = false;
  bool openBreakPmFired = false;

  String? boxKey;
  bool boxBreakFired = false;

  bool vwapFired = false;
  int vwapBelowCount = 0;

  bool tailDumpFired = false;
  bool tailPumpFired = false;

  bool hugeAmountFired = false;
  bool volHighFired = false;
  bool volLowFired = false;
  bool mainRatioHighFired = false;
  bool mainRatioLowFired = false;

  bool intradayRevFired = false;
  int mainInflowStreak = 0;

  final List<double> turnoverHist = [];
  final List<PricePoint> history = [];
  final List<double> emaSlopes = [];
  double? emaPrice;
  String? lastTrendDir; // up/down
  int decayCount = 0;
  double? peakEmaSlope;

  // 简化 KDJ（poll 点伪窗）
  double? k5;
  double? d5;
  double? k15;
  double? d15;
  double? prevK5;
  double? prevD5;
  double? prevK15;
  double? prevD15;

  // DDZ 轨迹（§39 简化）
  double? ddzTrackV1;
  DateTime? ddzTrackT1;
  bool ddzFirstLegDone = false;
  double? ddzTrackPrev;
  DateTime? ddzTrackPrevAt;
  double? ddzTrackPrevDelta;
  DateTime? ddzLastInflectAt;

  // 价档回落已报键
  final Set<String> priceTierFallFired = {};

  // 量能首报 / 午报
  bool volDigestFirstFired = false;
  bool volDigestNoonFired = false;

  // 大单占比首报 / 午报（不占 mainRatioHighFired）
  bool mainRatioFirstDigestFired = false;
  bool mainRatioNoonDigestFired = false;

  // 超买超卖（伪窗 15 轨 J）
  double? prevJ15;
  double? j15;
  bool obArmed = true;
  bool osArmed = true;
  int obEnterCount = 0;
  int osEnterCount = 0;
  int obExitCount = 0;
  int osExitCount = 0;
  DateTime? lastObEnterAt;
  DateTime? lastOsEnterAt;
  DateTime? lastObExitAt;
  DateTime? lastOsExitAt;

  void pushHistory(PricePoint p, {int maxKeep = 80}) {
    history.add(p);
    while (history.length > maxKeep) {
      history.removeAt(0);
    }
  }

  /// 按日持久化切片（极值 Registry 另存）
  Map<String, dynamic> toPersistJson() => {
        'peak_pct_open': peakPctOpen,
        'peak_pct_pc': peakPctPc,
        'session_open': sessionOpen,
        'session_high': sessionHigh,
        'session_low': sessionLow,
        'last_alerted_high': lastAlertedHigh,
        'last_alerted_low': lastAlertedLow,
        'last_valid_f2': lastValidF2,
        'fall_fired': priceTierFallFired.toList(),
        'vol_digest_first': volDigestFirstFired,
        'vol_digest_noon': volDigestNoonFired,
        'main_ratio_first_digest': mainRatioFirstDigestFired,
        'main_ratio_noon_digest': mainRatioNoonDigestFired,
        'ob_enter': obEnterCount,
        'os_enter': osEnterCount,
        'ob_exit': obExitCount,
        'os_exit': osExitCount,
        'ob_armed': obArmed,
        'os_armed': osArmed,
        'prev_j15': prevJ15,
        'ddz_v1': ddzTrackV1,
        'ddz_t1_ms': ddzTrackT1?.millisecondsSinceEpoch,
        'ddz_first_done': ddzFirstLegDone,
        'ddz_prev': ddzTrackPrev,
        'ddz_prev_at_ms': ddzTrackPrevAt?.millisecondsSinceEpoch,
        'ddz_prev_delta': ddzTrackPrevDelta,
        'ddz_last_inflect_ms': ddzLastInflectAt?.millisecondsSinceEpoch,
      };

  void applyPersistJson(Map<String, dynamic> j) {
    peakPctOpen = (j['peak_pct_open'] as num?)?.toDouble() ?? peakPctOpen;
    peakPctPc = (j['peak_pct_pc'] as num?)?.toDouble() ?? peakPctPc;
    sessionOpen = (j['session_open'] as num?)?.toDouble() ?? sessionOpen;
    sessionHigh = (j['session_high'] as num?)?.toDouble();
    sessionLow = (j['session_low'] as num?)?.toDouble();
    lastAlertedHigh = (j['last_alerted_high'] as num?)?.toDouble();
    lastAlertedLow = (j['last_alerted_low'] as num?)?.toDouble();
    lastValidF2 = (j['last_valid_f2'] as num?)?.toDouble() ?? lastValidF2;
    final ff = j['fall_fired'];
    if (ff is List) {
      priceTierFallFired
        ..clear()
        ..addAll(ff.map((e) => e.toString()));
    }
    volDigestFirstFired = j['vol_digest_first'] as bool? ?? volDigestFirstFired;
    volDigestNoonFired = j['vol_digest_noon'] as bool? ?? volDigestNoonFired;
    mainRatioFirstDigestFired =
        j['main_ratio_first_digest'] as bool? ?? mainRatioFirstDigestFired;
    mainRatioNoonDigestFired =
        j['main_ratio_noon_digest'] as bool? ?? mainRatioNoonDigestFired;
    obEnterCount = (j['ob_enter'] as num?)?.toInt() ?? obEnterCount;
    osEnterCount = (j['os_enter'] as num?)?.toInt() ?? osEnterCount;
    obExitCount = (j['ob_exit'] as num?)?.toInt() ?? obExitCount;
    osExitCount = (j['os_exit'] as num?)?.toInt() ?? osExitCount;
    obArmed = j['ob_armed'] as bool? ?? obArmed;
    osArmed = j['os_armed'] as bool? ?? osArmed;
    prevJ15 = (j['prev_j15'] as num?)?.toDouble() ?? prevJ15;
    ddzTrackV1 = (j['ddz_v1'] as num?)?.toDouble();
    final t1 = j['ddz_t1_ms'] as int?;
    if (t1 != null) ddzTrackT1 = DateTime.fromMillisecondsSinceEpoch(t1);
    ddzFirstLegDone = j['ddz_first_done'] as bool? ?? ddzFirstLegDone;
    ddzTrackPrev = (j['ddz_prev'] as num?)?.toDouble();
    final pa = j['ddz_prev_at_ms'] as int?;
    if (pa != null) ddzTrackPrevAt = DateTime.fromMillisecondsSinceEpoch(pa);
    ddzTrackPrevDelta = (j['ddz_prev_delta'] as num?)?.toDouble();
    final li = j['ddz_last_inflect_ms'] as int?;
    if (li != null) {
      ddzLastInflectAt = DateTime.fromMillisecondsSinceEpoch(li);
    }
  }
}
