import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import 'alert_tuning.dart';
import 'models.dart';

class SettingsStore {
  static const _kKey = 'mx_api_key';
  static const _kSymbols = 'symbols_json';
  static const _kQuota = 'daily_api_quota';
  static const _kInterval = 'poll_interval_sec';
  static const _kMonitor = 'monitoring_enabled';
  static const _kDisclaimer = 'disclaimer_accepted';
  static const _kWarnedGt3 = 'warned_gt3_symbols';
  static const _kBgGuide = 'background_guide_seen';
  static const _kTiers = 'price_tiers_pct'; // 旧键，迁移进 alert_tuning
  static const _kAlertTuning = 'alert_tuning_json';

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  SettingsStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<AppSettings> load() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    final key = await _secure.read(key: _kKey) ?? '';
    final rawSym = prefs.getString(_kSymbols);
    var symbols = <WatchSymbol>[];
    if (rawSym != null && rawSym.isNotEmpty) {
      final list = jsonDecode(rawSym) as List<dynamic>;
      symbols = list
          .map((e) => WatchSymbol.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final interval = prefs.getDouble(_kInterval);

    AlertTuning tuning;
    final rawTuning = prefs.getString(_kAlertTuning);
    if (rawTuning != null && rawTuning.isNotEmpty) {
      tuning = AlertTuning.fromJson(
        Map<String, dynamic>.from(jsonDecode(rawTuning) as Map),
      );
    } else {
      List<double> tiers = List<double>.from(kDefaultPriceTiersPct);
      final tiersRaw = prefs.getString(_kTiers);
      if (tiersRaw != null && tiersRaw.isNotEmpty) {
        tiers = (jsonDecode(tiersRaw) as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();
      }
      tuning = AlertTuning(priceTiersPct: tiers);
    }

    return AppSettings(
      mxApiKey: key,
      symbols: symbols,
      dailyApiQuota: prefs.getInt(_kQuota) ?? kDefaultDailyApiQuota,
      pollIntervalSec: interval,
      monitoringEnabled: prefs.getBool(_kMonitor) ?? false,
      disclaimerAccepted: prefs.getBool(_kDisclaimer) ?? false,
      warnedGt3Symbols: prefs.getBool(_kWarnedGt3) ?? false,
      backgroundGuideSeen: prefs.getBool(_kBgGuide) ?? false,
      alertTuning: tuning,
    );
  }

  Future<void> save(AppSettings s) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (s.mxApiKey.trim().isEmpty) {
      await _secure.delete(key: _kKey);
    } else {
      await _secure.write(
        key: _kKey,
        value: s.mxApiKey.replaceAll(RegExp(r'[\r\n\t]'), '').trim(),
      );
    }
    await prefs.setString(
      _kSymbols,
      jsonEncode(s.symbols.map((e) => e.toJson()).toList()),
    );
    await prefs.setInt(_kQuota, s.dailyApiQuota);
    if (s.pollIntervalSec == null) {
      await prefs.remove(_kInterval);
    } else {
      await prefs.setDouble(_kInterval, s.pollIntervalSec!);
    }
    await prefs.setBool(_kMonitor, s.monitoringEnabled);
    await prefs.setBool(_kDisclaimer, s.disclaimerAccepted);
    await prefs.setBool(_kWarnedGt3, s.warnedGt3Symbols);
    await prefs.setBool(_kBgGuide, s.backgroundGuideSeen);
    await prefs.setString(_kAlertTuning, jsonEncode(s.alertTuning.toJson()));
    // 兼容旧读者
    await prefs.setString(_kTiers, jsonEncode(s.alertTuning.priceTiersPct));
  }
}
