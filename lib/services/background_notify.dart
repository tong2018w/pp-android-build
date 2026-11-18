import 'dart:io' show Platform;

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/services/local_notify_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account_manager/account_mgr.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

/// WorkManager 后台轮询任务名
const String backgroundPollTask = 'piliplus_bg_poll';
const String _backgroundUniqueName = 'piliplus_bg_poll_periodic';

bool _bgReady = false;

/// 后台任务入口：WorkManager 每 ~15 分钟在后台 isolate 里回调一次。
///
/// 目标：App 退到后台/被划掉后，仍能检测关注动态/开播/未读并发系统通知。
/// 说明：Android WorkManager 的最小周期是 15 分钟，OPPO 等厂商的省电策略
/// 可能进一步延后；这是平台限制，能显著改善「后台完全没通知」但非秒级实时。
@pragma('vm:entry-point')
void notifyCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    if (task != backgroundPollTask) return true;
    try {
      await runBackgroundNotifyOnce();
      return true;
    } catch (e) {
      debugPrint('后台通知任务异常: $e');
      // 返回 true 不重试，避免异常时任务堆积/反复弹出
      return true;
    }
  });
}

/// 在后台 isolate 里初始化存储、网络与账号 Cookie，然后跑一轮检测。
///
/// 关键点：
/// - WorkManager 每次会拉起新的 Dart isolate，内存里的「上次基线」会丢，
///   所以基线必须持久化到 setting box（见 LocalNotifyService 的 _kLast*）；
/// - 手动装配 dio + AccountManager 注入登录 Cookie，避免依赖 webview 插件；
/// - flutter_local_notifications 依赖插件注册，先 ensureInitialized。
Future<void> runBackgroundNotifyOnce() async {
  if (!_bgReady) {
    WidgetsFlutterBinding.ensureInitialized();

    appSupportDirPath = (await getApplicationSupportDirectory()).path;
    await GStorage.init();

    // 构建 dio 并注入账号 Cookie（等价于 Request.setCookie，但不碰 webview）
    Request();
    Request.accountManager = AccountManager();
    Request.dio.interceptors.add(Request.accountManager);
    try {
      await Accounts.refresh().timeout(const Duration(seconds: 20));
    } catch (_) {
      // 刷新 buvid 失败不影响用已有 Cookie 发请求
    }
    _bgReady = true;
  }

  await LocalNotifyService.instance.runBackgroundPoll();
}

/// 应用启动时调用一次，注册后台回调。
Future<void> initBackgroundNotify() async {
  if (!Platform.isAndroid) return;
  await Workmanager().initialize(notifyCallbackDispatcher);
}

/// 根据通知总开关安排/取消后台周期任务（仅 Android）。
Future<void> scheduleBackgroundNotify({required bool enable}) async {
  if (!Platform.isAndroid) return;
  try {
    if (!enable) {
      await Workmanager().cancelByUniqueName(_backgroundUniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _backgroundUniqueName,
      backgroundPollTask,
      // Android 最小周期 15 分钟
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (e) {
    debugPrint('安排后台通知任务失败: $e');
  }
}
