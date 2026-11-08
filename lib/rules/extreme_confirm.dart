/// 日内极值确认（对齐 PC ExtremeConfirmRegistry；APP 用 poll 代替分钟 K 收线）
library;

import 'rule_thresholds.dart';
import 'symbol_state.dart';

bool samePriceLevel(double a, double b, {double rel = kSamePriceLevelRel}) {
  if (a <= 0 || b <= 0) return (a - b).abs() < 1e-9;
  final m = a.abs() > b.abs() ? a.abs() : b.abs();
  return (a - b).abs() / m <= rel;
}

class ExtremePending {
  final String kind; // high | low
  final double level;
  final DateTime since;
  double peakPrice;
  double troughPrice;

  ExtremePending({
    required this.kind,
    required this.level,
    required this.since,
    required this.peakPrice,
    required this.troughPrice,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'level': level,
        'since_ms': since.millisecondsSinceEpoch,
        'peak': peakPrice,
        'trough': troughPrice,
      };

  static ExtremePending? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final kind = j['kind']?.toString();
    final level = (j['level'] as num?)?.toDouble();
    final ms = j['since_ms'] as int?;
    if (kind == null || level == null || ms == null) return null;
    return ExtremePending(
      kind: kind,
      level: level,
      since: DateTime.fromMillisecondsSinceEpoch(ms),
      peakPrice: (j['peak'] as num?)?.toDouble() ?? level,
      troughPrice: (j['trough'] as num?)?.toDouble() ?? level,
    );
  }
}

/// 单标的极值状态（可 JSON 持久化）
class ExtremeSymbolState {
  double? sessionHigh;
  double? sessionLow;
  DateTime? highSince;
  DateTime? lowSince;
  ExtremePending? pendingHigh;
  ExtremePending? pendingLow;
  int confirmCount = 0;
  DateTime? lastConfirmHighAt;
  DateTime? lastConfirmLowAt;
  double? lastConfirmedHighLevel;
  double? lastConfirmedLowLevel;
  DateTime? lastDistLogAt;
  bool firstSample = true;

  Map<String, dynamic> toJson() => {
        'session_high': sessionHigh,
        'session_low': sessionLow,
        'high_since_ms': highSince?.millisecondsSinceEpoch,
        'low_since_ms': lowSince?.millisecondsSinceEpoch,
        'pending_high': pendingHigh?.toJson(),
        'pending_low': pendingLow?.toJson(),
        'confirm_count': confirmCount,
        'last_confirm_high_ms': lastConfirmHighAt?.millisecondsSinceEpoch,
        'last_confirm_low_ms': lastConfirmLowAt?.millisecondsSinceEpoch,
        'last_confirmed_high': lastConfirmedHighLevel,
        'last_confirmed_low': lastConfirmedLowLevel,
        'last_dist_ms': lastDistLogAt?.millisecondsSinceEpoch,
        'first_sample': firstSample,
      };

  static ExtremeSymbolState fromJson(Map<String, dynamic>? j) {
    final s = ExtremeSymbolState();
    if (j == null) return s;
    s.sessionHigh = (j['session_high'] as num?)?.toDouble();
    s.sessionLow = (j['session_low'] as num?)?.toDouble();
    final hs = j['high_since_ms'] as int?;
    final ls = j['low_since_ms'] as int?;
    if (hs != null) s.highSince = DateTime.fromMillisecondsSinceEpoch(hs);
    if (ls != null) s.lowSince = DateTime.fromMillisecondsSinceEpoch(ls);
    final ph = j['pending_high'];
    final pl = j['pending_low'];
    if (ph is Map) {
      s.pendingHigh =
          ExtremePending.fromJson(Map<String, dynamic>.from(ph));
    }
    if (pl is Map) {
      s.pendingLow =
          ExtremePending.fromJson(Map<String, dynamic>.from(pl));
    }
    s.confirmCount = (j['confirm_count'] as num?)?.toInt() ?? 0;
    final lch = j['last_confirm_high_ms'] as int?;
    final lcl = j['last_confirm_low_ms'] as int?;
    if (lch != null) {
      s.lastConfirmHighAt = DateTime.fromMillisecondsSinceEpoch(lch);
    }
    if (lcl != null) {
      s.lastConfirmLowAt = DateTime.fromMillisecondsSinceEpoch(lcl);
    }
    s.lastConfirmedHighLevel = (j['last_confirmed_high'] as num?)?.toDouble();
    s.lastConfirmedLowLevel = (j['last_confirmed_low'] as num?)?.toDouble();
    final ld = j['last_dist_ms'] as int?;
    if (ld != null) s.lastDistLogAt = DateTime.fromMillisecondsSinceEpoch(ld);
    s.firstSample = j['first_sample'] as bool? ?? false;
    return s;
  }

