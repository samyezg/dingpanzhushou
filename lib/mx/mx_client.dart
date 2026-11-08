import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';

/// 妙想 claw/query 客户端；对齐 PC `mx_http_session.SessionManager`：
/// 时长 OR 轮数重建 `http.Client`（推荐 A：900s / 8 轮）。
class MxClient {
  http.Client _http;
  final Stopwatch _sinceRebuild = Stopwatch()..start();
  int _roundsSinceRebuild = 0;
  String? lastSessionNote;

  final double ttlSec;
  final int maxRounds;

  MxClient({
    http.Client? httpClient,
    this.ttlSec = kMxHttpSessionTtlSec,
    this.maxRounds = kMxHttpSessionMaxRounds,
  }) : _http = httpClient ?? http.Client();

  void close() => _http.close();

  /// 一整轮监控（全部标的拉取结束）后调用；对齐 PC `after_round()`。
  void afterRound() {
    _roundsSinceRebuild++;
    final age = _sinceRebuild.elapsedMilliseconds / 1000.0;
    final byAge = ttlSec > 0 && age >= ttlSec;
    final byRounds = maxRounds > 0 && _roundsSinceRebuild >= maxRounds;
    if (byAge || byRounds) {
      _rebuild(reason: 'age=${age.toStringAsFixed(0)}s rounds=$_roundsSinceRebuild');
    }
  }

  /// 网络层失败后强制换连接（手机换网/半死连接）。
  void forceRebuild([String reason = 'transport error']) {
    _rebuild(reason: reason);
  }

  void _rebuild({required String reason}) {
    try {
      _http.close();
    } catch (_) {}
    _http = http.Client();
    _sinceRebuild
      ..reset()
      ..start();
    _roundsSinceRebuild = 0;
    lastSessionNote = '[SESSION] 重建 HTTP Client（$reason）';
  }

  bool _isTransportFailure(Object e) {
    if (e is TimeoutException || e is http.ClientException) return true;
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection closed') ||
        s.contains('Connection reset');
  }

  /// POST claw/query，Header: apikey
  Future<Map<String, dynamic>> query({
    required String apiKey,
    required String toolQuery,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw StateError('未配置行情接口密钥');
    }
    try {
      final resp = await _http
          .post(
            Uri.parse(kMxQueryUrl),
            headers: {
              'Content-Type': 'application/json',
              'apikey': key,
            },
            body: jsonEncode({'toolQuery': toolQuery}),
          )
          .timeout(timeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw StateError('MX HTTP ${resp.statusCode}: ${resp.body}');
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('MX 响应非 JSON 对象');
      }
      return decoded;
    } catch (e) {
      if (_isTransportFailure(e)) {
        forceRebuild(e is TimeoutException ? 'timeout' : 'transport: $e');
      }
      rethrow;
    }
  }
}

String buildToolQuery(String displayName, String tsCode, {String style = 'compact'}) {
  final metrics = style == 'legacy'
      ? '最新价、开盘价、昨收价、涨跌幅、成交量、成交额、'
          '主力净流入、小单净流入、换手率、当日DDX、当日DDY、当日DDZ'
      : '今日最新价、开盘价、昨收价、涨跌幅、成交量、成交额、均价、'
          '主力净流入、小单净流入、换手率、当日DDX、当日DDY、当日DDZ';
  final code = tsCode.trim();
  if (code.isEmpty) return '$displayName $metrics';
  final short = code.contains('.') ? code.split('.').first : code;
  return '$displayName($short) $metrics';
}
