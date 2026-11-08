/// 从 claw/query 响应提取中文指标与 f 码（对齐 eastmoney_skills.extract_labeled_metrics）
library;

class MetricsBundle {
  final Map<String, double> floats;
  final Map<String, dynamic> raw;
  final List<String> warns;

  MetricsBundle({
    required this.floats,
    required this.raw,
    required this.warns,
  });

  double? operator [](String key) => floats[key];

  double? f(String code) => floats[code.toLowerCase()];
}

double? _toFloat(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  var s = v.toString().trim();
  if (s.isEmpty || s == '--' || s == '-') return null;
  s = s.replaceAll(',', '').replaceAll('%', '');
  // 万/亿 → 元（粗略）
  double mul = 1;
  if (s.contains('亿')) {
    mul = 1e8;
    s = s.replaceAll('亿', '');
  } else if (s.contains('万')) {
    mul = 1e4;
    s = s.replaceAll('万', '');
  } else if (s.endsWith('元')) {
    s = s.substring(0, s.length - 1);
  }
  final n = double.tryParse(s);
  return n == null ? null : n * mul;
}

String? _headToYmd(dynamic head) {
  if (head == null) return null;
  final digits = head.toString().replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8) return digits.substring(0, 8);
  return null;
}

/// 列键 → f2 / f3…；支持裸 f2 与 ZXJ_f2_3。
String? normalizeMetricFCode(dynamic codeKey) {
  final ck = '$codeKey'.trim().toLowerCase();
  if (ck.isEmpty) return null;
  if (ck.startsWith('f') && int.tryParse(ck.substring(1)) != null) {
    return ck;
  }
  final m = RegExp(r'(?:^|_)f(\d+)(?:_|$)').firstMatch(ck);
  if (m != null) return 'f${m.group(1)}';
  return null;
}

int _dtoTablePriority(Map dto, String tradeDate) {
  final table = dto['table'];
  final headsDyn = table is Map ? table['headName'] : null;
  final heads = headsDyn is List ? List<dynamic>.from(headsDyn) : <dynamic>[];
  final title =
      '${dto['title'] ?? dto['tableName'] ?? dto['name'] ?? ''}';
  var score = 0;
  if (title.contains('当前')) score += 100;
  if (title.contains('今日')) score += 40;
  var bestHead = 0;
  for (final h in heads) {
    final hs = h.toString().trim();
    final ymd = _headToYmd(hs);
    if (ymd == null) continue;
    if (ymd == tradeDate) {
      var hscore = 80;
      if (hs.contains(' ') || hs.contains(':')) {
        hscore += 40;
      } else if (hs.contains('(日)') || hs.contains('日)')) {
        hscore += 10;
      }
      if (hscore > bestHead) bestHead = hscore;
    } else if (ymd.compareTo(tradeDate) < 0) {
      if (5 > bestHead) bestHead = 5;
    } else {
      if (15 > bestHead) bestHead = 15;
    }
  }
  return score + bestHead;
}

int _pickColumnIndex(List<dynamic> heads, String tradeDate) {
  if (heads.isEmpty) return 0;
  if (heads.length == 1) return 0;
  final parsed = <(int, String)>[];
  for (var i = 0; i < heads.length; i++) {
    final d = _headToYmd(heads[i]);
    if (d != null) parsed.add((i, d));
  }
  if (parsed.isEmpty) return heads.length - 1;
  for (final p in parsed) {
    if (p.$2 == tradeDate) return p.$1;
  }
  final eligible = parsed.where((p) => p.$2.compareTo(tradeDate) <= 0).toList();
  if (eligible.isNotEmpty) {
    eligible.sort((a, b) => a.$2.compareTo(b.$2));
    return eligible.last.$1;
  }
  parsed.sort((a, b) => a.$2.compareTo(b.$2));
  return parsed.first.$1;
}

dynamic _pickCell(dynamic rawVals, List<dynamic> heads, String tradeDate) {
  if (rawVals is List && rawVals.isNotEmpty) {
    if (heads.length > 1) {
      final idx = _pickColumnIndex(heads, tradeDate);
      if (idx >= 0 && idx < rawVals.length) return rawVals[idx];
      return rawVals.last;
    }
    return rawVals.first;
  }
  return rawVals;
}

/// MX 业务鉴权失败（如 status=114 密钥不存在/失效）。此类请求不应计入本地日额度。
bool isMxAuthFailure(Map<String, dynamic> result) {
  final st = result['status'];
  if (st == 114 || st == '114') return true;
  final msg = '${result['message'] ?? ''}';
  if (msg.contains('密钥') &&
      (msg.contains('不存在') ||
          msg.contains('失效') ||
          msg.contains('无效') ||
          msg.contains('过期'))) {
    return true;
  }
  return false;
}

String mxStatusBrief(Map<String, dynamic> result) {
  final st = result['status'];
  final msg = result['message'];
  if (st == null && msg == null) return '未知鉴权错误';
  return 'API status=$st msg=$msg';
}

