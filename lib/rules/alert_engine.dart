import '../core/constants.dart';
import '../data/alert_tuning.dart';
import '../data/models.dart';
import '../data/symbol_profile.dart';
import '../mx/metrics_extract.dart';
import 'extreme_confirm.dart';
import 'rule_thresholds.dart';
import 'symbol_state.dart';

export 'symbol_state.dart' show AlertHit, SymbolRoundState, PricePoint;

/// 规则引擎：一期子集 + §2.2/2.3 + §十七 PC 融入
class AlertEngine {
  AlertTuning _t = AlertTuning.defaults();
  final ExtremeConfirmRegistry extremeRegistry;

  AlertEngine({ExtremeConfirmRegistry? extremeRegistry})
      : extremeRegistry = extremeRegistry ?? ExtremeConfirmRegistry();

  List<AlertHit> evaluate({
    required String tsCode,
    required String displayName,
    required MetricsBundle metrics,
    required SymbolRoundState state,
    List<double>? tiersPct,
    AlertTuning? tuning,
    DateTime? now,
    /// 自选股画像（选填市值/均量）；未传或未填 → 降级规则
    WatchSymbol? watch,
  }) {
    _t = tuning ??
        AlertTuning(
          priceTiersPct: tiersPct ?? const [3.0, 5.0, 8.0],
        );
    if (tuning == null && tiersPct != null) {
      _t.priceTiersPct = List<double>.from(tiersPct);
    }
    final tiersPctEff = _t.priceTiersPct;
    final hits = <AlertHit>[];
    final at = now ?? DateTime.now();
    final dateKey =
        '${at.year.toString().padLeft(4, '0')}${at.month.toString().padLeft(2, '0')}${at.day.toString().padLeft(2, '0')}';
    final label =
        displayName.isEmpty ? tsCode : '$displayName(${tsCode.split('.').first})';
    final profile = watch ??
        WatchSymbol(tsCode: tsCode, displayName: displayName);

    final latest = metricLatest(metrics);
    final open = metricOpen(metrics);
    final pc = metricPrevClose(metrics);
    final main = metricMainNet(metrics);
    final retail = metricRetailNet(metrics);
    final ddx = metricDdx(metrics);
    final ddy = metricDdy(metrics);
    final ddz = metricDdz(metrics);
    final turnover = metricTurnoverRate(metrics);
    final amount = metricAmount(metrics);
    final volume = metricVolume(metrics);
    final vwap = metricAvgPrice(metrics);
    final mainRatio = metricMainRatioPct(metrics, amount: amount, main: main);

    if (latest == null) return hits;

    // —— 会话极值 / 开盘锚 ——
    state.sessionOpen ??= open ?? latest;
    final prevSessHigh = state.sessionHigh;
    final prevSessLow = state.sessionLow;
    state.sessionHigh =
        state.sessionHigh == null ? latest : (latest > state.sessionHigh! ? latest : state.sessionHigh);
    state.sessionLow =
        state.sessionLow == null ? latest : (latest < state.sessionLow! ? latest : state.sessionLow);
    extremeRegistry.stateOf(tsCode).expandSessionRange(
          high: state.sessionHigh,
          low: state.sessionLow,
          now: at,
        );
    final est = extremeRegistry.stateOf(tsCode);
    if (est.sessionHigh != null) {
      state.sessionHigh = state.sessionHigh == null
          ? est.sessionHigh
          : (est.sessionHigh! > state.sessionHigh! ? est.sessionHigh : state.sessionHigh);
    }
    if (est.sessionLow != null) {
      state.sessionLow = state.sessionLow == null
          ? est.sessionLow
          : (est.sessionLow! < state.sessionLow! ? est.sessionLow : state.sessionLow);
    }
    if (state.lastAlertedHigh == null && est.lastConfirmedHighLevel != null) {
      state.lastAlertedHigh = est.lastConfirmedHighLevel;
    }
    if (est.lastConfirmedHighLevel == null && state.lastAlertedHigh != null) {
      est.lastConfirmedHighLevel = state.lastAlertedHigh;
    }
    if (state.lastAlertedLow == null && est.lastConfirmedLowLevel != null) {
      state.lastAlertedLow = est.lastConfirmedLowLevel;
    }
    if (est.lastConfirmedLowLevel == null && state.lastAlertedLow != null) {
      est.lastConfirmedLowLevel = state.lastAlertedLow;
    }

    double? pctOpen;
    if (open != null && open.abs() > 1e-9) {
      pctOpen = (latest - open) / open * 100.0;
    }
    double? pctPc;
    if (pc != null && pc.abs() > 1e-9) {
      pctPc = (latest - pc) / pc * 100.0;
    } else {
      pctPc = metricPct(metrics);
    }

    if (pctOpen != null) {
      state.peakPctOpen = state.peakPctOpen == null
          ? pctOpen
          : (state.peakPctOpen! > pctOpen ? state.peakPctOpen : pctOpen);
    }
    if (pctPc != null) {
      state.peakPctPc = state.peakPctPc == null
          ? pctPc
          : (state.peakPctPc! > pctPc ? state.peakPctPc : pctPc);
    }

    state.pushHistory(PricePoint(
      at: at,
      price: latest,
      amount: amount,
      volume: volume,
      mainNet: main,
      turnover: turnover,
    ));

    // ========== 2.2 / 既有：价档 ==========
    if (_t.families.priceTiers.isOn) {
      _priceTiers(hits, label, latest, pctOpen, pctPc, state, tiersPctEff);
      _priceTierFall(hits, label, latest, pctOpen, pctPc, state, tiersPctEff);
    }

    // ========== 2.2：开盘跳空 ==========
    if (_t.families.gapMorningTail.isOn &&
        !state.gapFired &&
        open != null &&
        pc != null &&
        pc.abs() > 1e-9) {
      final gap = (open - pc) / pc * 100.0;
      if (gap.abs() + 1e-9 >= _t.gapThresholdPct) {
        state.gapFired = true;
        hits.add(AlertHit(
          ruleId: 'gap_${gap >= 0 ? 'up' : 'down'}',
          title: '[开盘跳空]',
          body:
              '$label 开盘价 ${_fmt(open)}，较昨收${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(2)}%（阈值±${_t.gapThresholdPct.toStringAsFixed(0)}%）',
          cooldown: const Duration(hours: 6),
        ));
      }
    }

    // ========== 2.2：盘中急升/急跌 ==========
    if (_t.families.spikePullback.isOn &&
        state.lastPrice != null &&
        state.lastPrice! > 0) {
      final chg = (latest - state.lastPrice!) / state.lastPrice! * 100.0;
      double volProxy = 1.0;
      if (amount != null && state.lastAmount != null && state.lastAmount! > 0) {
        volProxy = amount / state.lastAmount!;
      }
      if (chg >= _t.spikePricePct && volProxy >= kSpikeVolRatioDegraded) {
        hits.add(AlertHit(
          ruleId: 'spike_up',
          title: '[盘中急升]',
          body:
              '$label 现价 ${_fmt(latest)}，较前轮急涨+${chg.toStringAsFixed(2)}%，额比${volProxy.toStringAsFixed(2)}倍',
          cooldown: const Duration(minutes: 10),
        ));
      } else if (chg <= -_t.spikePricePct && volProxy >= kSpikeVolRatioDegraded) {
        hits.add(AlertHit(
          ruleId: 'spike_down',
          title: '[盘中急跌]',
          body:
              '$label 现价 ${_fmt(latest)}，较前轮急跌${chg.toStringAsFixed(2)}%，额比${volProxy.toStringAsFixed(2)}倍',
          cooldown: const Duration(minutes: 10),
        ));
      }
    }

    // ========== 2.2：冲高回落 ==========
    if (_t.families.spikePullback.isOn &&
        state.sessionHigh != null &&
        state.sessionLow != null) {
      final high = state.sessionHigh!;
      final low = state.sessionLow!;
      final leg = high > 0 ? (high - low) / high * 100.0 : 0.0;
      if (leg + 1e-9 >= _t.pullbackLegMinPct && latest < high) {
        final pb = (high - latest) / high * 100.0;
        if (pb + 1e-9 >= _t.pullbackPct) {
          final peakKey = high.toStringAsFixed(2);
          if (!state.pullbackFiredPeaks.contains(peakKey)) {
            state.pullbackFiredPeaks.add(peakKey);
            hits.add(AlertHit(
              ruleId: 'pullback_$peakKey',
              title: '[冲高回落]',
              body:
                  '$label 自日内高点 ${_fmt(high)} 回落至 ${_fmt(latest)}，回调${pb.toStringAsFixed(2)}%',
              cooldown: const Duration(minutes: 20),
            ));
          }
        }
      }
    }

    // ========== 2.2：早盘急升/急跌 ==========
    if (_t.families.gapMorningTail.isOn) {
      _morningAlerts(hits, label, latest, open, pctOpen, state, at);
    }

    // ========== 2.2：整数关口 ==========
    if (_t.families.patternTrend.isOn) {
      _integerGate(hits, label, latest, state);
    }

    // ========== 2.2：日内新高/新低（§43：须超过已告警价） ==========
    if (_t.families.patternTrend.isOn &&
        prevSessHigh != null &&
        prevSessLow != null) {
      if (latest > prevSessHigh + 1e-9) {
        final allow = state.lastAlertedHigh == null ||
            latest > state.lastAlertedHigh! * (1 + kSamePriceLevelRel);
        if (allow) {
          state.lastAlertedHigh = latest;
          state.dayHighFired = true;
          hits.add(AlertHit(
            ruleId: 'day_high_${latest.toStringAsFixed(2)}',
            title: '[日内新高]',
            body: '$label 突破日内高点 ${_fmt(prevSessHigh)}，现价 ${_fmt(latest)}',
            cooldown: const Duration(minutes: 25),
          ));
        }
      }
      if (latest < prevSessLow - 1e-9) {
        final allow = state.lastAlertedLow == null ||
            latest < state.lastAlertedLow! * (1 - kSamePriceLevelRel);
        if (allow) {
          state.lastAlertedLow = latest;
          state.dayLowFired = true;
          hits.add(AlertHit(
            ruleId: 'day_low_${latest.toStringAsFixed(2)}',
            title: '[日内新低]',
            body: '$label 跌破日内低点 ${_fmt(prevSessLow)}，现价 ${_fmt(latest)}',
            cooldown: const Duration(minutes: 25),
          ));
        }
      }
    }

    // ========== 极值确认 / 距极值 ==========
    if (_t.families.patternTrend.isOn) {
      final ex = extremeRegistry.onSnapshot(
        stateKey: tsCode,
        label: label,
        price: latest,
        round: state,
        now: at,
        dateKey: dateKey,
      );
      for (final e in ex) {
        hits.add(AlertHit(
          ruleId: e.ruleId,
          title: e.title,
          body: e.body,
          cooldown: Duration(
            minutes: e.title.contains('距极值')
                ? kExtremeDistanceCooldownMin.round()
                : kExtremeCooldownMin.round(),
          ),
        ));
      }
    }

    // ========== 2.2：换手 ==========
    if (_t.families.turnoverVolume.isOn) {
      _turnoverAlerts(hits, label, turnover, state, at);
    }

    // ========== 资金：穿零 / 拐点 / 反转 / 散户 / 筹码 ==========
    if (_t.families.fund.isOn || _t.families.chip.isOn) {
      _fundAlerts(hits, label, main, retail, ddx, ddy, ddz, state, profile);
    }

    // ========== DDZ 首段 / 拐点 ==========
    if (_t.families.chip.isOn && ddz != null) {
      _ddzTrack(hits, label, ddz, state, at);
    }

    // ========== 2.3：巨量 / 量异动 / 大单占比 / 量能首报 ==========
    if (_t.families.turnoverVolume.isOn) {
      _volumeAndRatio(
        hits,
        label,
        amount,
        mainRatio,
        volume,
        state,
        profile,
        at,
      );
      _volDigestFirst(hits, label, amount, state, at);
      _volDigestNoon(hits, label, amount, state, at);
    }

    // ========== 2.3：形态降级 ==========
    if (_t.families.patternTrend.isOn) {
      _patternAlerts(hits, label, latest, open, amount, state, at);
    }

    // ========== 2.3：尾盘 ==========
    if (_t.families.gapMorningTail.isOn) {
      _tailAlerts(hits, label, latest, state, at);
    }

    // ========== 2.3：VWAP ==========
    if (_t.families.patternTrend.isOn && vwap != null && vwap > 0 && main != null) {
      if (latest < vwap) {
        state.vwapBelowCount++;
      } else {
        if (!state.vwapFired &&
            state.vwapBelowCount >= kVwapBelowMinSnaps &&
            main / 10000.0 >= kVwapMainMinWan) {
          state.vwapFired = true;
          hits.add(AlertHit(
            ruleId: 'vwap_break',
            title: '[VWAP突破]',
            body:
                '$label 站上日内均价 ${_fmt(vwap)}，主力净流入 ${_fmtMoney(main)}',
            cooldown: const Duration(minutes: 45),
          ));
        }
        state.vwapBelowCount = 0;
      }
    }

    // ========== 2.3：盘中反转 ==========
    if (_t.families.patternTrend.isOn) {
      _intradayReversal(hits, label, latest, main, state);
    }

    // ========== 2.3：趋势族简化 ==========
    if (_t.families.patternTrend.isOn) {
      _trendFamily(hits, label, latest, state);
    }

    // ========== 2.3：伪 Bar-KDJ + 超买超卖 ==========
    if (_t.families.kdj15.isOn || _t.families.kdj5.isOn) {
      _pseudoKdj(hits, label, state, at);
    }

    // —— 更新尾状态 ——
    state.lastPrice = latest;
    state.lastAmount = amount;
    state.lastVolume = volume;
    state.lastTurnover = turnover;
    if (ddz != null) state.lastDdz = ddz;
    state.lastValidF2 = latest;

    return hits;
  }

