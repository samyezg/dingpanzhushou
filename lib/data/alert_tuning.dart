/// 二期告警调参：骨（价档/资金/族投递三态）+ 肉（常用阈值）。专家区暂不入模。
library;

import '../core/constants.dart';
import '../rules/rule_thresholds.dart';

/// 规则族投递：关 / 仅记录（告警页有、不推送）/ 通知
enum FamilyDeliveryMode {
  off,
  recordOnly,
  notify,
}

extension FamilyDeliveryModeX on FamilyDeliveryMode {
  bool get isOn => this != FamilyDeliveryMode.off;
  bool get shouldNotify => this == FamilyDeliveryMode.notify;

  String get id {
    switch (this) {
      case FamilyDeliveryMode.off:
        return 'off';
      case FamilyDeliveryMode.recordOnly:
        return 'record';
      case FamilyDeliveryMode.notify:
        return 'notify';
    }
  }

  String get labelZh {
    switch (this) {
      case FamilyDeliveryMode.off:
        return '关';
      case FamilyDeliveryMode.recordOnly:
        return '仅记录';
      case FamilyDeliveryMode.notify:
        return '通知';
    }
  }

  static FamilyDeliveryMode parse(dynamic v, FamilyDeliveryMode fallback) {
    if (v is bool) {
      return v ? FamilyDeliveryMode.notify : FamilyDeliveryMode.off;
    }
    switch ((v ?? '').toString().trim().toLowerCase()) {
      case 'off':
      case 'false':
      case '0':
        return FamilyDeliveryMode.off;
      case 'record':
      case 'recordonly':
      case 'record_only':
      case 'silent':
        return FamilyDeliveryMode.recordOnly;
      case 'notify':
      case 'true':
      case '1':
        return FamilyDeliveryMode.notify;
      default:
        return fallback;
    }
  }
}

/// 规则族标识（与设置页、ruleId 映射一致）
enum AlertFamilyId {
  priceTiers,
  fund,
  spikePullback,
  gapMorningTail,
  turnoverVolume,
  patternTrend,
  chip,
  kdj15,
  kdj5,
}

extension AlertFamilyIdX on AlertFamilyId {
  String get labelZh {
    switch (this) {
      case AlertFamilyId.priceTiers:
        return '价档';
      case AlertFamilyId.fund:
        return '资金';
      case AlertFamilyId.spikePullback:
        return '急变·回落';
      case AlertFamilyId.gapMorningTail:
        return '跳空·早盘·尾盘';
      case AlertFamilyId.turnoverVolume:
        return '换手·成交';
      case AlertFamilyId.patternTrend:
        return '形态·趋势';
      case AlertFamilyId.chip:
        return '筹码 DDX';
      case AlertFamilyId.kdj15:
        return 'KDJ15';
      case AlertFamilyId.kdj5:
        return 'KDJ5';
    }
  }
}

/// 由 ruleId 推断所属族（监控侧决定是否推送）
AlertFamilyId familyOfRuleId(String ruleId) {
  final id = ruleId;
  if (id.startsWith('price_tier_')) return AlertFamilyId.priceTiers;
  if (id.startsWith('main_ratio')) return AlertFamilyId.turnoverVolume;
  if (id.startsWith('main_') || id.startsWith('retail_')) {
    return AlertFamilyId.fund;
  }
  if (id.startsWith('chip_') || id.startsWith('ddz_')) {
    return AlertFamilyId.chip;
  }
  if (id.startsWith('spike_') || id.startsWith('pullback_')) {
    return AlertFamilyId.spikePullback;
  }
  if (id.startsWith('gap_') ||
      id.startsWith('morning_') ||
      id.startsWith('tail_')) {
    return AlertFamilyId.gapMorningTail;
  }
  if (id.startsWith('turnover_') ||
      id.startsWith('huge_') ||
      id.startsWith('vol_')) {
    return AlertFamilyId.turnoverVolume;
  }
  if (id.startsWith('kdj_5_')) return AlertFamilyId.kdj5;
  if (id.startsWith('ob_') || id.startsWith('os_')) return AlertFamilyId.kdj15;
  if (id.startsWith('kdj_15_') || id.startsWith('kdj_')) {
    return AlertFamilyId.kdj15;
  }
  // day_high/low、integer、vwap、形态、趋势伪KDJ 等
  return AlertFamilyId.patternTrend;
}

