import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import 'alert_tuning.dart';
import 'symbol_profile.dart';

@immutable
class WatchSymbol {
  final String tsCode;
  final String displayName;

  /// 客户选填：流通市值（亿元）；未设显式档时由 [effectiveTier] 按亿元推断并展示
  final double? circMvYi;

  /// 客户选填：市值档 large/medium/small（可空；空则跟亿元推断，不自动回写）
  final CircMvTier? marketCapTier;

  /// 客户选填：近 5 日均量（手）
  final double? avgVol5dLots;

  const WatchSymbol({
    required this.tsCode,
    required this.displayName,
    this.circMvYi,
    this.marketCapTier,
    this.avgVol5dLots,
  });

  String get label =>
      displayName.isEmpty ? tsCode : '$displayName $tsCode';

  BoardKind get board => inferBoard(tsCode);

  /// 有效市值档：显式档 > 由亿元映射 > unknown
  CircMvTier get effectiveTier {
    if (marketCapTier != null && marketCapTier != CircMvTier.unknown) {
      return marketCapTier!;
    }
    return tierFromCircMvYi(circMvYi);
  }

  bool get hasCircMvProfile =>
      effectiveTier != CircMvTier.unknown &&
      effectiveTier != CircMvTier.micro;

  bool get hasAvgVol5d => avgVol5dLots != null && avgVol5dLots! > 0;

  WatchSymbol copyWith({
    String? tsCode,
    String? displayName,
    double? circMvYi,
    CircMvTier? marketCapTier,
    double? avgVol5dLots,
    bool clearCircMvYi = false,
    bool clearMarketCapTier = false,
    bool clearAvgVol5dLots = false,
  }) {
    return WatchSymbol(
      tsCode: tsCode ?? this.tsCode,
      displayName: displayName ?? this.displayName,
      circMvYi: clearCircMvYi ? null : (circMvYi ?? this.circMvYi),
      marketCapTier:
          clearMarketCapTier ? null : (marketCapTier ?? this.marketCapTier),
      avgVol5dLots:
          clearAvgVol5dLots ? null : (avgVol5dLots ?? this.avgVol5dLots),
    );
  }

  Map<String, dynamic> toJson() => {
        'ts_code': tsCode,
        'display_name': displayName,
        if (circMvYi != null) 'circ_mv_yi': circMvYi,
        if (marketCapTier != null) 'market_cap_tier': marketCapTier!.id,
        if (avgVol5dLots != null) 'avg_vol_5d_lots': avgVol5dLots,
      };

  factory WatchSymbol.fromJson(Map<String, dynamic> j) {
    CircMvTier? tier;
    final rawTier = j['market_cap_tier'] ?? j['marketCapTier'];
    if (rawTier != null) {
      tier = CircMvTierX.tryParse(rawTier.toString()) ?? CircMvTier.unknown;
      if (tier == CircMvTier.unknown) tier = null;
    }
    double? yi;
    final rawYi = j['circ_mv_yi'] ?? j['circMvYi'];
    if (rawYi is num) yi = rawYi.toDouble();
    double? avg;
    final rawAvg = j['avg_vol_5d_lots'] ?? j['avgVol5dLots'];
    if (rawAvg is num) avg = rawAvg.toDouble();
    return WatchSymbol(
      tsCode: (j['ts_code'] ?? '').toString(),
      displayName: (j['display_name'] ?? '').toString(),
      circMvYi: yi,
      marketCapTier: tier,
      avgVol5dLots: avg,
    );
  }
}

class AppSettings {
  String mxApiKey;
  List<WatchSymbol> symbols;
  int dailyApiQuota;
  /// 轮询间隔（秒）；未设置时由 [defaultPollIntervalSec] 估算；设置页默认显示该估算值
  double? pollIntervalSec;
  bool monitoringEnabled;
  bool disclaimerAccepted;
  bool warnedGt3Symbols;
  /// 后台白名单引导是否已看过/跳过（§7.25）
  bool backgroundGuideSeen;
  /// 二期骨+肉调参（含价档）
  AlertTuning alertTuning;

  AppSettings({
    this.mxApiKey = '',
    List<WatchSymbol>? symbols,
    this.dailyApiQuota = 500,
    this.pollIntervalSec,
    this.monitoringEnabled = false,
    this.disclaimerAccepted = false,
    this.warnedGt3Symbols = false,
    this.backgroundGuideSeen = false,
    AlertTuning? alertTuning,
    List<double>? priceTiersPct,
  })  : symbols = symbols ?? <WatchSymbol>[],
        alertTuning = alertTuning ??
            AlertTuning(
              priceTiersPct: priceTiersPct ?? kDefaultPriceTiersPct,
            );

  List<double> get priceTiersPct => alertTuning.priceTiersPct;
  set priceTiersPct(List<double> v) =>
      alertTuning.priceTiersPct = List<double>.from(v);

  /// 按额度与股票数估算默认间隔（秒）。
  double defaultPollIntervalSec() {
    final n = symbols.isEmpty ? 1 : symbols.length;
    final quota = dailyApiQuota <= 0 ? kDefaultDailyApiQuota : dailyApiQuota;
    final denom = quota * kQuotaSafetyRatio;
    if (denom <= 0) return kMinRecommendedPollIntervalSec;
    final tMinutes =
        (kContinuousAuctionMinutes * n * kRequestsPerSymbolPerRound) / denom;
    final raw = tMinutes * 60.0;
    return raw < kMinRecommendedPollIntervalSec
        ? kMinRecommendedPollIntervalSec
        : raw;
  }

  double effectivePollIntervalSec() =>
      pollIntervalSec ?? defaultPollIntervalSec();
}
