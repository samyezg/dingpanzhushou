import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android release 签名白名单校验（§二十）。
class SignatureGuard {
  static const MethodChannel _ch =
      MethodChannel('com.dingpanzhushou.app/security');

  /// debug / 非 Android：放行。release：白名单不匹配则 [ok]=false。
  static Future<SignatureCheckResult> verify() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const SignatureCheckResult(ok: true, skipped: true);
    }
    try {
      final raw = await _ch.invokeMethod<dynamic>('verifySigning');
      if (raw is! Map) {
        return const SignatureCheckResult(
          ok: false,
          message: '签名校验返回异常',
        );
      }
      final map = Map<String, dynamic>.from(raw);
      final ok = map['ok'] == true;
      final debug = map['debug'] == true;
      final sha = (map['sha256'] ?? '').toString();
      final n = map['allowedCount'];
      return SignatureCheckResult(
        ok: ok,
        debugBuild: debug,
        sha256: sha,
        allowedCount: n is int ? n : int.tryParse('$n') ?? 0,
        message: ok
            ? null
            : '安装包签名与官方白名单不一致，可能被篡改或二次打包。请从官方渠道重新下载。',
      );
    } on PlatformException catch (e) {
      return SignatureCheckResult(
        ok: false,
        message: '签名校验失败：${e.message ?? e.code}',
      );
    } catch (e) {
      return SignatureCheckResult(ok: false, message: '签名校验异常：$e');
    }
  }
}

class SignatureCheckResult {
  final bool ok;
  final bool skipped;
  final bool debugBuild;
  final String sha256;
  final int allowedCount;
  final String? message;

  const SignatureCheckResult({
    required this.ok,
    this.skipped = false,
    this.debugBuild = false,
    this.sha256 = '',
    this.allowedCount = 0,
    this.message,
  });
}