  void _priceTiers(
    List<AlertHit> hits,
    String label,
    double latest,
    double? pctOpen,
    double? pctPc,
    SymbolRoundState state,
    List<double> tiersPct,
  ) {
    for (final tier in tiersPct) {
      final keyO = 'open_$tier';
      if (pctOpen != null &&
          pctOpen.abs() + 1e-9 >= tier &&
          !state.firedTiersOpen.contains(keyO)) {
        final dir = pctOpen >= 0 ? '上涨' : '下跌';
        hits.add(AlertHit(
          ruleId: 'price_tier_open_$tier',
          title: '[股价异动]',
          body:
              '$label 现价 ${_fmt(latest)}，较开盘$dir至 ${tier.toStringAsFixed(0)}% 档（${pctOpen.toStringAsFixed(2)}%）',
          cooldown: Duration(minutes: _t.cooldownMinutesForTier(tier)),
        ));
        state.firedTiersOpen.add(keyO);
      }
      final keyP = 'pc_$tier';
      if (pctPc != null &&
          pctPc.abs() + 1e-9 >= tier &&
          !state.firedTiersPc.contains(keyP)) {
        final dir = pctPc >= 0 ? '上涨' : '下跌';
        hits.add(AlertHit(
          ruleId: 'price_tier_pc_$tier',
          title: '[股价异动]',
          body:
              '$label 现价 ${_fmt(latest)}，较昨收$dir至 ${tier.toStringAsFixed(0)}% 档（${pctPc.toStringAsFixed(2)}%）',
          cooldown: Duration(minutes: _t.cooldownMinutesForTier(tier)),
        ));
        state.firedTiersPc.add(keyP);
      }
    }
  }

