import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/constants.dart';

/// 前台服务保活（方案 A · flutter_foreground_task）。
/// 主 isolate 仍跑 [MonitorService]；本类只负责 FGS 常驻通知与进程保活。
class ForegroundKeepAlive {
  ForegroundKeepAlive._();

  static const channelId = 'dingpan_monitor_fgs';
  static const stopButtonId = 'btn_stop_monitor';
  static const serviceId = 256;

  static bool _inited = false;
  static void Function()? onStopRequested;

  static void initCommunicationPort() {
    FlutterForegroundTask.initCommunicationPort();
  }

  static void addTaskDataCallback(void Function(Object) cb) {
    FlutterForegroundTask.addTaskDataCallback(cb);
  }

  static void removeTaskDataCallback(void Function(Object) cb) {
    FlutterForegroundTask.removeTaskDataCallback(cb);
  }

  static void handleTaskData(Object data) {
    if (data is Map && data['event'] == 'stop') {
      onStopRequested?.call();
    }
  }

  static Future<void> ensureInitialized() async {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: channelId,
        channelName: '盯盘运行中',
        channelDescription: '盯盘助手前台服务常驻通知（与告警渠道分离）',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        // 杀进程后不静默自启（§7.25）
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  static Future<void> requestNotificationPermission() async {
    final p = await FlutterForegroundTask.checkNotificationPermission();
    if (p != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  /// 引导忽略电池优化，并**始终**尝试打开系统页（已忽略时不再静默 return）。
  /// 返回可展示的提示文案；非 Android 返回说明。
  static Future<String?> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) {
      return '当前系统无电池优化引导，请见使用帮助。';
    }
    final ignoring =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!ignoring) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    // 列表/详情页：已忽略时也能进系统页，避免「去设置」无反馈
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
    if (ignoring) {
      return '请在系统页确认「盯盘助手」不受电池优化限制；华为请另开启动管理（见使用帮助）。';
    }
    return '请在系统对话框或设置页中允许忽略电池优化。';
  }

  static Future<bool> get isRunning async =>
      FlutterForegroundTask.isRunningService;

  static String notificationText({
    required int symbolCount,
    required double intervalSec,
  }) {
    final sec = intervalSec.round();
    return '盯盘助手运行中 · $symbolCount只 · 约${sec}s';
  }

  static Future<void> start({
    required int symbolCount,
    required double intervalSec,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await ensureInitialized();
    await requestNotificationPermission();
    final text = notificationText(
      symbolCount: symbolCount,
      intervalSec: intervalSec,
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: kAppDisplayName,
        notificationText: text,
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      serviceId: serviceId,
      notificationTitle: kAppDisplayName,
      notificationText: text,
      notificationButtons: [
        const NotificationButton(id: stopButtonId, text: '停止'),
      ],
      callback: foregroundTaskStartCallback,
    );
  }

  static Future<void> update({
    required int symbolCount,
    required double intervalSec,
  }) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: kAppDisplayName,
      notificationText: notificationText(
        symbolCount: symbolCount,
        intervalSec: intervalSec,
      ),
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void foregroundTaskStartCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 心跳即可；业务轮询在主 isolate MonitorService
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == ForegroundKeepAlive.stopButtonId) {
      FlutterForegroundTask.sendDataToMain({'event': 'stop'});
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    // 若系统允许划掉 ongoing，视为停止盯盘
    FlutterForegroundTask.sendDataToMain({'event': 'stop'});
  }
}
