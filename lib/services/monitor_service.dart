import 'dart:async';

import '../core/trading_session.dart';
import '../data/alert_history_store.dart';
import '../data/alert_tuning.dart';
import '../data/cooldown_store.dart';
import '../data/day_state_persist.dart';
import '../data/models.dart';
import '../mx/metrics_extract.dart';
import '../mx/mx_client.dart';
import '../rules/alert_engine.dart';
import '../rules/extreme_confirm.dart';
import '../rules/snapshot_sanity.dart';
import 'foreground_keep_alive.dart';
import 'notification_service.dart';

typedef StatusCallback = void Function(String message);
typedef AlertsCallback = void Function(List<AlertRecord> newest);
typedef AuthFailedCallback = void Function(String detail);

class MonitorService {
  final MxClient mx;
  final CooldownStore cooldowns;
  final AlertHistoryStore history;
  final NotificationService notifications;
  final AlertEngine engine;
  final DayStatePersist dayPersist;
  final ExtremeConfirmRegistry extremeRegistry;

  Timer? _timer;
  AppSettings? _settings;
  final Map<String, SymbolRoundState> _states = {};
  int _quotaUsedToday = 0;
  String _quotaDay = '';
  bool _running = false;
  bool _fgsActive = false;
  bool _dayHydrated = false;

  StatusCallback? onStatus;
  AlertsCallback? onAlerts;
  /// 鉴权失败停轮询后回调（关闭 monitoringEnabled，角标回「已停止」）
  AuthFailedCallback? onAuthFailed;
  /// 首次进入交易时段并真正开 FGS 后回调（白名单引导）
  void Function()? onFgsStarted;

  MonitorService({
    required MxClient mx,
    required CooldownStore cooldowns,
    required AlertHistoryStore history,
    required NotificationService notifications,
    AlertEngine? engine,
    DayStatePersist? dayPersist,
    ExtremeConfirmRegistry? extremeRegistry,
  }) : this._(
          mx: mx,
          cooldowns: cooldowns,
          history: history,
          notifications: notifications,
          dayPersist: dayPersist ?? DayStatePersist(),
          extremeRegistry: extremeRegistry ??
              engine?.extremeRegistry ??
              ExtremeConfirmRegistry(),
          engine: engine,
        );

  MonitorService._({
    required this.mx,
    required this.cooldowns,
    required this.history,
    required this.notifications,
    required this.dayPersist,
    required this.extremeRegistry,
    AlertEngine? engine,
  }) : engine = engine ?? AlertEngine(extremeRegistry: extremeRegistry);

  bool get isRunning => _running;

  Future<void> start(AppSettings settings) async {
    await stop(announce: false);
    _settings = settings;
    if (!settings.disclaimerAccepted) {
      onStatus?.call('请先同意免责声明');
      return;
    }
    if (settings.mxApiKey.trim().isEmpty) {
      onStatus?.call('请先配置行情接口密钥');
      return;
    }
    if (settings.symbols.isEmpty) {
      onStatus?.call('请先添加盯盘股票');
      return;
    }
    _running = true;
    onStatus?.call('盯盘已启动');
    await _tick();
    if (!_running) return;
    final sec = settings.effectivePollIntervalSec();
    _timer = Timer.periodic(Duration(milliseconds: (sec * 1000).round()), (_) {
      unawaited(_tick());
    });
  }