  void _morningAlerts(
    List<AlertHit> hits,
    String label,
    double latest,
    double? open,
    double? pctOpen,
    SymbolRoundState state,
    DateTime at,
  ) {
    if (open == null || pctOpen == null) return;
    final inMorningWindow = at.hour < _t.morningEndHour ||
        (at.hour == _t.morningEndHour && at.minute <= _t.morningEndMinute);
    if (inMorningWindow) {
      if (pctOpen >= _t.morningPct) {
        state.morningExtremePct = pctOpen;
        state.morningExtremeAt = at;
      } else if (pctOpen <= -_t.morningPct) {
        state.morningExtremePct = pctOpen;
        state.morningExtremeAt = at;
      }
    }
    final extAt = state.morningExtremeAt;
    final extPct = state.morningExtremePct;
    if (extAt == null || extPct == null) return;
    final elapsed = at.difference(extAt).inMinutes;
    if (elapsed < kMorningRepairMinutes) return;
    if (extPct >= _t.morningPct && !state.morningRiseFired) {
      final giveback = extPct - pctOpen;
      if (giveback <= extPct / 3.0) {
        state.morningRiseFired = true;
        hits.add(AlertHit(
          ruleId: 'morning_rise',
          title: '[早盘急升]',
          body:
              '$label 现价 ${_fmt(latest)}，较开盘+${pctOpen.toStringAsFixed(2)}%，${elapsed}分钟内回落不足涨幅三分之一',
          cooldown: const Duration(hours: 4),
        ));
      }
    }
    if (extPct <= -_t.morningPct && !state.morningFallFired) {
      final repair = pctOpen - extPct;
      if (repair <= (-extPct) / 3.0) {
        state.morningFallFired = true;
        hits.add(AlertHit(
          ruleId: 'morning_fall',
          title: '[早盘急跌]',
          body:
              '$label 现价 ${_fmt(latest)}，较开盘${pctOpen.toStringAsFixed(2)}%，${elapsed}分钟内反弹不足跌幅三分之一',
          cooldown: const Duration(hours: 4),
        ));
      }
    }
  }

  void _integerGate(List<AlertHit> hits, String label, double latest, SymbolRoundState state) {
    final level = latest.roundToDouble();
    if (level <= 0) return;
    final distPct = (latest - level).abs() / level * 100.0;
    if (distPct > kIntegerNearPct) return;
    final key = level.toStringAsFixed(0);
    if (state.integerFired.contains(key)) return;
    // 需从下方上穿或从上方下穿：用历史
    if (state.history.length < 2) return;
    final prev = state.history[state.history.length - 2].price;
    final crossUp = prev < level && latest >= level;
    final crossDn = prev > level && latest <= level;
    if (!crossUp && !crossDn) return;
    state.integerFired.add(key);
    hits.add(AlertHit(
      ruleId: 'integer_$key',
      title: '[整数关口]',
      body: '$label ${crossUp ? '突破' : '跌破'}${key}整数关位，现价 ${_fmt(latest)}',
      cooldown: const Duration(minutes: 20),
    ));
  }

  void _turnoverAlerts(
    List<AlertHit> hits,
    String label,
    double? turnover,
    SymbolRoundState state,
    DateTime at,
  ) {
    if (turnover == null) return;
    state.turnoverHist.add(turnover);
    final minutesFromOpen = (at.hour - 9) * 60 + at.minute - 30;
    if (turnover >= _t.turnoverHighPct) {
      hits.add(AlertHit(
        ruleId: 'turnover_high',
        title: '[换手极高]',
        body: '$label 换手率${turnover.toStringAsFixed(2)}%（≥${_t.turnoverHighPct.toStringAsFixed(0)}%）',
        cooldown: const Duration(minutes: 30),
      ));
    }
    if (minutesFromOpen >= 0 &&
        minutesFromOpen <= 60 &&
        turnover >= _t.turnoverMorningHighPct) {
      hits.add(AlertHit(
        ruleId: 'turnover_morning',
        title: '[早盘高换手]',
        body:
            '$label 开盘60分钟内换手率${turnover.toStringAsFixed(2)}%（≥${_t.turnoverMorningHighPct.toStringAsFixed(0)}%）',
        cooldown: const Duration(minutes: 30),
      ));
    }
    if (minutesFromOpen >= kTurnoverDryDisableBeforeMinute &&
        state.turnoverHist.length >= kTurnoverDryMinSamples &&
        turnover <= kTurnoverDryPct) {
      final sorted = [...state.turnoverHist]..sort();
      final med = sorted[sorted.length ~/ 2];
      if (turnover <= med) {
        hits.add(AlertHit(
          ruleId: 'turnover_dry',
          title: '[地量换手]',
          body:
              '$label 换手率${turnover.toStringAsFixed(2)}%（≤${kTurnoverDryPct.toStringAsFixed(2)}%且≤日内中位）',
          cooldown: const Duration(minutes: 30),
        ));
      }
    }
  }

