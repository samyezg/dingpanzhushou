import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../data/models.dart';
import 'alert_tuning_section.dart';
import 'app_theme.dart';
import 'help_page.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onChanged;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _keyCtrl;
  late TextEditingController _intervalCtrl;
  late TextEditingController _quotaCtrl;
  late AppSettings _s;
  bool _keyVisible = false;
  late final FocusNode _intervalFocus;
  /// 会话内：当前「偏短」连续段是否已提示过（改回安全后再偏短可再报）
  bool _shortIntervalWarnedThisStreak = false;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _keyCtrl = TextEditingController(text: _s.mxApiKey);
    _quotaCtrl = TextEditingController(text: '${_s.dailyApiQuota}');
    // 默认显示额度估算值（不再以空框表示自动）
    final est = _s.effectivePollIntervalSec();
    _intervalCtrl = TextEditingController(text: est.toStringAsFixed(0));
    _intervalFocus = FocusNode();
    _intervalFocus.addListener(_onIntervalFocusChange);
    if (_s.pollIntervalSec == null) {
      _s.pollIntervalSec = est;
      _intervalCtrl.text = est.toStringAsFixed(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    } else if (_looksLikeLegacyQuotaEstimate(_s.pollIntervalSec!)) {
      // 旧公式（满额均分≈86）自动升到 PC 对齐估算，避免一直卡在旧值
      _refreshIntervalFromQuotaEstimate();
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    } else {
      _intervalCtrl.text = _s.pollIntervalSec!.toStringAsFixed(0);
    }
  }

  /// 旧 APP 公式：sessionSec / (quota/n)，无 safety、无 k=2
  bool _looksLikeLegacyQuotaEstimate(double stored) {
    final n = _s.symbols.isEmpty ? 1 : _s.symbols.length;
    final quota =
        _s.dailyApiQuota <= 0 ? kDefaultDailyApiQuota : _s.dailyApiQuota;
    final legacy = (4 * 3600.0) / (quota / n);
    return (stored - legacy).abs() < 1.5;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _s = widget.settings;
      // 盯盘页改股票数后可能已重算间隔，同步显示
      final est = _s.effectivePollIntervalSec();
      final shown = _intervalCtrl.text.trim();
      if (shown != est.toStringAsFixed(0) &&
          (_s.pollIntervalSec == null ||
              (_s.pollIntervalSec! - est).abs() < 0.51)) {
        _intervalCtrl.text = est.toStringAsFixed(0);
      } else if (_s.pollIntervalSec != null) {
        final want = _s.pollIntervalSec!.toStringAsFixed(0);
        if (shown != want) {
          _intervalCtrl.text = want;
        }
      }
      final q = '${_s.dailyApiQuota}';
      if (_quotaCtrl.text != q) {
        _quotaCtrl.text = q;
      }
    }
  }

  @override
  void dispose() {
    _intervalFocus.removeListener(_onIntervalFocusChange);
    _intervalFocus.dispose();
    _keyCtrl.dispose();
    _intervalCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  void _onIntervalFocusChange() {
    if (!_intervalFocus.hasFocus) {
      _maybeWarnShortInterval();
    }
  }

  bool _isIntervalTooShort(double n) {
    final def = _s.defaultPollIntervalSec();
    return n > 0 && n < def * 0.5;
  }

  /// C：失焦/完成编辑时判定；A：同一偏短段仅首报，改回安全后再偏短可再报
  void _maybeWarnShortInterval() {
    final n = double.tryParse(_intervalCtrl.text.trim());
    if (n == null || n <= 0) return;
    if (!_isIntervalTooShort(n)) {
      _shortIntervalWarnedThisStreak = false;
      return;
    }
    if (_shortIntervalWarnedThisStreak || !mounted) return;
    _shortIntervalWarnedThisStreak = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('间隔偏短，可能导致行情接口限流（不拦截）'),
      ),
    );
  }

  void _applyIntervalInput(String v) {
    if (v.trim().isEmpty) {
      final est = _s.defaultPollIntervalSec();
      _s.pollIntervalSec = est;
      _intervalCtrl.text = est.toStringAsFixed(0);
      _shortIntervalWarnedThisStreak = false;
      _emit();
      return;
    }
    final n = double.tryParse(v);
    if (n != null && n > 0) {
      if (!_isIntervalTooShort(n)) {
        _shortIntervalWarnedThisStreak = false;
      }
      _s.pollIntervalSec = n;
      _emit();
    }
  }

  void _emit() => widget.onChanged(_s);

  /// 额度变化后，用新估算刷新间隔显示并写回设置
  void _refreshIntervalFromQuotaEstimate() {
    final est = _s.defaultPollIntervalSec();
    _s.pollIntervalSec = est;
    _intervalCtrl.text = est.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    // 点空白离开填写框（设置页长表单）
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView(
        // 底 padding：列表末项「使用帮助」避开底 Tab / 偶发 SnackBar
        padding: const EdgeInsets.fromLTRB(kPagePadH, 12, kPagePadH, 96),
        children: [
          FieldWithCollapsibleHelp(
            label: '行情接口密钥',
            shortHint:
                '修改后自动保存 · 长度 ${_s.mxApiKey.trim().length} · 点眼睛可核对明文',
            detail:
                '请填写自备的东方财富 Skills 密钥（行情接口用）。'
                '若含「=」（如 apikey=×××），只保留等号后面的字符串。',
            field: TextField(
              controller: _keyCtrl,
              obscureText: !_keyVisible,
              decoration: InputDecoration(
                hintText: '粘贴密钥，不要带等号前缀',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _keyVisible ? '隐藏密钥' : '显示密钥',
                  icon: Icon(
                    _keyVisible ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _keyVisible = !_keyVisible),
                ),
              ),
              onChanged: (v) {
                var cleaned = v.replaceAll(RegExp(r'[\r\n\t]'), '').trim();
                final pref = RegExp(
                  r'^(?:apikey|api_key|key)\s*=\s*(.+)$',
                  caseSensitive: false,
                ).firstMatch(cleaned);
                if (pref != null) {
                  cleaned = pref.group(1)!.trim();
                }
                if (cleaned != v) {
                  _keyCtrl.value = TextEditingValue(
                    text: cleaned,
                    selection: TextSelection.collapsed(offset: cleaned.length),
                  );
                }
                _s.mxApiKey = cleaned;
                _emit();
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 8),
          FieldWithCollapsibleHelp(
            label: '每日额度',
            shortHint: '默认 500；股票在「盯盘」页管理',
            detail:
                '每个交易日最多请求行情的次数。股票越多，建议轮询间隔越长。',
            field: TextField(
              controller: _quotaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) {
                  setState(() {
                    _s.dailyApiQuota = n;
                    _refreshIntervalFromQuotaEstimate();
                  });
                  _emit();
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          FieldWithCollapsibleHelp(
            label: '轮询间隔（秒）',
            shortHint:
                '建议约 ${_s.defaultPollIntervalSec().toStringAsFixed(0)} 秒（按额度与股票数）',
            detail:
                '改额度或（在盯盘页）改股票数会刷新建议值。'
                '过短可能触发接口限流（失焦时提示，不拦截）。',
            field: TextField(
              controller: _intervalCtrl,
              focusNode: _intervalFocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              onChanged: _applyIntervalInput,
              onEditingComplete: () {
                _maybeWarnShortInterval();
                _intervalFocus.unfocus();
              },
            ),
          ),
          const SizedBox(height: 8),
          AlertTuningSection(
            settings: _s,
            onChanged: () {
              setState(() {});
              _emit();
            },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用帮助'),
            subtitle: const Text('上手、默认、规则、选填、电源与后台、关于与免责'),
            trailing: const Icon(Icons.chevron_right),
            leading: const Icon(Icons.help_outline),
            onTap: () {
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HelpPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
