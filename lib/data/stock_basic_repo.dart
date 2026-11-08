import 'package:flutter/services.dart' show rootBundle;

class StockBasicRepo {
  final Map<String, String> _byCode = {};
  final Map<String, List<String>> _byName = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/stock_basic_min.csv');
    final lines = raw.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return;
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = _parseCsvLine(line);
      if (parts.length < 2) continue;
      final tc = parts[0].trim().toUpperCase();
      final name = parts[1].trim();
      if (tc.isEmpty || name.isEmpty) continue;
      _byCode[tc] = name;
      final key = name.toLowerCase();
      _byName.putIfAbsent(key, () => []).add(tc);
    }
    _loaded = true;
  }

  String? nameOf(String tsCode) => _byCode[tsCode.trim().toUpperCase()];

  /// 输入：名称、6 位码、或 600519.SH
  ({String? tsCode, String? name, String? err}) resolve(String input) {
    final s = input.trim();
    if (s.isEmpty) return (tsCode: null, name: null, err: '空输入');
    // 600519.SH / 600519
    final codeLike = RegExp(r'^(\d{6})(\.(SH|SZ|BJ))?$', caseSensitive: false);
    final m = codeLike.firstMatch(s);
    if (m != null) {
      final six = m.group(1)!;
      if (m.group(2) != null) {
        final tc = '${six}.${m.group(3)!.toUpperCase()}';
        return (tsCode: tc, name: _byCode[tc] ?? six, err: null);
      }
      // 无后缀：在表中找唯一匹配
      final hits = _byCode.keys.where((k) => k.startsWith('$six.')).toList();
      if (hits.length == 1) {
        return (tsCode: hits.first, name: _byCode[hits.first], err: null);
      }
      if (hits.isEmpty) {
        return (tsCode: '$six.SH', name: six, err: null); // 兜底沪市，可再改
      }
      return (tsCode: null, name: null, err: '代码 $six 对应多交易所，请写全如 $six.SH');
    }
    final hits = _byName[s.toLowerCase()] ?? [];
    if (hits.length == 1) {
      return (tsCode: hits.first, name: s, err: null);
    }
    if (hits.isEmpty) {
      // 模糊包含
      final fuzzy = <String>[];
      for (final e in _byCode.entries) {
        if (e.value.contains(s)) fuzzy.add(e.key);
      }
      if (fuzzy.length == 1) {
        return (tsCode: fuzzy.first, name: _byCode[fuzzy.first], err: null);
      }
      return (tsCode: null, name: null, err: '未找到：$s');
    }
    return (tsCode: null, name: null, err: '名称重名，请用代码');
  }

  List<String> _parseCsvLine(String line) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQ = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQ = !inQ;
        continue;
      }
      if (c == ',' && !inQ) {
        out.add(sb.toString());
        sb.clear();
        continue;
      }
      sb.write(c);
    }
    out.add(sb.toString());
    return out;
  }
}
