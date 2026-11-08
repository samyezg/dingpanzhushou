import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../services/foreground_keep_alive.dart';

/// App 内使用帮助（§十五 · 客户向；默认全折叠；表格式默认/通知/规则摘要）
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Future<void> _openBattery(BuildContext context) async {
    final tip = await ForegroundKeepAlive.openBatteryOptimizationSettings();
    if (!context.mounted) return;
    if (tip != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('使用帮助')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '锁屏后不更新、不再告警？请展开下方「8. 电源与后台」。',
              style: tipStyle,
            ),
          ),
          const Divider(height: 1),
          _section(
            title: '1. 这是什么',
            children: [
              _p(
                '盯盘助手在 A 股连续竞价时段，按你设置的轮询间隔拉取行情快照，'
                '当价格、资金、换手等条件满足时，在本机生成告警记录，并可推送系统通知。',
              ),
              _p(
                '本应用不是东方财富官方产品；不荐股、不承诺收益、不提供投资建议。'
                '一期不支持企业微信推送，告警仅保存在本机。',
              ),
              _p(
                '行情数据来自你自行配置的「行情接口密钥」（东方财富 Skills）。'
                '每次轮询会消耗每日额度。请保证网络畅通，并在系统中允许通知。',
              ),
              _p(
                '当前提供 Android 安装包。暂不支持鸿蒙 NEXT 纯血系统；'
                '华为手机请使用安卓兼容环境。iPhone 需另行构建，APK 不能直接安装。',
              ),
            ],
          ),
          _section(
            title: '2. 快速上手',
            children: [
              _p('① 首次打开：阅读免责声明，点击同意并继续。'),
              _p(
                '② 设置 →「行情接口密钥」：粘贴自备密钥。'
                '若内容含 apikey= 或 KEY=，只保留等号后面的字符串；点眼睛可核对明文。',
              ),
              _p('③ 确认「每日额度」（默认 500）与「轮询间隔」（默认按额度与股票数估算，可改）。'),
              _p(
                '④ 回到「盯盘」页添加股票：建议先加 3 只（名称、6 位代码或 代码.SH/SZ）。',
              ),
              _p(
                '⑤（可选）在盯盘页点股票名称，补充流通市值/市值档/近5日均量，以便使用完整告警规则；不填则用简化规则。',
              ),
              _p('⑥ 在连续竞价时段点右上角「已停止」启动盯盘（运行中显示「运行中」），到「告警」页查看记录；需要时允许系统通知权限。'),
              _p(
                '交易时段（一期）：工作日 09:30–11:30、13:00–15:00（不含集合竞价）。'
                '周末与盘外不拉行情。法定节假日日历一期未完整排除，盘中请自行留意。',
              ),
            ],
          ),
          _section(
            title: '3. 默认设置',
            children: [
              _p('出厂默认如下。可在设置中修改；「恢复告警默认」可还原告警相关项。'),
              _h('连接与时段'),
              _table([
                ['项', '默认'],
                ['行情接口密钥', '空（须自备）'],
                ['每日额度', '500 次/交易日'],
                ['轮询间隔', '按额度与股票数估算（可改）'],
                ['交易时段', '工作日 09:30–11:30、13:00–15:00'],
                ['盘外', '不拉行情；常驻保活停止'],
              ]),
              _h('告警灵敏度'),
              _table([
                ['项', '默认'],
                ['价档 %', '3 / 5 / 8'],
                ['价档冷却', '留空＝按档约 25 / 35 / 45 分钟'],
                ['主力门槛', '500 万元'],
                ['散户门槛', '1000 万元'],
              ]),
              _h('常用阈值'),
              _table([
                ['项', '默认'],
                ['开盘跳空 %', '3'],
                ['盘中急变 %', '0.65'],
                ['冲高回撤 %', '0.4'],
                ['最小冲高腿 %', '2'],
                ['巨量成交额（亿）', '100'],
                ['换手极高 %', '15'],
                ['早盘高换手 %', '5'],
                ['早盘急变 %', '3'],
                ['早盘窗口结束', '10:00'],
                ['尾盘开始小时', '14'],
                ['尾盘跳水 %', '2'],
                ['尾盘偷袭 %', '1.5'],
              ]),
            ],
          ),
          _section(
            title: '4. 告警通知设置',
            children: [
              _p(
                '设置 →「告警灵敏度」→「规则分组投递」。每个分组可选三种模式：',
              ),
              _table([
                ['模式', '是否计算规则', '告警页', '系统通知'],
                ['关', '否', '无', '无'],
                ['仅记录', '是', '有（标「未推送」）', '无'],
                ['通知', '是', '有', '有'],
              ]),
              _h('各分组默认'),
              _table([
                ['分组', '默认'],
                ['价档', '通知'],
                ['资金', '通知'],
                ['急变·回落', '通知'],
                ['跳空·早盘·尾盘', '通知'],
                ['换手·成交', '通知'],
                ['形态·趋势', '通知'],
                ['筹码 DDX', '通知'],
                ['KDJ15', '通知'],
                ['KDJ5', '关（易频繁提醒）'],
              ]),
              _p(
                '「安静模式」：把原为「通知」的分组改为「仅记录」；已「关」的保持关。'
                '仅记录仍会请求行情，不节省每日额度。',
              ),
              _p(
                '常驻通知「盯盘助手运行中」用于后台保活，不受上述分组控制。'
                '详见「7. 告警页与系统通知」。',
              ),
            ],
          ),
          _section(
            title: '5. 告警规则一览',
            children: [
              _p(
                '下表为常用逻辑摘要（客户向）。是否弹出系统通知，还取决于第 4 章投递模式、冷却时间，'
                '以及是否填写了市值/均量（简化规则 / 完整告警规则）。',
              ),
              _table([
                ['分组', '告警（例）', '何时可能提醒', '备注'],
                [
                  '价档',
                  '股价异动',
                  '相对开盘或昨收达到所设价档（如 3/5/8%）',
                  '每档每日约一次；受冷却',
                ],
                [
                  '资金',
                  '主力穿零/反转/拐点；散户异动',
                  '主力或散户净额达到门槛等条件',
                  '门槛见第 3 章',
                ],
                [
                  '急变·回落',
                  '盘中急升/急跌；冲高回落；价档回落',
                  '邻轮涨跌达急变%；或自高点回落达阈',
                  '阈值见「常用阈值」',
                ],
                [
                  '跳空·早盘·尾盘',
                  '开盘跳空；早盘急变；尾盘跳水/偷袭',
                  '跳空幅度、早盘窗口内急变、尾盘时段急变',
                  '时刻见默认设置',
                ],
                [
                  '换手·成交',
                  '巨量；成交量异动；大单占比（含首报/午报）；换手；量能首报/午报',
                  '成交额/换手/主力占比等达阈；开盘后额环比粗代理',
                  '填均量·市值→完整规则，否则简化规则；样本不足则跳过量能首报/午报',
                ],
                [
                  '筹码',
                  '筹码异动；DDZ首段/拐点',
                  'DDX/DDY/DDZ 组合吸筹或出逃；DDZ 轨迹首段与峰谷拐头',
                  '有市值档时筹码条件更严',
                ],
                [
                  '形态·趋势',
                  '破平台、横盘突破、趋势反转、动能等',
                  '短窗形态或价格动能变化',
                  '多为简化算法',
                ],
                [
                  '极值·日内',
                  '极值确认/距极值；日内新高/新低',
                  '确认日内高/低后提示；创 session 极值且超上次告警价',
                  '轮询近似；状态按日保留',
                ],
                [
                  'KDJ15 / KDJ5',
                  '金叉 / 死叉；超买 / 超卖 / 解除（伪窗 J·80/20）',
                  '用轮询点近似计算，非官方 K 线',
                  'KDJ5 默认关；超买超卖随 KDJ15',
                ],
              ]),
              _p(
                '另有整数关口、VWAP、开盘突破等，逻辑类似：条件满足且未在冷却中则写入告警页。'
                '脏价快照会静默丢弃本轮、不抬峰。完整研发对照表不在本帮助内展示。',
              ),
            ],
          ),
          _section(
            title: '6. 自选股选填',
            children: [
              _p('在盯盘页点股票名称，可补充下列选填项。均可不填。'),
              _table([
                ['字段', '说明'],
                ['流通市值（亿元）', '填后按 ≥500 大 / ≥100 中 / ≥20 小自动判定并显示「·推断」；不自动写入显式市值档；<20 为微盘'],
                ['市值档', '可选大/中/小；选定后以本档为准；选「未设」则跟亿元推断'],
                ['近5日均量（手）', '1 万股 = 100 手；用于成交量类完整规则'],
                ['板块', '由代码推断，一般不用改'],
                ['昨收', '由行情接口提供，无需填写'],
              ]),
              _h('简化规则与完整告警规则'),
              _table([
                ['情况', '效果'],
                ['不填市值、均量', '简化规则（如用成交额环比代理量能、固定粗阈等）'],
                ['填了相应项', '完整告警规则（更接近完整公式，如全日量/均量、分档大单占比）'],
              ]),
            ],
          ),
          _section(
            title: '7. 告警页与系统通知',
            children: [
              _table([
                ['类型', '作用'],
                ['告警页列表', '历史记录；可复制全部/分享为纯文本（无 JSON、不用文件）；「未推送」表示仅记录、未发系统通知'],
                ['告警系统通知', '条件触发时的提醒；需系统通知权限；受第 4 章「通知」模式控制'],
                ['常驻「运行中」', '交易时段保活用；不是买卖信号；通知上「停止」等于点右上角暂停'],
              ]),
              _p('投递模式（关 / 仅记录 / 通知）的含义见第 4 章，此处不重复。'),
            ],
          ),
          _section(
            title: '8. 电源与后台（安卓 / 华为）',
            children: [
              _p('锁屏后不更新、不再告警，多半是省电或启动限制，而不是规则算错。'),
              _h('通用安卓'),
              _p('1. 允许通知（含告警与「运行中」常驻）。'),
              _p('2. 忽略电池优化：将「盯盘助手」设为不允许优化 / 无限制。'),
              _p('3. 使用下方按钮打开系统电池优化相关页（未忽略时会弹出请求；已忽略也会打开系统页以便确认）。'),
              _p('4. 勿从多任务强行划掉（等于杀进程）。'),
              _p('5. 杀进程后本应用不会静默自启；回到 App 后右上角为「待恢复」，点按即可继续盯盘。'),
              _p('6. 盘外不拉行情，常驻保活会停止。'),
              _h('华为 · 启动管理'),
              _p(
                '设置 → 应用启动管理 → 盯盘助手 → 关闭自动管理，并手动打开：'
                '允许自启动、允许关联启动、允许后台活动。'
                '电池中将耗电设为不限制；交易时段尽量关闭超级省电。',
              ),
              _p('纯血鸿蒙 NEXT 暂不支持。'),
              _h('自检'),
              _p(
                '交易时段点右上角启动并见到「运行中」→ 锁屏 5～10 分钟 → '
                '若每日额度仍增加或能出告警，则大致正常；完全静止则再查电源与启动项。'
                '系统菜单路径可能随版本变化，以实机为准。',
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.battery_saver_outlined),
                title: const Text('打开系统电池优化设置'),
                subtitle: const Text('建议允许「盯盘助手」忽略电池优化'),
                onTap: () => _openBattery(context),
              ),
            ],
          ),
          _section(
            title: '9. 常见问题',
            children: [
              _qa('密钥无效 / 已失效', '行情接口密钥错误或失效。会停止轮询且不扣额度；请核对后重开盯盘。'),
              _qa('状态显示非交易时间', '盘外与周末按设计不拉行情。'),
              _qa('告警页有记录但没有系统通知', '该分组可能是「仅记录」，或系统关闭了通知权限。'),
              _qa('锁屏后完全不跑', '见第 8 章电源与后台（电池优化、启动管理、是否被划掉进程）。'),
              _qa('间隔偏短提示', '轮询过密可能导致接口限流；提示不拦截保存，建议按估算值使用。'),
              _qa('分享到微信后没有自动回到本应用', '属系统常态；请从多任务切回盯盘助手。若曾卡住文件预览，现已改为纯文本分享。'),
              _qa('能否安装到 iPhone', '当前为 Android APK，不能直接装 iPhone。'),
            ],
          ),
          _section(
            title: '10. 关于与免责',
            children: [
              _p(
                '盯盘助手（盯盘助手软件）版本 $kAppVersionLabel。'
                '包名：$kApplicationId',
              ),
              _p(
                '开发者 / 著作权人：$kCopyrightHolder（个人开发者）。'
                '联系邮箱：$kSupportEmail',
              ),
              _privacyLinkRow(),
              _p(
                '非东方财富官方产品，与券商、交易所无隶属关系。'
                '一期无企业微信推送；告警仅在本机展示。'
                '暂不支持鸿蒙 NEXT 纯血系统。'
                '本应用用于条件触发提醒与学习研究，不构成投资建议或荐股。',
              ),
              _p(
                '行情数据依赖用户自行配置的第三方接口密钥，可能存在延迟、缺失或错误。'
                '证券投资有风险，决策由用户独立作出。'
                '完整免责以首次启动时的《免责声明》全文为准。',
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return ExpansionTile(
      initiallyExpanded: false,
      title: Text(title),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  static Widget _p(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(height: 1.45)),
    );
  }

  static Widget _privacyLinkRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('隐私政策：', style: TextStyle(height: 1.45)),
          InkWell(
            onTap: () async {
              final uri = Uri.parse(kPrivacyPolicyUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: const Text(
              kPrivacyPolicyUrl,
              style: TextStyle(
                height: 1.45,
                color: Color(0xFF0B57D0),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _h(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
      ),
    );
  }

  static Widget _qa(String q, String a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Q：$q', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('A：$a', style: const TextStyle(height: 1.4)),
        ],
      ),
    );
  }

  /// 简易两列表格（首行为表头）。列数可变。
  static Widget _table(List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.first.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Table(
        border: TableBorder.all(color: const Color(0xFFDDDDDD), width: 0.6),
        columnWidths: {
          for (var i = 0; i < cols; i++)
            i: i == 0
                ? const FlexColumnWidth(1.1)
                : const FlexColumnWidth(1.4),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: BoxDecoration(
                color: r == 0 ? const Color(0xFFF2F4F7) : null,
              ),
              children: [
                for (final cell in rows[r])
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 7,
                    ),
                    child: Text(
                      cell,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight:
                            r == 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