  void expandSessionRange({double? high, double? low, DateTime? now}) {
    final n = now ?? DateTime.now();
    if (high != null) {
      if (sessionHigh == null || high > sessionHigh! + 1e-9) {
        sessionHigh = high;
        highSince ??= n;
      }
      firstSample = false;
    }
    if (low != null) {
      if (sessionLow == null || low < sessionLow! - 1e-9) {
        sessionLow = low;
        lowSince ??= n;
      }
      firstSample = false;
    }
  }
}

class ExtremeConfirmRegistry {
  ExtremeConfirmRegistry();

  final Map<String, ExtremeSymbolState> _symbols = {};
  String _dateKey = '';

  ExtremeSymbolState stateOf(String key) =>
      _symbols.putIfAbsent(key, ExtremeSymbolState.new);

  void maybeResetDay(String dateKey) {
    if (_dateKey == dateKey) return;
    _dateKey = dateKey;
    _symbols.clear();
  }

  void hydrateSymbol(String key, ExtremeSymbolState st) {
    _symbols[key] = st;
  }

  Map<String, ExtremeSymbolState> get all => Map.unmodifiable(_symbols);

  double? _volRatio(SymbolRoundState round) {
    final hist = round.history;
    if (hist.length < 2) return null;
    final deltas = <double>[];
    for (var i = 1; i < hist.length; i++) {
      final a0 = hist[i - 1].amount;
      final a1 = hist[i].amount;
      if (a0 == null || a1 == null) continue;
      final d = a1 - a0;
      if (d > 0) deltas.add(d);
    }
    if (deltas.isEmpty) return null;
    final n = deltas.length < 5 ? deltas.length : 5;
    final tail = deltas.sublist(deltas.length - n);
    final mean = tail.reduce((a, b) => a + b) / tail.length;
    if (mean <= 0) return null;
    final last = deltas.last;
    if (last <= 0) return null;
    return last / mean;
  }

  void _updateSession(ExtremeSymbolState st, double price, DateTime now) {
    if (st.firstSample) {
      st.sessionHigh = price;
      st.sessionLow = price;
      st.highSince = now;
      st.lowSince = now;
      st.firstSample = false;
      return;
    }
    if (price > (st.sessionHigh ?? price) + 1e-9) {
      st.sessionHigh = price;
      st.highSince = now;
      // poll 适配：新高即挂 pending（等同 bar 创 session 高）
      st.pendingHigh = ExtremePending(
        kind: 'high',
        level: price,
        since: now,
        peakPrice: price,
        troughPrice: price,
      );
    }
    if (price < (st.sessionLow ?? price) - 1e-9) {
      st.sessionLow = price;
      st.lowSince = now;
      st.pendingLow = ExtremePending(
        kind: 'low',
        level: price,
        since: now,
        peakPrice: price,
        troughPrice: price,
      );
    }
  }

