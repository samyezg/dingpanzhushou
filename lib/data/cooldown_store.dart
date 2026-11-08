import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 当日告警冷却：键 = tradeDate|tsCode|ruleId
class CooldownStore {
  static const _kPrefix = 'cooldown_v1_';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String _tradeDate([DateTime? now]) {
    final n = now ?? DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}'
        '${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}';
  }

  String _key(String tradeDate, String tsCode, String ruleId) =>
      '$_kPrefix$tradeDate|${tsCode.toUpperCase()}|$ruleId';

  Future<bool> isCooling(
    String tsCode,
    String ruleId, {
    DateTime? now,
    Duration? minGap,
  }) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final td = _tradeDate(now);
    final raw = prefs.getString(_key(td, tsCode, ruleId));
    if (raw == null) return false;
    if (minGap == null) return true;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ms = map['at_ms'] as int?;
      if (ms == null) return true;
      final at = DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime.now().difference(at) < minGap;
    } catch (_) {
      return true;
    }
  }

  Future<void> mark(
    String tsCode,
    String ruleId, {
    DateTime? now,
    Map<String, dynamic>? extra,
  }) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final td = _tradeDate(now);
    final payload = <String, dynamic>{
      'at_ms': (now ?? DateTime.now()).millisecondsSinceEpoch,
      ...?extra,
    };
    await prefs.setString(_key(td, tsCode, ruleId), jsonEncode(payload));
  }

  /// 清理非当日冷却键（启动时调用）
  Future<void> purgeOtherDays({DateTime? now}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final td = _tradeDate(now);
    final keys = prefs.getKeys().where((k) => k.startsWith(_kPrefix)).toList();
    for (final k in keys) {
      if (!k.startsWith('$_kPrefix$td|')) {
        await prefs.remove(k);
      }
    }
  }
}