  void _fundAlerts(
    List<AlertHit> hits,
    String label,
    double? main,
    double? retail,
    double? ddx,
    double? ddy,
    double? ddz,
    SymbolRoundState state,
    WatchSymbol profile,
  ) {
    if (_t.families.fund.isOn && main != null && state.lastMainNet != null) {
      final prev = state.lastMainNet!;
      if (prev < 0 && main > 0 && main.abs() >= _t.mainCrossMinYuan) {
        state.mainCrossedUp = true;
        hits.add(AlertHit(
          ruleId: 'main_cross_up',
          title: '[主力穿零]',
          body: '$label 主力净流入由负转正 ${_fmtMoney(main)}',
          cooldown: const Duration(minutes: 20),
        ));
      } else if (prev > 0 && main < 0 && main.abs() >= _t.mainCrossMinYuan) {
        state.mainCrossedDown = true;
        hits.add(AlertHit(
          ruleId: 'main_cross_down',
          title: '[主力穿零]',
          body: '$label 主力净流入由正转负 ${_fmtMoney(main)}',
          cooldown: const Duration(minutes: 20),
        ));
      }

      // 主力反转：穿零后 |主力| 达标
      if (state.mainCrossedUp &&
          !state.mainReversalUpFired &&
          main >= _t.mainCrossMinYuan) {
        state.mainReversalUpFired = true;
        hits.add(AlertHit(
          ruleId: 'main_reversal_up',
          title: '[主力反转]',
          body: '$label 主力加仓达标 ${_fmtMoney(main)}',
          cooldown: const Duration(minutes: 30),
        ));
      }
      if (state.mainCrossedDown &&
          !state.mainReversalDownFired &&
          main <= -_t.mainCrossMinYuan) {
        state.mainReversalDownFired = true;
        hits.add(AlertHit(
          ruleId: 'main_reversal_down',
          title: '[主力反转]',
          body: '$label 主力减仓达标 ${_fmtMoney(main)}',
          cooldown: const Duration(minutes: 30),
        ));
      }

      final delta = main - prev;
      if (state.lastMainDelta != null) {
        final prevD = state.lastMainDelta!;
        if (prevD > 0 && delta < 0 && delta.abs() >= _t.mainCrossMinYuan) {
          hits.add(AlertHit(
            ruleId: 'main_delta_inflect_down',
            title: '[主力净额拐点]',
            body: '$label 主力净流入增量由正转负 Δ=${_fmtMoney(delta)}',
            cooldown: const Duration(minutes: 5),
          ));
        } else if (prevD < 0 && delta > 0 && delta.abs() >= _t.mainCrossMinYuan) {
          hits.add(AlertHit(
            ruleId: 'main_delta_inflect_up',
            title: '[主力净额拐点]',
            body: '$label 主力净流入增量由负转正 Δ=${_fmtMoney(delta)}',
            cooldown: const Duration(minutes: 5),
          ));
        }
      }
      state.lastMainDelta = delta;
    }
    if (main != null) state.lastMainNet = main;

    // 散户：绝对值首次达标（冷却防刷；更严边沿待对拍）
    if (_t.families.fund.isOn && retail != null) {
      if (retail >= _t.retailCrossMinYuan && !state.retailPosFired) {
        state.retailPosFired = true;
        hits.add(AlertHit(
          ruleId: 'retail_in',
          title: '[散户异动]',
          body: '$label 小单净流入 ${_fmtMoney(retail)}（跟风增强）',
          cooldown: const Duration(minutes: 30),
        ));
      } else if (retail <= -_t.retailCrossMinYuan && !state.retailNegFired) {
        state.retailNegFired = true;
        hits.add(AlertHit(
          ruleId: 'retail_out',
          title: '[散户异动]',
          body: '$label 小单净流出 ${_fmtMoney(retail)}（抛压增强）',
          cooldown: const Duration(minutes: 30),
        ));
      }
    }

    // 筹码异动（吸筹/出逃）；有市值档时升格首次 DDZ 绝对值门槛
    if (_t.families.chip.isOn && ddx != null && ddy != null) {
      final absMin = profile.hasCircMvProfile
          ? ddzAbsMin(board: profile.board, tier: profile.effectiveTier)
          : null;
      final firstChip = state.lastDdz == null;
      final bool ddzOk;
      if (absMin == null) {
        ddzOk = true; // 降级：与现 APP 放宽一致
      } else if (ddz == null) {
        ddzOk = true;
      } else if (firstChip) {
        ddzOk = ddz.abs() + 1e-9 >= absMin;
      } else {
        ddzOk = (ddz - state.lastDdz!).abs() >= kDdzDeltaMin;
      }
      final bull =
          ddx >= kDdxChipMin && ddy >= kDdxChipMin && ddzOk;
      final bear =
          ddx <= -kDdxChipMin && ddy <= -kDdxChipMin && ddzOk;
      if (bull && state.ddxChipSide != 1) {
        if (state.ddxChipRearm <= 0 || state.ddxChipSide == -1) {
          state.ddxChipSide = 1;
          state.ddxChipRearm = 2;
          hits.add(AlertHit(
            ruleId: 'chip_bull',
            title: '[筹码异动]',
            body:
                '$label 主力吸筹：DDX=${ddx.toStringAsFixed(3)} DDY=${ddy.toStringAsFixed(3)}'
                '${ddz != null ? ' DDZ=${ddz.toStringAsFixed(2)}' : ''}'
                '${absMin != null ? '（完整规则，DDZ≥${absMin.toStringAsFixed(0)}）' : ''}',
            cooldown: const Duration(minutes: 30),
          ));
        }
      } else if (bear && state.ddxChipSide != -1) {
        if (state.ddxChipRearm <= 0 || state.ddxChipSide == 1) {
          state.ddxChipSide = -1;
          state.ddxChipRearm = 2;
          hits.add(AlertHit(
            ruleId: 'chip_bear',
            title: '[筹码异动]',
            body:
                '$label 主力出逃：DDX=${ddx.toStringAsFixed(3)} DDY=${ddy.toStringAsFixed(3)}'
                '${ddz != null ? ' DDZ=${ddz.toStringAsFixed(2)}' : ''}'
                '${absMin != null ? '（完整规则，DDZ≥${absMin.toStringAsFixed(0)}）' : ''}',
            cooldown: const Duration(minutes: 30),
          ));
        }
      } else if (!bull && !bear && state.ddxChipRearm > 0) {
        state.ddxChipRearm--;
      }
    }
  }