MetricsBundle extractLabeledMetrics(Map<String, dynamic> result) {
  final floats = <String, double>{};
  final raw = <String, dynamic>{};
  final warns = <String>[];
  final labelPrio = <String, int>{};
  final fcodePrio = <String, int>{};

  final st = result['status'];
  if (st != null && st != 0) {
    warns.add('API status=$st msg=${result['message']}');
  }

  final data = result['data'];
  if (data is! Map) {
    return MetricsBundle(floats: floats, raw: raw, warns: [...warns, '响应缺少 data']);
  }
  final inner = data['data'];
  if (inner is! Map) {
    return MetricsBundle(
        floats: floats, raw: raw, warns: [...warns, '响应缺少 data.data']);
  }
  final sr = inner['searchDataResultDTO'];
  if (sr is! Map) {
    return MetricsBundle(
        floats: floats,
        raw: raw,
        warns: [...warns, '响应缺少 searchDataResultDTO']);
  }
  final lst = sr['dataTableDTOList'];
  if (lst is! List) {
    return MetricsBundle(
        floats: floats, raw: raw, warns: [...warns, 'dataTableDTOList 非列表']);
  }
  final now = DateTime.now();
  final tradeDate =
      '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  var multi = false;
  var skippedLower = false;

  for (final dto in lst) {
    if (dto is! Map) continue;
    final table = dto['table'];
    if (table is! Map) continue;
    final prio = _dtoTablePriority(Map<String, dynamic>.from(dto), tradeDate);
    var nameMap = dto['nameMap'];
    if (nameMap is List) {
      final list = List<dynamic>.from(nameMap);
      nameMap = <String, dynamic>{
        for (var i = 0; i < list.length; i++) '$i': list[i],
      };
    }
    if (nameMap is! Map) nameMap = <String, dynamic>{};

    final headsDyn = table['headName'];
    final heads = headsDyn is List ? List<dynamic>.from(headsDyn) : <dynamic>[];

    table.forEach((codeKey, rawVals) {
      if (codeKey == 'headName') return;
      var label = nameMap[codeKey];
      if (label == null && int.tryParse('$codeKey') != null) {
        label = nameMap[int.parse('$codeKey')];
      }
      final labelS = (label == null || '$label'.isEmpty) ? '$codeKey' : '$label';

      if (rawVals is List && rawVals.isNotEmpty && heads.length > 1) {
        multi = true;
      }
      final pick = _pickCell(rawVals, heads, tradeDate);
      final num = _toFloat(pick);
      final fCode = normalizeMetricFCode(codeKey);

      final prevLp = labelPrio[labelS];
      if (prevLp == null || prio >= prevLp) {
        raw[labelS] = pick;
        if (num != null) floats[labelS] = num;
        labelPrio[labelS] = prio;
      } else {
        skippedLower = true;
      }

      if (fCode != null && num != null) {
        final prevFp = fcodePrio[fCode];
        if (prevFp == null || prio >= prevFp) {
          floats[fCode] = num;
          fcodePrio[fCode] = prio;
        } else {
          skippedLower = true;
        }
      }
    });
  }

  if (lst.isEmpty) warns.add('dataTableDTOList 为空');
  if (multi) {
    warns.add('多期表已按交易日 $tradeDate 对齐取列');
  }
  if (skippedLower && lst.length > 1) {
    warns.add('多表同名指标已按表优先级合并（优先「当前」/当日盘中，避免昨表覆盖）');
  }
  return MetricsBundle(floats: floats, raw: raw, warns: warns);
}

/// 常用字段别名解析
double? metricLatest(MetricsBundle m) =>
    m['最新价'] ?? m['今日最新价'] ?? m.f('f2');
double? metricOpen(MetricsBundle m) => m['开盘价'] ?? m.f('f17');
double? metricPrevClose(MetricsBundle m) =>
    m['昨收价'] ?? m['昨收'] ?? m.f('f18') ?? m.f('f60');
double? metricPct(MetricsBundle m) => m['涨跌幅'] ?? m.f('f3');
double? metricMainNet(MetricsBundle m) => m['主力净流入'] ?? m.f('f62');
double? metricRetailNet(MetricsBundle m) => m['小单净流入'] ?? m.f('f66');
double? metricTurnoverRate(MetricsBundle m) => m['换手率'] ?? m.f('f8');
double? metricDdx(MetricsBundle m) => m['当日DDX'] ?? m['DDX'];
double? metricDdy(MetricsBundle m) => m['当日DDY'] ?? m['DDY'];
double? metricDdz(MetricsBundle m) => m['当日DDZ'] ?? m['DDZ'];
double? metricAmount(MetricsBundle m) => m['成交额'] ?? m.f('f6');
double? metricVolume(MetricsBundle m) => m['成交量'] ?? m.f('f5');

/// 均价 / VWAP 近似（有则用）
double? metricAvgPrice(MetricsBundle m) =>
    m['均价'] ?? m['平均价'] ?? m['当日均价'] ?? m.f('f21');

/// 主力净额占成交额比例（%）；无市值分档时的降级「大单占比」
double? metricMainRatioPct(
  MetricsBundle m, {
  double? amount,
  double? main,
}) {
  final a = amount ?? metricAmount(m);
  final f = main ?? metricMainNet(m);
  if (a == null || f == null || a.abs() < 1e-6) return null;
  return f.abs() / a.abs() * 100.0;
}
