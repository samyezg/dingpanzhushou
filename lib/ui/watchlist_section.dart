import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/stock_batch_input.dart';
import '../data/models.dart';
import '../data/stock_basic_repo.dart';
import '../data/symbol_profile.dart';

/// 盯盘页自选管理：添加 / 列表 / 选填 / 删除（设置页不再保留股票区）。
class WatchlistSection extends StatefulWidget {
  final AppSettings settings;
  final StockBasicRepo basic;
  final ValueChanged<AppSettings> onChanged;
  final bool monitorRunning;

  const WatchlistSection({
    super.key,
    required this.settings,
    required this.basic,
    required this.onChanged,
    this.monitorRunning = false,
  });

  @override
  State<WatchlistSection> createState() => _WatchlistSectionState();
}

class _WatchlistSectionState extends State<WatchlistSection> {
  late TextEditingController _addCtrl;
  late AppSettings _s;
  bool _multiLineInput = false;
  bool _showInputHelp = false;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _addCtrl = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant WatchlistSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _s = widget.settings;
    }
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_s);

  void _refreshIntervalFromQuotaEstimate() {
    final est = _s.defaultPollIntervalSec();
    _s.pollIntervalSec = est;
  }

  Future<void> _addStocks() async {
    final raw = _addCtrl.text;
    if (raw.trim().isEmpty) return;

    var segments = splitStockInputSegments(raw);
    if (segments.isEmpty) return;

    var truncated = false;
    if (segments.length > kMaxStockBatchSegments) {
      segments = segments.sublist(0, kMaxStockBatchSegments);
      truncated = true;
    }

    final next = List<WatchSymbol>.from(_s.symbols);
    final added = <String>[];
    final skipped = <String>[];
    final failed = <String>[];

    for (final seg in segments) {
      final r = widget.basic.resolve(seg);
      if (r.err != null || r.tsCode == null) {
        failed.add('$seg（${r.err ?? '无法解析'}）');
        continue;
      }
      if (next.any((e) => e.tsCode == r.tsCode)) {
        skipped.add(seg);
        continue;
      }
      next.add(
        WatchSymbol(
          tsCode: r.tsCode!,
          displayName: r.name ?? r.tsCode!,
        ),
      );
      added.add(r.name ?? r.tsCode!);
    }

    if (added.isEmpty && failed.isEmpty && skipped.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所选股票均已在列表中')),
      );
      return;
    }
    if (added.isEmpty && failed.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed.length == 1
                ? '未添加：${failed.first}'
                : '未添加 ${failed.length} 只：${failed.take(3).join('；')}',
          ),
        ),
      );
      return;
    }

    if (next.length > kDefaultSymbolCount && !_s.warnedGt3Symbols) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('股票超过 3 只'),
          content: const Text(
            '大于 3 只时，交易日后段可能导致行情接口限流。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      _s.warnedGt3Symbols = true;
    }

    setState(() {
      _s.symbols = next;
      _addCtrl.clear();
      _refreshIntervalFromQuotaEstimate();
    });
    _emit();

    if (!mounted) return;
    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add('已添加 ${added.length} 只');
    }
    if (skipped.isNotEmpty) {
      parts.add('跳过重复 ${skipped.length} 只');
    }
    if (failed.isNotEmpty) {
      parts.add('失败 ${failed.length} 只');
    }
    if (truncated) {
      parts.add('仅处理前 $kMaxStockBatchSegments 段');
    }
    if (widget.monitorRunning && added.isNotEmpty) {
      parts.add('轮询将按新列表继续');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.join(' · '))),
    );
  }

  String _symbolSubtitle(WatchSymbol s) {
    final parts = <String>[s.tsCode, s.board.labelZh];
    if (s.effectiveTier != CircMvTier.unknown) {
      final explicit = s.marketCapTier != null &&
          s.marketCapTier != CircMvTier.unknown;
      parts.add(
        explicit
            ? s.effectiveTier.labelZh
            : '${s.effectiveTier.labelZh}·推断',
      );
      if (s.circMvYi != null) {
        parts.add('${s.circMvYi!.toStringAsFixed(s.circMvYi! >= 10 ? 0 : 1)}亿');
      }
    }
    if (s.hasAvgVol5d) {
      parts.add('均量${s.avgVol5dLots!.toStringAsFixed(0)}手');
    }
    return parts.join(' · ');
  }

  bool _isFullRule(WatchSymbol s) => s.hasCircMvProfile || s.hasAvgVol5d;

  List<Widget> _ruleChips(WatchSymbol s, ThemeData theme) {
    final chips = <Widget>[
      Chip(
        label: Text(_isFullRule(s) ? '完整规则' : '简化规则'),
        backgroundColor: _isFullRule(s)
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        labelStyle: theme.textTheme.labelSmall,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      ),
    ];
    if (!s.hasCircMvProfile) {
      chips.add(
        Chip(
          label: const Text('未填市值'),
          labelStyle: theme.textTheme.labelSmall,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
      );
    }
    if (!s.hasAvgVol5d) {
      chips.add(
        Chip(
          label: const Text('未填均量'),
          labelStyle: theme.textTheme.labelSmall,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
      );
    }
    return chips;
  }

  String _circMvHelper(String yiText) {
    final yi = double.tryParse(yiText.trim());
    final inferred = tierFromCircMvYi(yi);
    if (inferred == CircMvTier.unknown) {
      return '填亿元后可自动判定市值档（仅显示，不写入显式档）';
    }
    return '按亿元推断：${inferred.labelZh}'
        '（≥500大/≥100中/≥20小；仅显示）';
  }

  String _tierHelper(CircMvTier? tier) {
    const map = '对应：大≥500 / 中≥100 / 小≥20（亿）；<20 为微盘';
    if (tier == null) {
      return '$map。未设时按上方流通市值自动分档；选定后以本档为准';
    }
    return '$map。已选手动档「${tier.labelZh}」，不再跟亿元；'
        '选「未设」则改回按亿元';
  }

  Future<void> _editSymbolProfile(WatchSymbol s) async {
    final yiCtrl = TextEditingController(
      text: s.circMvYi == null ? '' : s.circMvYi!.toString(),
    );
    final avgCtrl = TextEditingController(
      text: s.avgVol5dLots == null ? '' : s.avgVol5dLots!.toString(),
    );
    CircMvTier? tier = s.marketCapTier;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.displayName),
                const SizedBox(height: 4),
                Text(
                  '${s.tsCode} · 选填，用于完整告警规则',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '板块 · ${s.board.labelZh}',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '由代码推断，一般不用改',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '不填市值、均量 → 简化规则\n'
                            '填了 → 完整告警规则\n'
                            '昨收由行情接口提供，无需填写',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: yiCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '流通市值（亿元，选填）',
                      border: const OutlineInputBorder(),
                      helperText: _circMvHelper(yiCtrl.text),
                      helperMaxLines: 3,
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CircMvTier?>(
                    value: tier,
                    decoration: InputDecoration(
                      labelText: '市值档（选填）',
                      border: const OutlineInputBorder(),
                      helperText: _tierHelper(tier),
                      helperMaxLines: 4,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('未设（跟亿元推断）'),
                      ),
                      DropdownMenuItem(
                        value: CircMvTier.large,
                        child: Text('大盘'),
                      ),
                      DropdownMenuItem(
                        value: CircMvTier.medium,
                        child: Text('中盘'),
                      ),
                      DropdownMenuItem(
                        value: CircMvTier.small,
                        child: Text('小盘'),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => tier = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: avgCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '近5日均量（手，选填）',
                      border: OutlineInputBorder(),
                      helperText: '1万股 = 100 手',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );

    final yiText = yiCtrl.text.trim();
    final avgText = avgCtrl.text.trim();
    yiCtrl.dispose();
    avgCtrl.dispose();
    if (ok != true || !mounted) return;

    double? yi;
    if (yiText.isNotEmpty) {
      yi = double.tryParse(yiText);
      if (yi == null || yi <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('流通市值请填正数（亿元）')),
        );
        return;
      }
    }
    double? avg;
    if (avgText.isNotEmpty) {
      avg = double.tryParse(avgText);
      if (avg == null || avg <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('近5日均量请填正数（手）')),
        );
        return;
      }
    }

    setState(() {
      _s.symbols = _s.symbols
          .map(
            (e) => e.tsCode == s.tsCode
                ? e.copyWith(
                    circMvYi: yi,
                    marketCapTier: tier,
                    avgVol5dLots: avg,
                    clearCircMvYi: yi == null,
                    clearMarketCapTier: tier == null,
                    clearAvgVol5dLots: avg == null,
                  )
                : e,
          )
          .toList();
    });
    _emit();
  }

  void _removeSymbol(WatchSymbol s) {
    setState(() {
      _s.symbols = _s.symbols.where((e) => e.tsCode != s.tsCode).toList();
      _refreshIntervalFromQuotaEstimate();
    });
    _emit();
    if (!mounted) return;
    final parts = <String>['已删除 ${s.displayName}'];
    if (widget.monitorRunning) {
      parts.add('轮询将按新列表继续');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.join(' · '))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '股票（${_s.symbols.length}）',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _addCtrl,
                minLines: 1,
                maxLines: _multiLineInput ? 4 : 1,
                keyboardType: _multiLineInput
                    ? TextInputType.multiline
                    : TextInputType.text,
                textInputAction: _multiLineInput
                    ? TextInputAction.newline
                    : TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: '名称、6位代码或 代码.SH/SZ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _addStocks,
              child: const Text('添加'),
            ),
          ],
        ),
        Row(
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _multiLineInput = !_multiLineInput),
              child: Text(_multiLineInput ? '单行输入' : '多只输入'),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => _showInputHelp = !_showInputHelp),
              child: Text(_showInputHelp ? '收起说明' : '输入说明'),
            ),
          ],
        ),
        if (_showInputHelp) ...[
          Text(
            kStockInputHelperText,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            '点股票可补充市值、均量（选填）。不填用简化规则；填了用完整告警规则。',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
        if (_s.symbols.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '添加名称或 6 位代码后点添加。建议先 3 只。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.black54,
              ),
            ),
          )
        else
          ..._s.symbols.map(
            (s) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.show_chart,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  s.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _symbolSubtitle(s),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: _ruleChips(s, theme),
                    ),
                  ],
                ),
                isThreeLine: true,
                onTap: () => _editSymbolProfile(s),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeSymbol(s),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
