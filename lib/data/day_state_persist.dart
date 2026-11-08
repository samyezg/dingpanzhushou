/// 按日盯盘状态持久化（极值 Registry + 告警高低/价档峰值）；换日 prune 保留今日+昨日
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../rules/extreme_confirm.dart';
import '../rules/rule_thresholds.dart';
import '../rules/symbol_state.dart';

class DayStatePersist {
  static const _kExtremePrefix = 'extreme_day_v1_';
  static const _kRoundPrefix = 'round_day_v1_';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String tradeDate([DateTime? now]) {
    final n = now ?? DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}'
        '${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Set<String> _keepDates(DateTime now) {
    final out = <String>{};
    for (var i = 0; i < kDayStateKeepCalendarDays; i++) {
      out.add(tradeDate(now.subtract(Duration(days: i))));
    }
    return out;
  }

  /// 删除非保留日的极值/轮询侧车键
  Future<void> pruneExpired({DateTime? now}) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final keep = _keepDates(now ?? DateTime.now());
    final keys = prefs.getKeys().toList();
    for (final k in keys) {
      String? td;
      if (k.startsWith(_kExtremePrefix)) {
        td = k.substring(_kExtremePrefix.length);
      } else if (k.startsWith(_kRoundPrefix)) {
        td = k.substring(_kRoundPrefix.length);
      }
      if (td != null && !keep.contains(td)) {
        await prefs.remove(k);
      }
    }
  }

  Future<void> saveExtremeDay(
    String dateKey,
    ExtremeConfirmRegistry registry,
  ) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final e in registry.all.entries) {
      map[e.key] = e.value.toJson();
    }
    await prefs.setString('$_kExtremePrefix$dateKey', jsonEncode(map));
  }

  Future<void> loadExtremeDay(
    String dateKey,
    ExtremeConfirmRegistry registry,
  ) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kExtremePrefix$dateKey');
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      registry.maybeResetDay(dateKey);
      for (final e in map.entries) {
        if (e.value is Map) {
          registry.hydrateSymbol(
            e.key,
            ExtremeSymbolState.fromJson(
              Map<String, dynamic>.from(e.value as Map),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> saveRoundSlice(
    String dateKey,
    Map<String, SymbolRoundState> states,
  ) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final e in states.entries) {
      map[e.key] = e.value.toPersistJson();
    }
    await prefs.setString('$_kRoundPrefix$dateKey', jsonEncode(map));
  }

  Future<void> loadRoundSlice(
    String dateKey,
    Map<String, SymbolRoundState> states,
  ) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kRoundPrefix$dateKey');
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        if (e.value is! Map) continue;
        final st = states.putIfAbsent(e.key, SymbolRoundState.new);
        st.applyPersistJson(Map<String, dynamic>.from(e.value as Map));
      }
    } catch (_) {}
  }
}