  /// 每轮 poll 调用；返回告警文案 hits（title/body）
  List<({String ruleId, String title, String body})> onSnapshot({
    required String stateKey,
    required String label,
    required double price,
    required SymbolRoundState round,
    required DateTime now,
    required String dateKey,
  }) {
    maybeResetDay(dateKey);
    final st = stateOf(stateKey);
    final out = <({String ruleId, String title, String body})>[];

    _updateSession(st, price, now);

    void tryConfirm(ExtremePending pend, {required bool isHigh}) {
      final mins = now.difference(pend.since).inMinutes;
      if (mins < kExtremeConfirmMin) return;
      if (isHigh) {
        if (st.lastConfirmedHighLevel != null &&
            samePriceLevel(pend.level, st.lastConfirmedHighLevel!)) {
          st.pendingHigh = null;
          return;
        }
        if (st.lastConfirmHighAt != null &&
            now.difference(st.lastConfirmHighAt!).inMinutes <
                kExtremeCooldownMin) {
          return;
        }
      } else {
        if (st.lastConfirmedLowLevel != null &&
            samePriceLevel(pend.level, st.lastConfirmedLowLevel!)) {
          st.pendingLow = null;
          return;
        }
        if (st.lastConfirmLowAt != null &&
            now.difference(st.lastConfirmLowAt!).inMinutes <
                kExtremeCooldownMin) {
          return;
        }
      }
      final vr = _volRatio(round);
      if (vr == null || vr < kExtremeVolRatioMin) return;

      if (isHigh) {
        out.add((
          ruleId: 'extreme_high_${pend.level.toStringAsFixed(2)}',
          title: '[极值确认]',
          body:
              '$label 确认日内高点 ${_fmt(pend.level)}（守稳约${mins}分钟，额增量比 ${vr.toStringAsFixed(2)}）',
        ));
        st.lastConfirmHighAt = now;
        st.lastConfirmedHighLevel = pend.level;
        st.pendingHigh = null;
      } else {
        out.add((
          ruleId: 'extreme_low_${pend.level.toStringAsFixed(2)}',
          title: '[极值确认]',
          body:
              '$label 确认日内低点 ${_fmt(pend.level)}（守稳约${mins}分钟，额增量比 ${vr.toStringAsFixed(2)}）',
        ));
        st.lastConfirmLowAt = now;
        st.lastConfirmedLowLevel = pend.level;
        st.pendingLow = null;
      }
      st.confirmCount++;
    }

    if (st.pendingHigh != null) {
      final pend = st.pendingHigh!;
      pend.peakPrice =
          pend.peakPrice > price ? pend.peakPrice : price;
      if (price > pend.level + 1e-9) {
        st.pendingHigh = null;
      } else {
        tryConfirm(pend, isHigh: true);
      }
    }
    if (st.pendingLow != null) {
      final pend = st.pendingLow!;
      pend.troughPrice =
          pend.troughPrice < price ? pend.troughPrice : price;
      if (price < pend.level - 1e-9) {
        st.pendingLow = null;
      } else {
        tryConfirm(pend, isHigh: false);
      }
    }

    // 距极值
    if (st.sessionHigh != null &&
        st.sessionLow != null &&
        st.sessionHigh! > 0 &&
        st.sessionLow! > 0) {
      final coolOk = st.lastDistLogAt == null ||
          now.difference(st.lastDistLogAt!).inMinutes >=
              kExtremeDistanceCooldownMin;
      if (coolOk) {
        final distH =
            (st.sessionHigh! - price) / st.sessionHigh! * 100.0;
        final distL =
            (price - st.sessionLow!) / st.sessionLow! * 100.0;
        var fired = false;
        if (distH <= kExtremeDistanceNearPct && st.highSince != null) {
          final mins = now.difference(st.highSince!).inMinutes;
          out.add((
            ruleId: 'dist_extreme_high',
            title: '[距极值]',
            body:
                '$label 距日内高 ${_fmt(st.sessionHigh!)} 约 ${distH.toStringAsFixed(2)}%（高点已维持约${mins}分钟），现价 ${_fmt(price)}',
          ));
          fired = true;
        }
        if (distL <= kExtremeDistanceNearPct && st.lowSince != null) {
          final mins = now.difference(st.lowSince!).inMinutes;
          out.add((
            ruleId: 'dist_extreme_low',
            title: '[距极值]',
            body:
                '$label 距日内低 ${_fmt(st.sessionLow!)} 约 ${distL.toStringAsFixed(2)}%（低点已维持约${mins}分钟），现价 ${_fmt(price)}',
          ));
          fired = true;
        }
        if (fired) st.lastDistLogAt = now;
      }
    }

    return out;
  }

  static String _fmt(double v) {
    if (v >= 100) return v.toStringAsFixed(2);
    if (v >= 10) return v.toStringAsFixed(2);
    return v.toStringAsFixed(3);
  }
}