  void _volumeAndRatio(
    List<AlertHit> hits,
    String label,
    double? amount,
    double? mainRatio,
    double? volume,
    SymbolRoundState state,
    WatchSymbol profile,
    DateTime at,
  ) {
    if (amount != null && !state.hugeAmountFired) {
      final yi = amount / 1e8;
      if (yi >= _t.hugeAmountYi) {
        state.hugeAmountFired = true;
        hits.add(AlertHit(
          ruleId: 'huge_amount',
          title: '[巨量成交]',
          body: '$label 当日成交额约${yi.toStringAsFixed(2)}亿元（阈值${_t.hugeAmountYi.toStringAsFixed(0)}亿）',
          cooldown: const Duration(hours: 4),
        ));
      }
    }

    // 成交量异动：填了近5日均量 → 预估全日量/均量；否则额环比降级
    if (profile.hasAvgVol5d) {
      final est = estimateFullDayLots(volumeShares: volume, at: at);
      if (est != null) {
        final ratio = est / profile.avgVol5dLots!;
        if (!state.volHighFired && ratio >= kVolRatioHighFull) {
          state.volHighFired = true;
          hits.add(AlertHit(
            ruleId: 'vol_high',
            title: '[成交量异动]',
            body:
                '$label 预估全日量/近5日均量约${ratio.toStringAsFixed(2)}倍（≥${kVolRatioHighFull.toStringAsFixed(1)}，完整规则）',
            cooldown: const Duration(minutes: 90),
          ));
        }
        if (!state.volLowFired && ratio <= kVolRatioLowFull) {
          state.volLowFired = true;
          hits.add(AlertHit(
            ruleId: 'vol_low',
            title: '[成交量异动]',
            body:
                '$label 预估全日量/近5日均量约${ratio.toStringAsFixed(2)}倍（≤${kVolRatioLowFull.toStringAsFixed(1)}，完整规则）',
            cooldown: const Duration(minutes: 90),
          ));
        }
      }
    } else if (state.history.length >= 4 &&
        state.lastAmount != null &&
        amount != null) {
      final recent = state.history.sublist(state.history.length - 4);
      final amts =
          recent.map((e) => e.amount ?? 0).where((e) => e > 0).toList();
      if (amts.length >= 3) {
        final first = amts.first;
        final last = amts.last;
        final ratio = first > 0 ? last / first : 1.0;
        if (!state.volHighFired && ratio >= kVolRatioHigh) {
          state.volHighFired = true;
          hits.add(AlertHit(
            ruleId: 'vol_high_degraded',
            title: '[成交量异动]',
            body:
                '$label 近段成交额放大约${ratio.toStringAsFixed(2)}倍（简化规则：无5日均量，放量代理）',
            cooldown: const Duration(minutes: 40),
          ));
        }
        if (!state.volLowFired && ratio <= kVolRatioLow && last > 0) {
          state.volLowFired = true;
          hits.add(AlertHit(
            ruleId: 'vol_low_degraded',
            title: '[成交量异动]',
            body:
                '$label 近段成交额萎缩约${ratio.toStringAsFixed(2)}倍（简化规则：无5日均量，缩量代理）',
            cooldown: const Duration(minutes: 40),
          ));
        }
      }
    }

    if (mainRatio == null) return;
    final part = profile.hasCircMvProfile
        ? participationForTier(profile.effectiveTier)
        : null;

    // 首报 / 午报：不占 mainRatioHighFired
    void maybeDigest(bool fired, void Function() mark, int hour, String title, String ruleId) {
      if (fired) return;
      if (at.hour < hour) return;
      if (part != null) {
        final amountWan = amount != null ? amount / 10000.0 : 0.0;
        if (amountWan < part.minAmountWan) return;
        final ratioFrac = mainRatio / 100.0;
        final band = ratioFrac.abs() >= part.ratio ? '已越界' : '未越界';
        mark();
        hits.add(AlertHit(
          ruleId: ruleId,
          title: title,
          body:
              '$label 主力净额/成交额约${mainRatio.toStringAsFixed(1)}%'
              '（阈值≥${(part.ratio * 100).toStringAsFixed(0)}%·$band，'
              '${profile.effectiveTier.labelZh}·完整规则）',
          cooldown: const Duration(hours: 6),
        ));
      } else {
        final band = mainRatio >= kMainRatioHighPct ? '已越界' : '未越界';
        mark();
        hits.add(AlertHit(
          ruleId: ruleId,
          title: title,
          body:
              '$label 主力净额/成交额约${mainRatio.toStringAsFixed(1)}%'
              '（阈值≥${kMainRatioHighPct.toStringAsFixed(0)}%·$band，简化规则）',
          cooldown: const Duration(hours: 6),
        ));
      }
    }

    maybeDigest(
      state.mainRatioFirstDigestFired,
      () => state.mainRatioFirstDigestFired = true,
      kMainRatioDigestFirstHour,
      '[大单占比-首报]',
      'main_ratio_first_digest',
    );
    maybeDigest(
      state.mainRatioNoonDigestFired,
      () => state.mainRatioNoonDigestFired = true,
      kMainRatioDigestNoonHour,
      '[大单占比-午报]',
      'main_ratio_noon_digest',
    );

    if (part != null) {
      final amountWan = amount != null ? amount / 10000.0 : 0.0;
      final ratioFrac = mainRatio / 100.0;
      if (!state.mainRatioHighFired &&
          amountWan >= part.minAmountWan &&
          ratioFrac.abs() >= part.ratio) {
        state.mainRatioHighFired = true;
        hits.add(AlertHit(
          ruleId: 'main_ratio_high',
          title: '[大单占比]',
          body:
              '$label 主力净额/成交额约${mainRatio.toStringAsFixed(1)}%'
              '（≥${(part.ratio * 100).toStringAsFixed(0)}%，'
              '${profile.effectiveTier.labelZh}·完整规则）',
          cooldown: const Duration(minutes: 35),
        ));
      }
      if (!state.mainRatioLowFired &&
          amountWan >= part.minAmountWan &&
          ratioFrac.abs() < part.absentRatio) {
        state.mainRatioLowFired = true;
        hits.add(AlertHit(
          ruleId: 'main_ratio_low',
          title: '[主力缺席]',
          body:
              '$label 主力净额/成交额约${mainRatio.toStringAsFixed(1)}%'
              '（<${(part.absentRatio * 100).toStringAsFixed(0)}%，'
              '${profile.effectiveTier.labelZh}·完整规则）',
          cooldown: const Duration(minutes: 35),
        ));
      }
    } else {
      if (!state.mainRatioHighFired && mainRatio >= kMainRatioHighPct) {
        state.mainRatioHighFired = true;
        hits.add(AlertHit(
          ruleId: 'main_ratio_high',
          title: '[大单占比]',
          body:
              '$label 主力净额/成交额约${mainRatio.toStringAsFixed(1)}%（≥${kMainRatioHighPct.toStringAsFixed(0)}%，简化规则·无市值分档）',
          cooldown: const Duration(minutes: 35),
        ));
      }
      if (!state.mainRatioLowFired && mainRatio.abs() < kMainRatioLowPct) {
        state.mainRatioLowFired = true;
        hits.add(AlertHit(
          ruleId: 'main_ratio_low',
          title: '[主力缺席]',
          body:
              '$label 主力净额/成交额约${mainRatio.toStringAsFixed(1)}%（<${kMainRatioLowPct.toStringAsFixed(0)}%，简化规则）',
          cooldown: const Duration(minutes: 35),
        ));
      }
    }
  }

