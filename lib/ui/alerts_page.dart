import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/alert_history_store.dart';
import 'app_theme.dart';

class AlertsPage extends StatelessWidget {
  final List<AlertRecord> alerts;

  /// 分享时最多条数（列表通常新→旧）；过大易导致微信等无法直达分享
  static const int kShareMaxAlerts = 100;

  const AlertsPage({super.key, required this.alerts});

  /// 列表右侧上行：`YY-MM-DD`（两位年）。
  static String formatAlertDate(DateTime at) {
    final yy = (at.year % 100).toString().padLeft(2, '0');
    final mm = at.month.toString().padLeft(2, '0');
    final dd = at.day.toString().padLeft(2, '0');
    return '$yy-$mm-$dd';
  }

  /// 列表右侧下行：`HH:mm:ss`。
  static String formatAlertTime(DateTime at) {
    final hh = at.hour.toString().padLeft(2, '0');
    final mi = at.minute.toString().padLeft(2, '0');
    final ss = at.second.toString().padLeft(2, '0');
    return '$hh:$mi:$ss';
  }

  /// 兼容旧测试名
  static String _formatAlertDate(DateTime at) => formatAlertDate(at);
  static String _formatAlertTime(DateTime at) => formatAlertTime(at);

  /// 客户向纯文本（无 JSON）。
  static String formatPlainText(
    List<AlertRecord> list, {
    String? note,
  }) {
    final buf = StringBuffer();
    buf.writeln('盯盘助手 · 告警');
    buf.writeln('条数: ${list.length}');
    if (note != null && note.isNotEmpty) {
      buf.writeln(note);
    }
    buf.writeln('---');
    for (final a in list) {
      buf.writeln('${_formatAlertDate(a.at)} ${_formatAlertTime(a.at)}');
      buf.writeln(
        '${a.title} ${a.tsCode}${a.notified ? '' : ' 【未推送】'}',
      );
      buf.writeln(a.body);
      buf.writeln('---');
    }
    return buf.toString();
  }

  Future<void> _copyAll(BuildContext context) async {
    if (alerts.isEmpty) return;
    final text = formatPlainText(alerts);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${alerts.length} 条告警')),
    );
  }

  Future<void> _shareAll(BuildContext context) async {
    if (alerts.isEmpty) return;
    final truncated = alerts.length > kShareMaxAlerts;
    final slice =
        truncated ? alerts.sublist(0, kShareMaxAlerts) : alerts;
    final text = formatPlainText(
      slice,
      note: truncated
          ? '（仅分享最近 $kShareMaxAlerts 条；全部请用「复制全部」）'
          : null,
    );
    final subject = '盯盘助手告警 · ${slice.length}条';

    try {
      await Share.share(text, subject: subject);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('分享未成功，请用「复制全部」后粘贴到微信等应用'),
        ),
      );
    }
  }

  /// 按日分组：header 用日期串，item 用告警（保序，通常新→旧）
  static List<Object> groupByDate(List<AlertRecord> list) {
    final out = <Object>[];
    String? last;
    for (final a in list) {
      final d = formatAlertDate(a.at);
      if (d != last) {
        out.add(d);
        last = d;
      }
      out.add(a);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const Center(child: Text('暂无告警'));
    }
    final theme = Theme.of(context);
    final rows = groupByDate(alerts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, kPagePadH, 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _copyAll(context),
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('复制全部'),
                ),
                TextButton.icon(
                  onPressed: () => _shareAll(context),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('分享'),
                ),
                const Spacer(),
                Text(
                  '共 ${alerts.length} 条',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (ctx, i) {
              final row = rows[i];
              if (row is String) {
                return Container(
                  width: double.infinity,
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  padding: const EdgeInsets.fromLTRB(
                    kPagePadH,
                    8,
                    kPagePadH,
                    6,
                  ),
                  child: Text(
                    row,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                );
              }
              final a = row as AlertRecord;
              final tone = alertToneColor(a.title);
              final timeStyle = theme.textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              );
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: kPagePadH,
                  vertical: 4,
                ),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: a.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tone ?? theme.colorScheme.onSurface,
                        ),
                      ),
                      TextSpan(
                        text: ' ${a.tsCode}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    a.notified ? a.body : '【未推送】${a.body}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black87,
                      height: 1.25,
                    ),
                  ),
                ),
                leading: Icon(
                  a.notified
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: a.notified
                      ? (tone ?? theme.colorScheme.primary)
                      : Colors.orange.shade800,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatAlertTime(a.at), style: timeStyle),
                  ],
                ),
                isThreeLine: true,
              );
            },
          ),
        ),
      ],
    );
  }
}
