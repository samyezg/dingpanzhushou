import 'package:flutter/material.dart';

import '../data/alert_tuning.dart';
import '../data/models.dart';

/// 二期告警调参区块（专家区未做）；族投递三态 A+B
class AlertTuningSection extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onChanged;

  const AlertTuningSection({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<AlertTuningSection> createState() => _AlertTuningSectionState();
}

class _AlertTuningSectionState extends State<AlertTuningSection> {
  late TextEditingController _tiers;
  late TextEditingController _tierCd;
  late TextEditingController _mainWan;
  late TextEditingController _retailWan;
  late TextEditingController _gap;
  late TextEditingController _spike;
  late TextEditingController _pb;
  late TextEditingController _pbLeg;
  late TextEditingController _huge;
  late TextEditingController _turnHigh;
  late TextEditingController _turnMorning;
  late TextEditingController _morningPct;
  late TextEditingController _morningHm;
  late TextEditingController _tailHour;
  late TextEditingController _tailDump;
  late TextEditingController _tailPump;

  AlertTuning get t => widget.settings.alertTuning;

  @override
  void initState() {
    super.initState();
    _syncControllersFromModel();
  }

  void _syncControllersFromModel() {
    _tiers = TextEditingController(
      text: t.priceTiersPct.map((e) => e.toStringAsFixed(0)).join(','),
    );
    _tierCd = TextEditingController(
      text: t.priceTierCooldownMin > 0 ? '${t.priceTierCooldownMin}' : '',
    );
    _mainWan = TextEditingController(text: t.mainCrossMinWan.toStringAsFixed(0));
    _retailWan =
        TextEditingController(text: t.retailCrossMinWan.toStringAsFixed(0));
    _gap = TextEditingController(text: t.gapThresholdPct.toStringAsFixed(1));
    _spike = TextEditingController(text: t.spikePricePct.toStringAsFixed(2));
    _pb = TextEditingController(text: t.pullbackPct.toStringAsFixed(2));
    _pbLeg = TextEditingController(text: t.pullbackLegMinPct.toStringAsFixed(1));
    _huge = TextEditingController(text: t.hugeAmountYi.toStringAsFixed(0));
    _turnHigh =
        TextEditingController(text: t.turnoverHighPct.toStringAsFixed(0));
    _turnMorning = TextEditingController(
      text: t.turnoverMorningHighPct.toStringAsFixed(0),
    );
    _morningPct = TextEditingController(text: t.morningPct.toStringAsFixed(1));
    _morningHm = TextEditingController(
      text:
          '${t.morningEndHour.toString().padLeft(2, '0')}:${t.morningEndMinute.toString().padLeft(2, '0')}',
    );
    _tailHour = TextEditingController(text: '${t.tailStartHour}');
    _tailDump = TextEditingController(text: t.tailDumpPct.toStringAsFixed(1));
    _tailPump = TextEditingController(text: t.tailPumpPct.toStringAsFixed(1));
  }

  @override
  void dispose() {
    for (final c in [
      _tiers,
      _tierCd,
      _mainWan,
      _retailWan,
      _gap,
      _spike,
      _pb,
      _pbLeg,
      _huge,
      _turnHigh,
      _turnMorning,
      _morningPct,
      _morningHm,
      _tailHour,
      _tailDump,
      _tailPump,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged();

  Widget _numField(
    String label,
    TextEditingController c,
    void Function(double) apply, {
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onEditingComplete: () => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) {
          final n = double.tryParse(v.trim());
          if (n != null && n > 0) {
            apply(n);
            _emit();
          }
        },
      ),
    );
  }

  Widget _familyModeTile(String title, AlertFamilyId id, {String? subtitle}) {
    final f = t.families;
    final mode = f.modeOf(id);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: DropdownButton<FamilyDeliveryMode>(
        value: mode,
        underline: const SizedBox.shrink(),
        items: FamilyDeliveryMode.values
            .map(
              (m) => DropdownMenuItem(
                value: m,
                child: Text(m.labelZh),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => f.setMode(id, v));
          _emit();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          title: const Text('告警灵敏度'),
          subtitle: const Text('价档、资金门槛与分组投递'),
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          children: [
            Text(
              '分组投递：关＝不算；仅记录＝告警页有、不推送；通知＝记录＋系统提醒。'
              '仅记录不减少接口调用。',
              style: small,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tiers,
              textInputAction: TextInputAction.done,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: '价档 %',
                helperText: '逗号分隔，如 3,5,8',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              onChanged: (v) {
                final parts = v
                    .split(RegExp(r'[,，\s]+'))
                    .map((e) => double.tryParse(e.trim()))
                    .whereType<double>()
                    .where((e) => e > 0)
                    .toList();
                if (parts.length >= 2) {
                  parts.sort();
                  t.priceTiersPct = parts;
                  _emit();
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tierCd,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: '价档冷却（分钟）',
                helperText: '留空则按档 25 / 35 / 45 分钟',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              onChanged: (v) {
                if (v.trim().isEmpty) {
                  t.priceTierCooldownMin = 0;
                  _emit();
                  return;
                }
                final n = int.tryParse(v.trim());
                if (n != null && n >= 0) {
                  t.priceTierCooldownMin = n;
                  _emit();
                }
              },
            ),
            const SizedBox(height: 8),
            _numField(
              '主力门槛（万元）',
              _mainWan,
              (n) => t.mainCrossMinWan = n,
              helper: '相关资金类告警的最低金额',
            ),
            _numField(
              '散户门槛（万元）',
              _retailWan,
              (n) => t.retailCrossMinWan = n,
              helper: '相关资金类告警的最低金额',
            ),
            const SizedBox(height: 4),
            Text('规则分组投递', style: Theme.of(context).textTheme.titleSmall),
            _familyModeTile('价档', AlertFamilyId.priceTiers),
            _familyModeTile('资金', AlertFamilyId.fund),
            _familyModeTile('急变·回落', AlertFamilyId.spikePullback),
            _familyModeTile('跳空·早盘·尾盘', AlertFamilyId.gapMorningTail),
            _familyModeTile('换手·成交', AlertFamilyId.turnoverVolume),
            _familyModeTile('形态·趋势', AlertFamilyId.patternTrend),
            _familyModeTile('筹码 DDX', AlertFamilyId.chip),
            _familyModeTile('KDJ15', AlertFamilyId.kdj15),
            _familyModeTile(
              'KDJ5',
              AlertFamilyId.kdj5,
              subtitle: '默认关（易频繁提醒）',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() => t.families.applyQuietPreset());
                    _emit();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已设安静模式：原「通知」改为「仅记录」'),
                      ),
                    );
                  },
                  child: const Text('安静模式'),
                ),
                OutlinedButton(
                  onPressed: () {
                    setState(() => t.families.resetDeliveryDefaults());
                    _emit();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已恢复投递默认（通知为主，KDJ5 关）'),
                      ),
                    );
                  },
                  child: const Text('恢复投递默认'),
                ),
              ],
            ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('常用阈值'),
          subtitle: const Text('跳空 / 急变 / 回落 / 巨额 / 换手 / 早尾盘'),
          childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          children: [
            Text(
              '上方对应分组为「关」时本区仍可改数，但不会触发该族告警。',
              style: small,
            ),
            const SizedBox(height: 8),
            _numField('开盘跳空 %', _gap, (n) => t.gapThresholdPct = n),
            _numField('盘中急变 %', _spike, (n) => t.spikePricePct = n),
            _numField('冲高回撤 %', _pb, (n) => t.pullbackPct = n),
            _numField('最小冲高腿 %', _pbLeg, (n) => t.pullbackLegMinPct = n),
            _numField('巨量成交额（亿）', _huge, (n) => t.hugeAmountYi = n),
            _numField('换手极高 %', _turnHigh, (n) => t.turnoverHighPct = n),
            _numField(
              '早盘高换手 %',
              _turnMorning,
              (n) => t.turnoverMorningHighPct = n,
            ),
            _numField('早盘急变 %', _morningPct, (n) => t.morningPct = n),
            TextField(
              controller: _morningHm,
              textInputAction: TextInputAction.done,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: '早盘窗口结束（HH:MM）',
                border: OutlineInputBorder(),
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              onChanged: (v) {
                final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(v.trim());
                if (m == null) return;
                final h = int.parse(m.group(1)!);
                final mi = int.parse(m.group(2)!);
                if (h > 23 || mi > 59) return;
                t.morningEndHour = h;
                t.morningEndMinute = mi;
                _emit();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tailHour,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onEditingComplete: () => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: '尾盘开始小时（0–23）',
                border: OutlineInputBorder(),
                isDense: true,
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n != null && n >= 0 && n <= 23) {
                  t.tailStartHour = n;
                  _emit();
                }
              },
            ),
            const SizedBox(height: 8),
            _numField('尾盘跳水 %', _tailDump, (n) => t.tailDumpPct = n),
            _numField('尾盘偷袭 %', _tailPump, (n) => t.tailPumpPct = n),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              t.resetToDefaults();
              _tiers.text =
                  t.priceTiersPct.map((e) => e.toStringAsFixed(0)).join(',');
              _tierCd.text = '';
              _mainWan.text = t.mainCrossMinWan.toStringAsFixed(0);
              _retailWan.text = t.retailCrossMinWan.toStringAsFixed(0);
              _gap.text = t.gapThresholdPct.toStringAsFixed(1);
              _spike.text = t.spikePricePct.toStringAsFixed(2);
              _pb.text = t.pullbackPct.toStringAsFixed(2);
              _pbLeg.text = t.pullbackLegMinPct.toStringAsFixed(1);
              _huge.text = t.hugeAmountYi.toStringAsFixed(0);
              _turnHigh.text = t.turnoverHighPct.toStringAsFixed(0);
              _turnMorning.text = t.turnoverMorningHighPct.toStringAsFixed(0);
              _morningPct.text = t.morningPct.toStringAsFixed(1);
              _morningHm.text =
                  '${t.morningEndHour.toString().padLeft(2, '0')}:${t.morningEndMinute.toString().padLeft(2, '0')}';
              _tailHour.text = '${t.tailStartHour}';
              _tailDump.text = t.tailDumpPct.toStringAsFixed(1);
              _tailPump.text = t.tailPumpPct.toStringAsFixed(1);
            });
            _emit();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已恢复告警默认')),
            );
          },
          icon: const Icon(Icons.restart_alt),
          label: const Text('恢复告警默认'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