  void _patternAlerts(
    List<AlertHit> hits,
    String label,
    double latest,
    double? open,
    double? amount,
    SymbolRoundState state,
    DateTime at,
  ) {
    final win = state.history.where(
      (p) => at.difference(p.at).inMinutes <= kPlatformMinutes,
    ).toList();
    if (win.length >= 4) {
      final hi = win.map((e) => e.price).reduce((a, b) => a > b ? a : b);
      final lo = win.map((e) => e.price).reduce((a, b) => a < b ? a : b);
      final mid = (hi + lo) / 2;
      final amp = mid > 0 ? (hi - lo) / mid * 100.0 : 0.0;
      double volR = 1.0;
      if (amount != null && win.first.amount != null && win.first.amount! > 0) {
        volR = amount / win.first.amount!;
      }
      // 破平台
      if (latest < lo && volR >= kPlatformVolRatio) {
        hits.add(AlertHit(
          ruleId: 'break_platform',
          title: '[破平台]',
          body:
              '$label 跌破平台支撑 ${_fmt(lo)}，额比${volR.toStringAsFixed(2)}倍（简化规则）',
          cooldown: const Duration(minutes: 25),
        ));
      }
      // 横盘突破
      if (amp < kPlatformAmpPct) {
        final key = '${lo.toStringAsFixed(2)}_${hi.toStringAsFixed(2)}';
        final dev = mid > 0 ? (latest - mid).abs() / mid * 100.0 : 0.0;
        if (dev >= kBreakoutDevPct &&
            volR >= 2.0 &&
            state.boxKey != key) {
          state.boxKey = key;
          final up = latest > mid;
          hits.add(AlertHit(
            ruleId: 'box_break_${up ? 'up' : 'dn'}',
            title: '[横盘突破]',
            body: '$label 放量突破整理平台，方向${up ? '上' : '下'}（简化规则）',
            cooldown: const Duration(minutes: 30),
          ));
        }
      }
    }

    if (open != null) {
      if (latest < open) state.brokeBelowOpen = true;
      if (state.brokeBelowOpen && latest >= open) {
        final isAm = at.hour < 12;
        if (isAm && !state.openBreakAmFired) {
          state.openBreakAmFired = true;
          hits.add(AlertHit(
            ruleId: 'open_break_am',
            title: '[开盘突破]',
            body: '$label 重新站上开盘价 ${_fmt(open)}（上午，简化规则）',
            cooldown: const Duration(minutes: 30),
          ));
        } else if (!isAm && !state.openBreakPmFired) {
          state.openBreakPmFired = true;
          hits.add(AlertHit(
            ruleId: 'open_break_pm',
            title: '[开盘突破]',
            body: '$label 重新站上开盘价 ${_fmt(open)}（午后，简化规则）',
            cooldown: const Duration(minutes: 30),
          ));
        }
      }
    }
  }

  void _tailAlerts(
    List<AlertHit> hits,
    String label,
    double latest,
    SymbolRoundState state,
    DateTime at,
  ) {
    if (at.hour < kTailStartHour) return;
    final lookback = state.history.where(
      (p) => at.difference(p.at).inMinutes <= 10,
    ).toList();
    if (lookback.length < 2) return;
    final base = lookback.first.price;
    if (base <= 0) return;
    final chg = (latest - base) / base * 100.0;
    if (!state.tailDumpFired && chg <= -_t.tailDumpPct) {
      state.tailDumpFired = true;
      hits.add(AlertHit(
        ruleId: 'tail_dump',
        title: '[尾盘跳水]',
        body:
            '$label ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}急跌${chg.toStringAsFixed(2)}%（简化规则：未计成交占比）',
        cooldown: const Duration(minutes: 12),
      ));
    }
    if (!state.tailPumpFired && chg >= _t.tailPumpPct) {
      state.tailPumpFired = true;
      hits.add(AlertHit(
        ruleId: 'tail_pump',
        title: '[尾盘偷袭]',
        body:
            '$label ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}急涨+${chg.toStringAsFixed(2)}%（简化规则）',
        cooldown: const Duration(minutes: 12),
      ));
    }
  }

  void _intradayReversal(
    List<AlertHit> hits,
    String label,
    double latest,
    double? main,
    SymbolRoundState state,
  ) {
    if (state.intradayRevFired || state.sessionLow == null || state.sessionHigh == null) {
      return;
    }
    final low = state.sessionLow!;
    final high = state.sessionHigh!;
    final drop = high > 0 ? (high - low) / high : 0.0;
    if (drop < 0.02) return;
    final rebound = low > 0 ? (latest - low) / low : 0.0;
    if (main != null && state.lastMainNet != null) {
      if (main > state.lastMainNet!) {
        state.mainInflowStreak++;
      } else {
        state.mainInflowStreak = 0;
      }
    }
    if (rebound >= drop * kIntradayRevHalf &&
        state.mainInflowStreak >= kIntradayRevMainStreak) {
      state.intradayRevFired = true;
      hits.add(AlertHit(
        ruleId: 'intraday_rev',
        title: '[盘中反转]',
        body:
            '$label 自低点 ${_fmt(low)} 回升${(rebound * 100).toStringAsFixed(2)}%，主力连续净流入放大（简化规则）',
        cooldown: const Duration(minutes: 40),
      ));
    }
  }

  void _trendFamily(
    List<AlertHit> hits,
    String label,
    double latest,
    SymbolRoundState state,
  ) {
    // 简化 EMA
    const alpha = 0.3;
    if (state.emaPrice == null) {
      state.emaPrice = latest;
      return;
    }
    final prevEma = state.emaPrice!;
    final ema = alpha * latest + (1 - alpha) * prevEma;
    final slope = ema - prevEma;
    state.emaPrice = ema;
    state.emaSlopes.add(slope);
    if (state.emaSlopes.length > 8) state.emaSlopes.removeAt(0);
    state.peakEmaSlope = state.peakEmaSlope == null
        ? slope.abs()
        : (slope.abs() > state.peakEmaSlope! ? slope.abs() : state.peakEmaSlope);

    final dir = slope >= 0 ? 'up' : 'down';
    if (state.lastTrendDir != null && state.lastTrendDir != dir) {
      hits.add(AlertHit(
        ruleId: 'trend_rev_$dir',
        title: dir == 'up' ? '[趋势反转↑]' : '[趋势反转↓]',
        body: '$label 价格动能由${dir == 'up' ? '跌转涨' : '涨转跌'}（简化规则）',
        cooldown: const Duration(minutes: 15),
      ));
    }
    state.lastTrendDir = dir;

    if (state.emaSlopes.length >= 3) {
      final a = state.emaSlopes[state.emaSlopes.length - 3];
      final b = state.emaSlopes[state.emaSlopes.length - 2];
      final c = state.emaSlopes.last;
      if (a > b && b > c && c > 0) {
        hits.add(AlertHit(
          ruleId: 'speed_slow_up',
          title: '[涨速放缓]',
          body: '$label 上涨动能减弱（简化规则）',
          cooldown: const Duration(minutes: 20),
        ));
      }
      if (a < b && b < c && c < 0) {
        hits.add(AlertHit(
          ruleId: 'speed_slow_dn',
          title: '[降速放缓]',
          body: '$label 下跌动能减弱（简化规则）',
          cooldown: const Duration(minutes: 20),
        ));
      }
    }

    if (state.peakEmaSlope != null && state.peakEmaSlope! > 1e-6) {
      if (slope.abs() < state.peakEmaSlope! * 0.3) {
        state.decayCount++;
      } else {
        state.decayCount = 0;
      }
      if (state.decayCount >= 3) {
        hits.add(AlertHit(
          ruleId: 'momentum_decay',
          title: '[动能衰减]',
          body: '$label 价格动能衰减（简化规则）',
          cooldown: const Duration(minutes: 25),
        ));
        state.decayCount = 0;
      }
    }

    if (slope.abs() < 1e-4 && state.emaSlopes.length >= 4) {
      hits.add(AlertHit(
        ruleId: slope >= 0 ? 'exhaust_up' : 'exhaust_dn',
        title: slope >= 0 ? '[涨势衰竭]' : '[跌势衰竭]',
        body: '$label EMA 斜率接近零（简化规则）',
        cooldown: const Duration(minutes: 30),
      ));
    }
  }

