/// 自选股画像：板块推断 + 客户选填升格（未填则规则降级）。
library;

/// 流通市值分档（与 PC board_thresholds 同边界，客户填「亿」时换算）
enum CircMvTier {
  large,
  medium,
  small,
  micro,
  unknown,
}

/// 板块（推断用；gem/star 查 DDZ 表时合并为 gem_star）
enum BoardKind {
  mainboard,
  gem,
  star,
  bj,
  bShare,
  unknown,
}

extension CircMvTierX on CircMvTier {
  String get id {
    switch (this) {
      case CircMvTier.large:
        return 'large';
      case CircMvTier.medium:
        return 'medium';
      case CircMvTier.small:
        return 'small';
      case CircMvTier.micro:
        return 'micro';
      case CircMvTier.unknown:
        return 'unknown';
    }
  }

  String get labelZh {
    switch (this) {
      case CircMvTier.large:
        return '大盘';
      case CircMvTier.medium:
        return '中盘';
      case CircMvTier.small:
        return '小盘';
      case CircMvTier.micro:
        return '微盘';
      case CircMvTier.unknown:
        return '未设';
    }
  }

  static CircMvTier? tryParse(String? s) {
    switch ((s ?? '').trim().toLowerCase()) {
      case 'large':
      case '大':
      case '大盘':
        return CircMvTier.large;
      case 'medium':
      case '中':
      case '中盘':
        return CircMvTier.medium;
      case 'small':
      case '小':
      case '小盘':
        return CircMvTier.small;
      case 'micro':
      case '微':
      case '微盘':
        return CircMvTier.micro;
      default:
        return null;
    }
  }
}

extension BoardKindX on BoardKind {
  String get labelZh {
    switch (this) {
      case BoardKind.mainboard:
        return '主板';
      case BoardKind.gem:
        return '创业板';
      case BoardKind.star:
        return '科创板';
      case BoardKind.bj:
        return '北交所';
      case BoardKind.bShare:
        return 'B股';
      case BoardKind.unknown:
        return '未知';
    }
  }

  /// DDZ 矩阵键
  String get ddzBoardKey {
    if (this == BoardKind.gem || this == BoardKind.star) return 'gem_star';
    if (this == BoardKind.bj) return 'bj';
    return 'mainboard';
  }
}

bool _isDigits(String s) {
  if (s.isEmpty) return false;
  for (final u in s.codeUnits) {
    if (u < 48 || u > 57) return false;
  }
  return true;
}

/// 对齐 PC `get_board_type`（301 作创业板，与现网一致）
BoardKind inferBoard(String tsCode) {
  final raw = tsCode.trim().toUpperCase();
  final code = raw.contains('.') ? raw.split('.').first : raw;
  if (code.length < 3 || !_isDigits(code.substring(0, code.length > 6 ? 6 : code.length))) {
    return BoardKind.unknown;
  }
  final c = code.length >= 6 ? code.substring(0, 6) : code.padLeft(6, '0');
  if (c.startsWith('900') && raw.endsWith('.SH')) return BoardKind.bShare;
  if (c.startsWith('200') && raw.endsWith('.SZ')) return BoardKind.bShare;
  if (raw.endsWith('.BJ') ||
      c.startsWith('43') ||
      c.startsWith('82') ||
      c.startsWith('83') ||
      c.startsWith('87') ||
      c.startsWith('88') ||
      c.startsWith('92')) {
    return BoardKind.bj;
  }
  if (c.startsWith('688')) return BoardKind.star;
  if (c.startsWith('300') || c.startsWith('301')) return BoardKind.gem;
  if (c.startsWith('60') || c.startsWith('00')) return BoardKind.mainboard;
  return BoardKind.unknown;
}

/// PC 完整版量异动默认阈（预估全日量/近5日均量）
const double kVolRatioHighFull = 2.5;
const double kVolRatioLowFull = 0.6;

/// 流通市值「亿元」→ 分档（PC 2026-08-05：500 / 100 / 20）
CircMvTier tierFromCircMvYi(double? yi) {
  if (yi == null || yi <= 0 || yi.isNaN) return CircMvTier.unknown;
  if (yi >= 500) return CircMvTier.large;
  if (yi >= 100) return CircMvTier.medium;
  if (yi >= 20) return CircMvTier.small;
  return CircMvTier.micro;
}

/// 大单占比升格阈值（ratio 为小数；minAmountWan 为成交额下限万元）
class ParticipationThresh {
  final double ratio;
  final double absentRatio;
  final double minAmountWan;
  final bool enabled;

  const ParticipationThresh({
    required this.ratio,
    required this.absentRatio,
    required this.minAmountWan,
    this.enabled = true,
  });
}

ParticipationThresh? participationForTier(CircMvTier tier) {
  switch (tier) {
    case CircMvTier.large:
      return const ParticipationThresh(
        ratio: 0.15,
        absentRatio: 0.05,
        minAmountWan: 10000,
      );
    case CircMvTier.medium:
      return const ParticipationThresh(
        ratio: 0.20,
        absentRatio: 0.05,
        minAmountWan: 5000,
      );
    case CircMvTier.small:
      return const ParticipationThresh(
        ratio: 0.30,
        absentRatio: 0.08,
        minAmountWan: 2000,
      );
    case CircMvTier.micro:
      return null; // PC micro enabled=false
    case CircMvTier.unknown:
      return null; // 回退降级粗阈
  }
}

/// PC DDZ_CHIP_THRESHOLDS
double? ddzAbsMin({required BoardKind board, required CircMvTier tier}) {
  if (tier == CircMvTier.unknown || tier == CircMvTier.micro) {
    // micro 用该板 medium（PC 注释）
    if (tier == CircMvTier.micro) {
      tier = CircMvTier.medium;
    } else {
      return null;
    }
  }
  final key = board.ddzBoardKey;
  const table = <String, Map<String, double>>{
    'mainboard': {'large': 15, 'medium': 10, 'small': 6},
    'gem_star': {'large': 12, 'medium': 8, 'small': 5},
    'bj': {'medium': 6, 'small': 4},
  };
  final row = table[key] ?? table['mainboard']!;
  return row[tier.id] ?? row['medium'];
}

/// 连续竞价已交易分钟（粗算，对齐 PC 量能异动）
int continuousAuctionMinutesElapsed(DateTime at) {
  final h = at.hour;
  final m = at.minute;
  final mins = h * 60 + m;
  const amOpen = 9 * 60 + 30;
  const amClose = 11 * 60 + 30;
  const pmOpen = 13 * 60;
  const pmClose = 15 * 60;
  if (mins < amOpen) return 0;
  if (mins <= amClose) return mins - amOpen;
  if (mins < pmOpen) return amClose - amOpen; // 120
  if (mins <= pmClose) return (amClose - amOpen) + (mins - pmOpen);
  return 240;
}

/// 预估全日量（手）：Skills 成交量为股时 ÷100
double? estimateFullDayLots({
  required double? volumeShares,
  required DateTime at,
}) {
  if (volumeShares == null || volumeShares <= 0) return null;
  final elapsed = continuousAuctionMinutesElapsed(at);
  if (elapsed < 60) return null;
  final lots = volumeShares / 100.0;
  return lots * (240.0 / elapsed);
}