/// 规则族投递三态（持久化 JSON；旧版 bool 兼容）
class RuleFamilyFlags {
  FamilyDeliveryMode priceTiers;
  FamilyDeliveryMode fund;
  FamilyDeliveryMode spikePullback;
  FamilyDeliveryMode gapMorningTail;
  FamilyDeliveryMode turnoverVolume;
  FamilyDeliveryMode patternTrend;
  FamilyDeliveryMode chip;
  FamilyDeliveryMode kdj15;
  FamilyDeliveryMode kdj5;

  RuleFamilyFlags({
    this.priceTiers = FamilyDeliveryMode.notify,
    this.fund = FamilyDeliveryMode.notify,
    this.spikePullback = FamilyDeliveryMode.notify,
    this.gapMorningTail = FamilyDeliveryMode.notify,
    this.turnoverVolume = FamilyDeliveryMode.notify,
    this.patternTrend = FamilyDeliveryMode.notify,
    this.chip = FamilyDeliveryMode.notify,
    this.kdj15 = FamilyDeliveryMode.notify,
    FamilyDeliveryMode? kdj5,
  }) : kdj5 = kdj5 ??
            (kEnableKdj5Alerts
                ? FamilyDeliveryMode.notify
                : FamilyDeliveryMode.off);

  factory RuleFamilyFlags.defaults() => RuleFamilyFlags();

  FamilyDeliveryMode modeOf(AlertFamilyId id) {
    switch (id) {
      case AlertFamilyId.priceTiers:
        return priceTiers;
      case AlertFamilyId.fund:
        return fund;
      case AlertFamilyId.spikePullback:
        return spikePullback;
      case AlertFamilyId.gapMorningTail:
        return gapMorningTail;
      case AlertFamilyId.turnoverVolume:
        return turnoverVolume;
      case AlertFamilyId.patternTrend:
        return patternTrend;
      case AlertFamilyId.chip:
        return chip;
      case AlertFamilyId.kdj15:
        return kdj15;
      case AlertFamilyId.kdj5:
        return kdj5;
    }
  }

  void setMode(AlertFamilyId id, FamilyDeliveryMode m) {
    switch (id) {
      case AlertFamilyId.priceTiers:
        priceTiers = m;
        break;
      case AlertFamilyId.fund:
        fund = m;
        break;
      case AlertFamilyId.spikePullback:
        spikePullback = m;
        break;
      case AlertFamilyId.gapMorningTail:
        gapMorningTail = m;
        break;
      case AlertFamilyId.turnoverVolume:
        turnoverVolume = m;
        break;
      case AlertFamilyId.patternTrend:
        patternTrend = m;
        break;
      case AlertFamilyId.chip:
        chip = m;
        break;
      case AlertFamilyId.kdj15:
        kdj15 = m;
        break;
      case AlertFamilyId.kdj5:
        kdj5 = m;
        break;
    }
  }

  /// B：安静模式 — 原「通知」降为「仅记录」；已关的保持关
  void applyQuietPreset() {
    void soft(FamilyDeliveryMode Function() get, void Function(FamilyDeliveryMode) set) {
      if (get() == FamilyDeliveryMode.notify) set(FamilyDeliveryMode.recordOnly);
    }

    soft(() => priceTiers, (m) => priceTiers = m);
    soft(() => fund, (m) => fund = m);
    soft(() => spikePullback, (m) => spikePullback = m);
    soft(() => gapMorningTail, (m) => gapMorningTail = m);
    soft(() => turnoverVolume, (m) => turnoverVolume = m);
    soft(() => patternTrend, (m) => patternTrend = m);
    soft(() => chip, (m) => chip = m);
    soft(() => kdj15, (m) => kdj15 = m);
    soft(() => kdj5, (m) => kdj5 = m);
  }