  Future<void> stop({bool announce = true, String? statusMessage}) async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    await _stopFgs();
    if (announce) {
      onStatus?.call(statusMessage ?? '盯盘已停止');
    } else if (statusMessage != null) {
      onStatus?.call(statusMessage);
    }
  }

  Future<void> _haltAuthFailure(String detail) async {
    await stop(
      announce: true,
      statusMessage: '密钥无效/已失效 · $detail',
    );
    onAuthFailed?.call(detail);
  }

  Future<void> _ensureFgs() async {
    final settings = _settings;
    if (settings == null || !_running) return;
    final was = _fgsActive;
    await ForegroundKeepAlive.start(
      symbolCount: settings.symbols.length,
      intervalSec: settings.effectivePollIntervalSec(),
    );
    _fgsActive = true;
    if (!was) onFgsStarted?.call();
  }

  Future<void> _stopFgs() async {
    if (!_fgsActive && !(await ForegroundKeepAlive.isRunning)) {
      _fgsActive = false;
      return;
    }
    await ForegroundKeepAlive.stop();
    _fgsActive = false;
  }

  Future<void> _tick() async {
    final settings = _settings;
    if (settings == null || !_running) return;
    final now = DateTime.now();
    final day =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    if (day != _quotaDay) {
      _quotaDay = day;
      _quotaUsedToday = 0;
      _states.clear();
      _dayHydrated = false;
    }
    if (!_dayHydrated) {
      await dayPersist.init();
      await dayPersist.pruneExpired(now: now);
      await dayPersist.loadExtremeDay(day, extremeRegistry);
      await dayPersist.loadRoundSlice(day, _states);
      _dayHydrated = true;
    }
    if (!TradingSession.isContinuousAuction(now)) {
      // 盘外停 FGS（§7.25）；Timer 仍跑，回交易时段再开
      await _stopFgs();
      onStatus?.call('非交易时间 · 暂停拉取');
      return;
    }
    if (_quotaUsedToday >= settings.dailyApiQuota) {
      await _stopFgs();
      onStatus?.call('今日额度已用尽（${settings.dailyApiQuota}）');
      return;
    }

    await _ensureFgs();

    final newest = <AlertRecord>[];
    for (final sym in settings.symbols) {
      if (!_running) break;
      if (_quotaUsedToday >= settings.dailyApiQuota) break;
      try {
        final q = buildToolQuery(sym.displayName, sym.tsCode);
        final raw = await mx.query(apiKey: settings.mxApiKey, toolQuery: q);
        // 鉴权失败：不扣额度、立即停轮询并高亮
        if (isMxAuthFailure(raw)) {
          await _haltAuthFailure(mxStatusBrief(raw));
          return;
        }
        _quotaUsedToday++;
        final metrics = extractLabeledMetrics(raw);
        // status≠0 且非鉴权：仍计额度，但不跑规则（通常无可用 data）
        if (metrics.warns.any((w) => w.startsWith('API status='))) {
          onStatus?.call(
            '已请求 ${sym.label} · 额度 $_quotaUsedToday/${settings.dailyApiQuota}'
            ' · ${metrics.warns.first}',
          );
          continue;
        }
        final st = _states.putIfAbsent(sym.tsCode, () => SymbolRoundState());
        final sanity = applySnapshotSanity(
          metrics: metrics,
          sessionOpen: st.sessionOpen,
          lastValidF2: st.lastValidF2,
        );
        if (!sanity.ok) {
          onStatus?.call(
            '${sym.label} 脏轮已忽略：${sanity.reason} · 额度 $_quotaUsedToday/${settings.dailyApiQuota}',
          );
          continue;
        }
        // 仅可信轮更新 lastValidF2（引擎内也会写；此处保证 sanity 后基线）
        final latestPx = metricLatest(metrics);
        if (latestPx != null) st.lastValidF2 = latestPx;
        final hits = engine.evaluate(
          tsCode: sym.tsCode,
          displayName: sym.displayName,
          metrics: metrics,
          state: st,
          tuning: settings.alertTuning,
          now: now,
          watch: sym,
        );
        for (final h in hits) {
          final cooling = await cooldowns.isCooling(
            sym.tsCode,
            h.ruleId,
            minGap: h.cooldown,
          );
          if (cooling) continue;
          await cooldowns.mark(sym.tsCode, h.ruleId);
          final mode = settings.alertTuning.families.modeOf(
            familyOfRuleId(h.ruleId),
          );
          // 族已关时引擎不应产出；双保险
          if (!mode.isOn) continue;
          final doNotify = mode.shouldNotify;
          final rec = AlertRecord(
            at: DateTime.now(),
            tsCode: sym.tsCode,
            title: h.title,
            body: h.body,
            notified: doNotify,
          );
          await history.add(rec);
          newest.add(rec);
          if (doNotify) {
            await notifications.showAlert(rec.title, rec.body);
          }
        }
        onStatus?.call(
          '已更新 ${sym.label} · 额度 $_quotaUsedToday/${settings.dailyApiQuota}'
          '${metrics.warns.isEmpty ? '' : ' · ${metrics.warns.first}'}',
        );
      } catch (e) {
        onStatus?.call('${sym.tsCode} 拉取失败: $e');
      }
    }
    if (_quotaUsedToday >= settings.dailyApiQuota) {
      await _stopFgs();
      onStatus?.call('今日额度已用尽（${settings.dailyApiQuota}）');
    } else if (_fgsActive) {
      await ForegroundKeepAlive.update(
        symbolCount: settings.symbols.length,
        intervalSec: settings.effectivePollIntervalSec(),
      );
    }
    // 整轮结束后按时长/轮数重建 HTTP Client（对齐 PC after_round）
    mx.afterRound();
    // 按日侧车：极值 + 峰值/告警高低（拒轮未跑引擎时不抬峰）
    try {
      await dayPersist.saveExtremeDay(day, extremeRegistry);
      await dayPersist.saveRoundSlice(day, _states);
    } catch (_) {}
    final note = mx.lastSessionNote;
    if (note != null) {
      onStatus?.call(note);
      mx.lastSessionNote = null;
    }
    if (newest.isNotEmpty) onAlerts?.call(newest);
  }
}
