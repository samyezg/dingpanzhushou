import 'package:flutter/material.dart';

/// §十九 界面精修：统一种子色 / 边距 / 运行态 Chip。
const Color kAppSeedColor = Color(0xFF1B4F72);

/// 页面水平边距（P1）
const double kPagePadH = 16;

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kAppSeedColor);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0.5,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: kPagePadH, vertical: 2),
      dense: true,
      visualDensity: VisualDensity(horizontal: 0, vertical: -1),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// AppBar 盯盘运行态：三态可点（§二十四 · 方案 A）
enum MonitorChipState {
  /// 监控在跑
  running,

  /// 用户未开或启动未成功
  stopped,

  /// 曾要开着，但当前未在跑（如杀进程）；点按恢复
  pendingResume,
}

/// AppBar 运行态徽章（点击启停/恢复；页内不再放「启动盯盘」开关）
class RunningStatusChip extends StatelessWidget {
  final MonitorChipState state;
  final VoidCallback? onPressed;

  const RunningStatusChip({
    super.key,
    required this.state,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;
    switch (state) {
      case MonitorChipState.running:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
        icon = Icons.play_circle_filled;
        label = '运行中';
      case MonitorChipState.pendingResume:
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFE65100);
        icon = Icons.replay_circle_filled;
        label = '待恢复';
      case MonitorChipState.stopped:
        bg = const Color(0xFFEEEEEE);
        fg = const Color(0xFF616161);
        icon = Icons.pause_circle_filled;
        label = '已停止';
    }
    final chip = Chip(
      avatar: Icon(icon, size: 16, color: fg),
      label: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      backgroundColor: bg,
      side: BorderSide.none,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
    if (onPressed == null) return chip;
    return Tooltip(
      message: switch (state) {
        MonitorChipState.running => '点击暂停盯盘',
        MonitorChipState.pendingResume => '点击恢复盯盘',
        MonitorChipState.stopped => '点击启动盯盘',
      },
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: chip,
      ),
    );
  }
}

/// 设置页：短标签 + 可展开说明（P0）
class FieldWithCollapsibleHelp extends StatelessWidget {
  final String label;
  final String shortHint;
  final String detail;
  final Widget field;

  const FieldWithCollapsibleHelp({
    super.key,
    required this.label,
    required this.shortHint,
    required this.detail,
    required this.field,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: titleStyle),
        const SizedBox(height: 6),
        field,
        const SizedBox(height: 2),
        Text(
          shortHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: Text(
              '说明',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 告警标题语气色（升偏暖 / 跌偏冷；非 A 股红绿看板）
Color? alertToneColor(String title) {
  final t = title;
  const down = [
    '急跌',
    '死叉',
    '新低',
    '回落',
    '跳水',
    '出逃',
    '↓',
    '跌破',
    '缺席',
    '走弱',
    '降速',
    '跌势',
  ];
  const up = [
    '急升',
    '金叉',
    '新高',
    '突破',
    '↑',
    '吸筹',
    '偷袭',
    '放量',
    '反转↑',
    '涨速',
    '涨势',
  ];
  for (final k in down) {
    if (t.contains(k)) return const Color(0xFF00695C);
  }
  for (final k in up) {
    if (t.contains(k)) return const Color(0xFFBF360C);
  }
  return null;
}