  /// B：恢复投递默认（通知为主，KDJ5 关）
  void resetDeliveryDefaults() {
    final d = RuleFamilyFlags.defaults();
    priceTiers = d.priceTiers;
    fund = d.fund;
    spikePullback = d.spikePullback;
    gapMorningTail = d.gapMorningTail;
    turnoverVolume = d.turnoverVolume;
    patternTrend = d.patternTrend;
    chip = d.chip;
    kdj15 = d.kdj15;
    kdj5 = d.kdj5;
  }

  Map<String, dynamic> toJson() => {
        'priceTiers': priceTiers.id,
        'fund': fund.id,
        'spikePullback': spikePullback.id,
        'gapMorningTail': gapMorningTail.id,
        'turnoverVolume': turnoverVolume.id,
        'patternTrend': patternTrend.id,
        'chip': chip.id,
        'kdj15': kdj15.id,
        'kdj5': kdj5.id,
      };

  factory RuleFamilyFlags.fromJson(Map<String, dynamic>? j) {
    if (j == null) return RuleFamilyFlags.defaults();
    FamilyDeliveryMode m(String k, FamilyDeliveryMode d) =>
        FamilyDeliveryModeX.parse(j[k], d);
    final def = RuleFamilyFlags.defaults();
    return RuleFamilyFlags(
      priceTiers: m('priceTiers', def.priceTiers),
      fund: m('fund', def.fund),
      spikePullback: m('spikePullback', def.spikePullback),
      gapMorningTail: m('gapMorningTail', def.gapMorningTail),
      turnoverVolume: m('turnoverVolume', def.turnoverVolume),
      patternTrend: m('patternTrend', def.patternTrend),
      chip: m('chip', def.chip),
      kdj15: m('kdj15', def.kdj15),
      kdj5: m('kdj5', def.kdj5),
    );
  }
}

/// 骨 + 肉；与 PC 同单位（%、万元、亿元）。
class AlertTuning {
  List<double> priceTiersPct;
  /// ≤0 表示按档 25/35/45；>0 则三档共用该冷却分钟
  int priceTierCooldownMin;
  double mainCrossMinWan;
  double retailCrossMinWan;
  RuleFamilyFlags families;

  // —— 肉 ——
  double gapThresholdPct;
  double spikePricePct;
  double pullbackPct;
  double pullbackLegMinPct;
  double hugeAmountYi;
  double turnoverHighPct;
  double turnoverMorningHighPct;
  int morningEndHour;
  int morningEndMinute;
  double morningPct;
  int tailStartHour;
  double tailDumpPct;
  double tailPumpPct;

  AlertTuning({
    List<double>? priceTiersPct,
    this.priceTierCooldownMin = 0,
    this.mainCrossMinWan = kMainCrossMinWan,
    this.retailCrossMinWan = kRetailCrossMinWan,
    RuleFamilyFlags? families,
    this.gapThresholdPct = kGapThresholdPct,
    this.spikePricePct = kSpikePricePct,
    this.pullbackPct = kPullbackPct,
    this.pullbackLegMinPct = kPullbackLegMinPct,
    this.hugeAmountYi = kTurnoverHugeYi,
    this.turnoverHighPct = kTurnoverHighPctMain,
    this.turnoverMorningHighPct = kTurnoverMorningHighPct,
    this.morningEndHour = kMorningWindowEndHour,
    this.morningEndMinute = kMorningWindowEndMinute,
    this.morningPct = kMorningPct,
    this.tailStartHour = kTailStartHour,
    this.tailDumpPct = kTailDumpPct,
    this.tailPumpPct = kTailPumpPct,
  })  : priceTiersPct = List<double>.from(
          priceTiersPct ?? kDefaultPriceTiersPct,
        ),
        families = families ?? RuleFamilyFlags.defaults();

  factory AlertTuning.defaults() => AlertTuning();

  double get mainCrossMinYuan => mainCrossMinWan * 10000.0;
  double get retailCrossMinYuan => retailCrossMinWan * 10000.0;

  int cooldownMinutesForTier(double tier) {
    if (priceTierCooldownMin > 0) return priceTierCooldownMin;
    if (tier <= 3) return 25;
    if (tier <= 5) return 35;
    return 45;
  }