  void _pseudoKdj(
    List<AlertHit> hits,
    String label,
    SymbolRoundState state,
    DateTime at,
  ) {
    if (state.history.length < 9) return;
    void updateTrack(int win, void Function(double k, double d) setKD) {
      final slice = state.history.sublist(state.history.length - win);
      final hi = slice.map((e) => e.price).reduce((a, b) => a > b ? a : b);
      final lo = slice.map((e) => e.price).reduce((a, b) => a < b ? a : b);
      final c = slice.last.price;
      final rsv = (hi - lo).abs() < 1e-9 ? 50.0 : (c - lo) / (hi - lo) * 100.0;
      final k = rsv;
      final d = slice.length >= 3
          ? slice.sublist(slice.length - 3).map((e) {
              final h = hi;
              final l = lo;
              return (h - l).abs() < 1e-9
                  ? 50.0
                  : (e.price - l) / (h - l) * 100.0;
            }).reduce((a, b) => a + b) /
              3.0
          : rsv;
      setKD(k, d);
    }

    state.prevK5 = state.k5;
    state.prevD5 = state.d5;
    state.prevK15 = state.k15;
    state.prevD15 = state.d15;
    state.prevJ15 = state.j15;
    if (state.history.length >= 5 && _t.families.kdj5.isOn) {
      updateTrack(5, (k, d) {
        state.k5 = k;
        state.d5 = d;
      });
    } else if (!_t.families.kdj5.isOn) {
      state.k5 = state.d5 = state.prevK5 = state.prevD5 = null;
    }
    updateTrack(9, (k, d) {
      state.k15 = k;
      state.d15 = d;
      state.j15 = 3.0 * k - 2.0 * d;
    });

    var golden15 = false;
    var death15 = false;

    void cross(String tag, double? pk, double? pd, double? k, double? d) {
      if (tag == '5' && !_t.families.kdj5.isOn) return;
      if (tag == '15' && !_t.families.kdj15.isOn) return;
      if (pk == null || pd == null || k == null || d == null) return;
      if (pk <= pd && k > d) {
        if (tag == '15') golden15 = true;
        hits.add(AlertHit(
          ruleId: 'kdj_${tag}_golden',
          title: tag == '5' ? '[KDJ5金叉]' : '[KDJ15金叉]',
          body: '$label 伪窗 KDJ 金叉（简化规则·非官方 K 线）',
          cooldown: const Duration(minutes: 20),
        ));
      } else if (pk >= pd && k < d) {
        if (tag == '15') death15 = true;
        hits.add(AlertHit(
          ruleId: 'kdj_${tag}_death',
          title: tag == '5' ? '[KDJ5死叉]' : '[KDJ15死叉]',
          body: '$label 伪窗 KDJ 死叉（简化规则·非官方 K 线）',
          cooldown: const Duration(minutes: 20),
        ));
      }
    }

    cross('5', state.prevK5, state.prevD5, state.k5, state.d5);
    cross('15', state.prevK15, state.prevD15, state.k15, state.d15);

    if (_t.families.kdj15.isOn) {
      _obOsOnJ15(
        hits,
        label,
        state,
        at,
        suppressEmit: golden15 || death15,
      );
    }
  }

  void _obOsOnJ15(
    List<AlertHit> hits,
    String label,
    SymbolRoundState state,
    DateTime at, {
    required bool suppressEmit,
  }) {
    final jNew = state.j15;
    if (jNew == null) return;
    final openMins = at.hour * 60 + at.minute - (9 * 60 + 30);
    if (openMins < kObOsOpenGateMinutes) {
      state.prevJ15 = jNew;
      return;
    }
    final jPrev = state.prevJ15;
    if (jPrev == null) return;

    bool coolOk(DateTime? last) {
      if (last == null) return true;
      return at.difference(last).inMinutes >= kObOsCooldownMinutes;
    }

    // 进入超买
    if (jPrev <= kObOsHigh && jNew > kObOsHigh && state.obArmed) {
      if (state.obEnterCount < kObOsMaxEnterPerDay && coolOk(state.lastObEnterAt)) {
        state.obEnterCount++;
        state.lastObEnterAt = at;
        state.obArmed = false;
        if (!suppressEmit) {
          hits.add(AlertHit(
            ruleId: 'ob_enter',
            title: '[超买]',
            body:
                '$label 伪窗 J 上穿${kObOsHigh.toStringAsFixed(0)}（J=${jNew.toStringAsFixed(1)}），进入超买区（简化规则）',
            cooldown: const Duration(minutes: 20),
          ));
        }
      }
    }
    // 离开超买
    if (jPrev >= kObOsHigh && jNew < kObOsHigh) {
      if (state.obExitCount < kObOsMaxExitPerDay && coolOk(state.lastObExitAt)) {
        state.obExitCount++;
        state.lastObExitAt = at;
        state.obArmed = true;
        if (!suppressEmit) {
          hits.add(AlertHit(
            ruleId: 'ob_exit',
            title: '[超买解除]',
            body:
                '$label 伪窗 J 跌破${kObOsHigh.toStringAsFixed(0)}（J=${jNew.toStringAsFixed(1)}），离开超买区（简化规则）',
            cooldown: const Duration(minutes: 20),
          ));
        }
      } else {
        state.obArmed = true;
      }
    }
    // 进入超卖
    if (jPrev >= kObOsLow && jNew < kObOsLow && state.osArmed) {
      if (state.osEnterCount < kObOsMaxEnterPerDay && coolOk(state.lastOsEnterAt)) {
        state.osEnterCount++;
        state.lastOsEnterAt = at;
        state.osArmed = false;
        if (!suppressEmit) {
          hits.add(AlertHit(
            ruleId: 'os_enter',
            title: '[超卖]',
            body:
                '$label 伪窗 J 下穿${kObOsLow.toStringAsFixed(0)}（J=${jNew.toStringAsFixed(1)}），进入超卖区（简化规则）',
            cooldown: const Duration(minutes: 20),
          ));
        }
      }
    }
    // 离开超卖
    if (jPrev <= kObOsLow && jNew > kObOsLow) {
      if (state.osExitCount < kObOsMaxExitPerDay && coolOk(state.lastOsExitAt)) {
        state.osExitCount++;
        state.lastOsExitAt = at;
        state.osArmed = true;
        if (!suppressEmit) {
          hits.add(AlertHit(
            ruleId: 'os_exit',
            title: '[超卖解除]',
            body:
                '$label 伪窗 J 升破${kObOsLow.toStringAsFixed(0)}（J=${jNew.toStringAsFixed(1)}），离开超卖区（简化规则）',
            cooldown: const Duration(minutes: 20),
          ));
        }
      } else {
        state.osArmed = true;
      }
    }
  }

