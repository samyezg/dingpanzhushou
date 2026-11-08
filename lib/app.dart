import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../core/disclaimer.dart';
import '../core/signature_guard.dart';
import '../core/trading_session.dart';
import '../data/alert_history_store.dart';
import '../data/cooldown_store.dart';
import '../data/models.dart';
import '../data/settings_store.dart';
import '../data/stock_basic_repo.dart';
import '../mx/mx_client.dart';
import '../services/foreground_keep_alive.dart';
import '../services/monitor_service.dart';
import '../services/notification_service.dart';
import 'ui/alerts_page.dart';
import 'ui/app_theme.dart';
import 'ui/settings_page.dart';
import 'ui/watchlist_section.dart';

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  late final SettingsStore _settingsStore;
  late final CooldownStore _cooldowns;
  late final AlertHistoryStore _history;
  late final StockBasicRepo _basic;
  late final NotificationService _notifications;
  late final MonitorService _monitor;

  AppSettings _settings = AppSettings();
  String _status = '初始化…';
  List<AlertRecord> _alerts = [];
  bool _ready = false;
  bool _signatureBlocked = false;
  String? _signatureBlockMessage;
  int _tab = 0;
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ForegroundKeepAlive.addTaskDataCallback(_onTaskData);
    ForegroundKeepAlive.onStopRequested = _onFgsStopRequested;
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ForegroundKeepAlive.removeTaskDataCallback(_onTaskData);
    ForegroundKeepAlive.onStopRequested = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // 角标「待恢复」随 setState 刷新；不再弹 SnackBar（§二十四）
      setState(() {});
    }
  }

  void _onTaskData(Object data) {
    ForegroundKeepAlive.handleTaskData(data);
  }

  Future<void> _onFgsStopRequested() async {
    if (!_ready) return;
    await _toggleMonitor(false);
  }

  Future<void> _bootstrap() async {
    final sig = await SignatureGuard.verify();
    if (!sig.ok && !sig.skipped) {
      if (mounted) {
        setState(() {
          _ready = true;
          _signatureBlocked = true;
          _signatureBlockMessage = sig.message;
        });
      }
      return;
    }

    _settingsStore = SettingsStore();
    _cooldowns = CooldownStore();
    _history = AlertHistoryStore();
    _basic = StockBasicRepo();
    _notifications = NotificationService();
    await _settingsStore.init();
    await _cooldowns.init();
    await _history.init();
    await _basic.load();
    await _notifications.init();
    await ForegroundKeepAlive.ensureInitialized();
    await _cooldowns.purgeOtherDays();
    _settings = await _settingsStore.load();
    _alerts = await _history.load();
    _monitor = MonitorService(
      mx: MxClient(),
      cooldowns: _cooldowns,
      history: _history,
      notifications: _notifications,
    );
    _monitor.onStatus = (m) {
      if (mounted) setState(() => _status = m);
    };
    _monitor.onAuthFailed = (detail) async {
      _settings.monitoringEnabled = false;
      await _persist();
      if (mounted) setState(() {});
    };
    _monitor.onAlerts = (list) async {
      final all = await _history.load();
      if (mounted) setState(() => _alerts = all);
    };
    _monitor.onFgsStarted = () {
      if (!_settings.backgroundGuideSeen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_showBackgroundGuide());
        });
      }
    };
    setState(() {
      _ready = true;
      _status = TradingSession.statusMessage(DateTime.now());
    });
    // §7.25 / §二十四：杀进程后不静默自启；角标显示「待恢复」，由用户点按恢复
  }

  Future<void> _persist() async {
    await _settingsStore.save(_settings);
  }

  MonitorChipState get _chipState {
    if (_monitor.isRunning) return MonitorChipState.running;
    if (_settings.monitoringEnabled) return MonitorChipState.pendingResume;
    return MonitorChipState.stopped;
  }

  Future<void> _onChipPressed() async {
    if (_monitor.isRunning) {
      await _toggleMonitor(false);
    } else {
      await _toggleMonitor(true);
    }
  }

  Future<void> _toggleMonitor(bool on) async {
    if (on) {
      _settings.monitoringEnabled = true;
      await _persist();
      await _monitor.start(_settings);
      // 启动未真正跑起来（空密钥/无股票等）：不留「待恢复」假态
      if (!_monitor.isRunning) {
        _settings.monitoringEnabled = false;
        await _persist();
      }
    } else {
      _settings.monitoringEnabled = false;
      await _persist();
      await _monitor.stop();
    }
    if (mounted) setState(() {});
  }

  Future<void> _showBackgroundGuide() async {
    if (!mounted || _settings.backgroundGuideSeen) return;
    if (!Platform.isAndroid) {
      _settings.backgroundGuideSeen = true;
      await _persist();
      return;
    }
    final navCtx = _navKey.currentContext;
    if (navCtx == null) return;
    final action = await showDialog<String>(
      context: navCtx,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('后台运行说明'),
        content: const Text(
          '锁屏/切到后台时，需允许「盯盘助手」后台运行与通知，'
          '并建议关闭电池优化（华为等还需在启动管理中允许自启动/关联启动）。'
          '详情与按钮见设置 →「使用帮助」→「8. 电源与后台」。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'skip'),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'settings'),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    _settings.backgroundGuideSeen = true;
    await _persist();
    if (action == 'settings') {
      final tip = await ForegroundKeepAlive.openBatteryOptimizationSettings();
      if (tip != null && mounted) {
        _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(tip)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (_signatureBlocked) {
      return MaterialApp(
        title: kAppDisplayName,
        theme: buildAppTheme(),
        home: Builder(
          builder: (ctx) {
            return Scaffold(
              appBar: AppBar(title: const Text(kAppDisplayName)),
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.security, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      '安全检查未通过',
                      style: Theme.of(ctx).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _signatureBlockMessage ??
                          '安装包签名异常，请从官方渠道重新安装。',
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => SystemNavigator.pop(),
                      child: const Text('退出'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    if (!_settings.disclaimerAccepted) {
      return MaterialApp(
        title: kAppDisplayName,
        home: _DisclaimerGate(
          onAccept: () async {
            _settings.disclaimerAccepted = true;
            await _persist();
            setState(() {});
          },
        ),
      );
    }
    return MaterialApp(
      title: kAppDisplayName,
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,
      theme: buildAppTheme(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text(kAppDisplayName),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: RunningStatusChip(
                  state: _chipState,
                  onPressed: _onChipPressed,
                ),
              ),
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            _HomePane(
              status: _status,
              settings: _settings,
              basic: _basic,
              monitorRunning: _monitor.isRunning,
              onSettingsChanged: (s) async {
                setState(() => _settings = s);
                await _persist();
                if (_monitor.isRunning) {
                  await _monitor.start(_settings);
                }
              },
              onOpenSettings: () => setState(() => _tab = 2),
            ),
            AlertsPage(alerts: _alerts),
            SettingsPage(
              settings: _settings,
              onChanged: (s) async {
                setState(() => _settings = s);
                await _persist();
                if (_monitor.isRunning) {
                  await _monitor.start(_settings);
                }
              },
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.monitor_heart), label: '盯盘'),
            NavigationDestination(icon: Icon(Icons.notifications), label: '告警'),
            NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    );
  }
}

class _HomePane extends StatelessWidget {
  final String status;
  final AppSettings settings;
  final StockBasicRepo basic;
  final bool monitorRunning;
  final ValueChanged<AppSettings> onSettingsChanged;
  final VoidCallback onOpenSettings;

  const _HomePane({
    required this.status,
    required this.settings,
    required this.basic,
    required this.monitorRunning,
    required this.onSettingsChanged,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final session = TradingSession.statusMessage(DateTime.now());
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(kPagePadH, 12, kPagePadH, 16),
        children: [
          Text(
            '时段：$session',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '状态：$status',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: status.contains('密钥无效')
                      ? Colors.red.shade700
                      : Colors.black87,
                  fontWeight:
                      status.contains('密钥无效') ? FontWeight.w600 : null,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '启停：点右上角「运行中 / 已停止 / 待恢复」',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black45,
                ),
          ),
          const SizedBox(height: 14),
          WatchlistSection(
            settings: settings,
            basic: basic,
            monitorRunning: monitorRunning,
            onChanged: onSettingsChanged,
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '间隔约 ${settings.effectivePollIntervalSec().toStringAsFixed(0)} 秒 · '
              '日额度 ${settings.dailyApiQuota}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            subtitle: Text(
              '在设置中修改密钥、额度与间隔',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                  ),
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: onOpenSettings,
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              '后台与电源',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Android：交易时段前台服务保活；盘外停 FGS；杀进程后不静默自启，'
                  '回 App 后右上角显示「待恢复」，点按即可继续。'
                  'iOS：回前台/系统唤醒后恢复（可降频）。'
                  '详情见设置 → 使用帮助 →「8. 电源与后台」。',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DisclaimerGate extends StatelessWidget {
  final VoidCallback onAccept;

  const _DisclaimerGate({required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(kDisclaimerTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(kDisclaimerBody),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onAccept,
              child: const Text('同意并继续'),
            ),
          ],
        ),
      ),
    );
  }
}