  void resetToDefaults() {
    final d = AlertTuning.defaults();
    priceTiersPct = List<double>.from(d.priceTiersPct);
    priceTierCooldownMin = d.priceTierCooldownMin;
    mainCrossMinWan = d.mainCrossMinWan;
    retailCrossMinWan = d.retailCrossMinWan;
    families = RuleFamilyFlags.defaults();
    gapThresholdPct = d.gapThresholdPct;
    spikePricePct = d.spikePricePct;
    pullbackPct = d.pullbackPct;
    pullbackLegMinPct = d.pullbackLegMinPct;
    hugeAmountYi = d.hugeAmountYi;
    turnoverHighPct = d.turnoverHighPct;
    turnoverMorningHighPct = d.turnoverMorningHighPct;
    morningEndHour = d.morningEndHour;
    morningEndMinute = d.morningEndMinute;
    morningPct = d.morningPct;
    tailStartHour = d.tailStartHour;
    tailDumpPct = d.tailDumpPct;
    tailPumpPct = d.tailPumpPct;
  }

  Map<String, dynamic> toJson() => {
        'priceTiersPct': priceTiersPct,
        'priceTierCooldownMin': priceTierCooldownMin,
        'mainCrossMinWan': mainCrossMinWan,
        'retailCrossMinWan': retailCrossMinWan,
        'families': families.toJson(),
        'gapThresholdPct': gapThresholdPct,
        'spikePricePct': spikePricePct,
        'pullbackPct': pullbackPct,
        'pullbackLegMinPct': pullbackLegMinPct,
        'hugeAmountYi': hugeAmountYi,
        'turnoverHighPct': turnoverHighPct,
        'turnoverMorningHighPct': turnoverMorningHighPct,
        'morningEndHour': morningEndHour,
        'morningEndMinute': morningEndMinute,
        'morningPct': morningPct,
        'tailStartHour': tailStartHour,
        'tailDumpPct': tailDumpPct,
        'tailPumpPct': tailPumpPct,
      };

  factory AlertTuning.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AlertTuning.defaults();
    double f(String k, double d) {
      final v = j[k];
      if (v is num) return v.toDouble();
      return d;
    }

    int i(String k, int d) {
      final v = j[k];
      if (v is num) return v.toInt();
      return d;
    }

    List<double> tiers = kDefaultPriceTiersPct;
    final raw = j['priceTiersPct'];
    if (raw is List && raw.isNotEmpty) {
      tiers = raw.map((e) => (e as num).toDouble()).toList();
    }
    return AlertTuning(
      priceTiersPct: tiers,
      priceTierCooldownMin: i('priceTierCooldownMin', 0),
      mainCrossMinWan: f('mainCrossMinWan', kMainCrossMinWan),
      retailCrossMinWan: f('retailCrossMinWan', kRetailCrossMinWan),
      families: RuleFamilyFlags.fromJson(
        j['families'] is Map
            ? Map<String, dynamic>.from(j['families'] as Map)
            : null,
      ),
      gapThresholdPct: f('gapThresholdPct', kGapThresholdPct),
      spikePricePct: f('spikePricePct', kSpikePricePct),
      pullbackPct: f('pullbackPct', kPullbackPct),
      pullbackLegMinPct: f('pullbackLegMinPct', kPullbackLegMinPct),
      hugeAmountYi: f('hugeAmountYi', kTurnoverHugeYi),
      turnoverHighPct: f('turnoverHighPct', kTurnoverHighPctMain),
      turnoverMorningHighPct:
          f('turnoverMorningHighPct', kTurnoverMorningHighPct),
      morningEndHour: i('morningEndHour', kMorningWindowEndHour),
      morningEndMinute: i('morningEndMinute', kMorningWindowEndMinute),
      morningPct: f('morningPct', kMorningPct),
      tailStartHour: i('tailStartHour', kTailStartHour),
      tailDumpPct: f('tailDumpPct', kTailDumpPct),
      tailPumpPct: f('tailPumpPct', kTailPumpPct),
    );
  }
}
