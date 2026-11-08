/// 无仓版脏轮门禁（对齐 PC snapshot_sanity / §44）
library;

import '../mx/metrics_extract.dart';
import 'rule_thresholds.dart';

class SanityResult {
  final bool ok;
  final String? reason;
  const SanityResult.ok() : ok = true, reason = null;
  const SanityResult.reject(this.reason) : ok = false;
}

bool _isPrevCloseLikeName(String name) {
  final ns = name;
  final nsl = ns.toLowerCase();
  if (nsl == 'f60' || nsl == 'f18') return true;
  if (ns.contains('昨收') || ns.contains('前收')) return true;
  if (ns == '前收盘') return true;
  return false;
}

/// metrics 仅有昨收类、无严格现价 → 过稀空表半残（§44 巨石）
bool metricsLooksPrevCloseOnly(MetricsBundle m) {
  if (m.floats.isEmpty) return true;
  if (metricLatest(m) != null) return false;
  var prevLike = 0;
  var other = 0;
  for (final name in m.floats.keys) {
    if (_isPrevCloseLikeName(name)) {
      prevLike++;
    } else {
      other++;
    }
  }
  return prevLike > 0 && other == 0;
}

/// 返回 reject 则本轮不跑规则；调用方仅在 ok 时更新 lastValidF2 / peak。
SanityResult applySnapshotSanity({
  required MetricsBundle metrics,
  required double? sessionOpen,
  required double? lastValidF2,
}) {
  if (metricsLooksPrevCloseOnly(metrics)) {
    return const SanityResult.reject('仅昨收类字段、无严格现价');
  }

  final latest = metricLatest(metrics);
  final open = metricOpen(metrics);
  final pc = metricPrevClose(metrics);
  final pct = metricPct(metrics);

  if (latest == null || latest <= 0) {
    return const SanityResult.reject('最新价缺失或非正');
  }

  // 同包最新相对昨收偏离过大（§44：默认 12%，挡假涨）
  if (pc != null && pc.abs() > 1e-9) {
    final dev = (latest - pc).abs() / pc.abs() * 100.0;
    if (dev > kSanityF60F2MaxDevPct) {
      return SanityResult.reject(
        '最新相对昨收偏离 ${dev.toStringAsFixed(2)}%>${kSanityF60F2MaxDevPct}%',
      );
    }
  }

  // 开盘锚定：sessionOpen 已定后，开盘价不应相对其大幅漂移（串表常见）
  if (sessionOpen != null && open != null && sessionOpen.abs() > 1e-9) {
    final dev = (open - sessionOpen).abs() / sessionOpen.abs() * 100.0;
    if (dev > kSanityOpenAnchorMaxDevPct) {
      return SanityResult.reject(
        '开盘锚定偏离 ${dev.toStringAsFixed(2)}%>${kSanityOpenAnchorMaxDevPct}%',
      );
    }
  }

  // 相邻有效价跳变过大
  if (lastValidF2 != null && lastValidF2 > 0) {
    final jump = (latest - lastValidF2).abs() / lastValidF2 * 100.0;
    if (jump > kSanityJumpMaxPct) {
      return SanityResult.reject(
        '相邻价跳变 ${jump.toStringAsFixed(2)}%>$kSanityJumpMaxPct%',
      );
    }
  }

  // 涨跌幅与价推算不一致（粗）
  if (pct != null && pc != null && pc.abs() > 1e-9) {
    final implied = (latest - pc) / pc * 100.0;
    if ((implied - pct).abs() > kSanityF3DeltaPct) {
      return SanityResult.reject(
        '涨跌幅与价推算不一致 Δ=${(implied - pct).abs().toStringAsFixed(2)}%',
      );
    }
  }

  return const SanityResult.ok();
}