  void _priceTierFall(
    List<AlertHit> hits,
    String label,
    double latest,
    double? pctOpen,
    double? pctPc,
    SymbolRoundState state,
    List<double> tiersPct,
  ) {
    void check(String anchor, double? pct, double? peak, String prefix) {
      if (pct == null || peak == null) return;
      final eligible = [
        for (final t in tiersPct)
          if (peak + 1e-9 >= t) t
      ];
      if (eligible.isEmpty) return;
      final highest = eligible.reduce((a, b) => a > b ? a : b);
      if (pct >= highest - 1e-9 || pct < 0) return;
      final key = '${prefix}_${highest.toStringAsFixed(0)}';
      if (state.priceTierFallFired.contains(key)) return;
      state.priceTierFallFired.add(key);
      final anchorLabel = anchor == 'open' ? '较开盘价' : '较昨收';
      final sign = pct >= 0 ? '+' : '';
      hits.add(AlertHit(
        ruleId: 'price_tier_fall_$key',
        title: '[价档回落]',
        body:
            '$label 现价 ${_fmt(latest)}，$anchorLabel $sign${pct.toStringAsFixed(2)}%，由涨超 ${highest.toStringAsFixed(0)}% 回落。',
        cooldown: const Duration(minutes: 35),
      ));
    }

    check('open', pctOpen, state.peakPctOpen, 'fall_open');
    check('pc', pctPc, state.peakPctPc, 'fall_pc');
  }

  void _ddzTrack(
    List<AlertHit> hits,
    String label,
    double ddz,
    SymbolRoundState state,
    DateTime at,
  ) {
    final eps = kDdzTrackDeltaEps;
    if (!state.ddzFirstLegDone) {
      if (state.ddzTrackV1 == null) {
        state.ddzTrackV1 = ddz;
        state.ddzTrackT1 = at;
      } else {
        final v1 = state.ddzTrackV1!;
        final delta = ddz - v1;
        final dir = delta >= 0 ? '上行' : '下行';
        hits.add(AlertHit(
          ruleId: 'ddz_first_leg',
          title: '[DDZ首段方向]',
          body:
              '$label 首段ΔDDZ=${delta.toStringAsFixed(3)}（$dir，${v1.toStringAsFixed(2)}→${ddz.toStringAsFixed(2)}；结构提示）',
          cooldown: const Duration(hours: 6),
        ));
        state.ddzFirstLegDone = true;
      }
    }
    final prev = state.ddzTrackPrev;
    final prevAt = state.ddzTrackPrevAt;
    if (prev != null) {
      var gapOk = true;
      if (prevAt != null &&
          at.difference(prevAt).inSeconds > kDdzInflectGapSkipSec) {
        gapOk = false;
        state.ddzTrackPrevDelta = null;
      }
      if (gapOk) {
        final delta = ddz - prev;
        final pd = state.ddzTrackPrevDelta;
        if (pd != null &&
            pd != 0 &&
            delta != 0 &&
            ((pd < 0 && delta > 0) || (pd > 0 && delta < 0)) &&
            pd.abs() >= eps &&
            delta.abs() >= eps) {
          final peakTurn = pd > 0 && delta < 0;
          hits.add(AlertHit(
            ruleId: 'ddz_inflect_${at.millisecondsSinceEpoch}',
            title: '[DDZ拐点]',
            body:
                '$label DDZ${peakTurn ? '见峰拐头' : '见谷拐头'}（Δ ${pd.toStringAsFixed(3)}→${delta.toStringAsFixed(3)}，DDZ=${ddz.toStringAsFixed(2)}；结构提示）',
            cooldown: const Duration(minutes: 5),
          ));
          state.ddzLastInflectAt = at;
        }
        state.ddzTrackPrevDelta = delta;
      }
    }
    state.ddzTrackPrev = ddz;
    state.ddzTrackPrevAt = at;
  }

  void _volDigestFirst(
    List<AlertHit> hits,
    String label,
    double? amount,
    SymbolRoundState state,
    DateTime at,
  ) {
    if (state.volDigestFirstFired) return;
    if (at.hour < kVolDigestFirstHour ||
        (at.hour == kVolDigestFirstHour && at.minute < kVolDigestFirstMinute)) {
      return;
    }
    _emitVolDigest(
      hits,
      label,
      state,
      at,
      title: '[量能对比-首报]',
      ruleId: 'vol_digest_first',
      mark: () => state.volDigestFirstFired = true,
    );
  }

  void _volDigestNoon(
    List<AlertHit> hits,
    String label,
    double? amount,
    SymbolRoundState state,
    DateTime at,
  ) {
    if (state.volDigestNoonFired) return;
    if (at.hour < kVolDigestNoonHour ||
        (at.hour == kVolDigestNoonHour && at.minute < kVolDigestNoonMinute)) {
      return;
    }
    _emitVolDigest(
      hits,
      label,
      state,
      at,
      title: '[量能对比-午报]',
      ruleId: 'vol_digest_noon',
      mark: () => state.volDigestNoonFired = true,
      noon: true,
    );
  }

  void _emitVolDigest(
    List<AlertHit> hits,
    String label,
    SymbolRoundState state,
    DateTime at, {
    required String title,
    required String ruleId,
    required void Function() mark,
    bool noon = false,
  }) {
    final amts = [
      for (final p in state.history)
        if (p.amount != null && p.amount! > 0) p.amount!
    ];
    if (amts.length < kVolDigestMinSamples) return;
    final latestA = amts.last;
    final base = amts.sublist(0, amts.length - 1).reduce((a, b) => a + b) /
        (amts.length - 1);
    if (base <= 0) return;
    final ratio = latestA / base;
    mark();
    String tag;
    if (ratio >= kVolDigestAmountRatioHigh) {
      tag = '已放量';
    } else if (ratio <= kVolDigestAmountRatioLow) {
      tag = '已缩量';
    } else {
      tag = '未越界';
    }
    final mins = at.hour * 60 + at.minute - (9 * 60 + 30);
    final head = noon ? '午前定格约' : '开盘约';
    hits.add(AlertHit(
      ruleId: ruleId,
      title: title,
      body:
          '$label $head${mins < 0 ? 0 : mins}分钟，累计额环比倍数=${ratio.toStringAsFixed(2)}（$tag；降级代理）',
      cooldown: const Duration(hours: 6),
    ));
  }

  static String _fmt(double v) {
    if (v >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(3);
  }

  static String _fmtMoney(double yuan) {
    final wan = yuan / 10000.0;
    if (wan.abs() >= 10000) {
      return '${(wan / 10000).toStringAsFixed(2)}亿';
    }
    return '${wan.toStringAsFixed(0)}万';
  }
}
