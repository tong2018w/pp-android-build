import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data' show Int64List;

import 'package:PiliPlus/grpc/dyn.dart';
import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

/// 本地通知服务：动态更新 & UP 开播提醒
///
/// 说明：这是「本地轮询 + 系统通知」，不是 B站服务端推送。
/// App 运行时按间隔拉取，发现新动态/新开播就发本地通知。
/// App 被系统彻底杀掉后不再工作（第三方客户端拿不到 B站推送凭证）。
class LocalNotifyService {
  LocalNotifyService._();
  static final instance = LocalNotifyService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 通知渠道 id。
  /// v2：加震动支持（渠道参数不可变，必须换新 id）
  static const _channelId = 'piliplus_dyn_live_v2';
  static const _channelName = '动态与开播提醒';

  Timer? _timer;
  bool _inited = false;
  bool _polling = false;

  /// 上次看到的最新动态 id，用于判断「有新动态」。
  ///
  /// 原来用 DynGrpc.dynRed() 的红点计数判断，但第三方客户端拿到的
  /// count 常年不变化（B站对第三方限流），导致文本/图片/视频动态
  /// 全都不触发通知。改为直接拉动态列表，对比第一条的 id_str ——
  /// 只要最新 id 变了就有新动态，覆盖所有类型。
  Object? _lastDynId;

  /// 上次正在直播的 uid → 名字，用于判断「新开播」
  final Map<int, String> _lastLive = {};

  /// 上次的消息未读总数（私信/@/回复/点赞/系统）
  int? _lastMsgCount;

  /// 已经通知过的动态 id / 消息未读数，用于防重。
  /// 动态用最新 id 对比（不是 count），避免计数波动导致反复弹同一条。
  Object? _notifiedDynId;
  int? _notifiedMsgCount;

  /// 动态未读数回调：由 MainController 注册，用它同步底部角标。
  /// 角标仍用 dynRed 语义；通知判断改用最新动态 id（见 _checkDynamic）。
  void Function(int count)? onDynCount;

  /// 是否有通知权限
  bool get _canNotify =>
      Pref.enableMsgNotif || Pref.enableDynNotif || Pref.enableLiveNotif;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    // 创建通知渠道（Android 8+）
    //
    // 渠道参数创建后不可修改，所以加震动必须换新 id，
    // 否则老用户装上新版仍是旧渠道（无震动）。
    final channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: '关注的 UP 发布动态或开播时的本地提醒',
      importance: Importance.high,
      playSound: true,
      // 通知栏消息震动（用户要求：通知时震动，而不是点开视频时震）
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
      enableLights: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 请求通知权限（Android 13+），返回是否授予
  Future<bool> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  /// 根据设置启动/停止轮询
  Future<void> syncPolling() async {
    await init();
    if (!_canNotify) {
      stop();
      return;
    }
    final granted = await requestPermission();
    if (!granted) {
      // Android 13 以下没有运行时通知权限，插件可能返回 null。
      // 这种情况仍应启动轮询（否则低版本永远收不到通知）。
      debugPrint('通知权限未授予或无法判定，仍尝试启动轮询');
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    final seconds = Pref.notifPollInterval.clamp(15, 3600).toInt();
    // 先跑一次建立基线（避免刚开启就把已有的当新的全推一遍）
    _pollOnce(initial: true);
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => _pollOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 回到前台时只同步基线，不发通知。
  ///
  /// 原来这里会 _pollOnce() 真检测，结果后台期间积累的未读在用户
  /// 点开任意页面（App 回前台）时一次性补发一堆通知 —— 用户看到的
  /// 「点开视频冒出一串通知 + 两句震动」就是这个。
  /// 现在改成只把基线刷成当前值，不发提醒：
  /// 通知只由前台 Timer 或后续真实增量触发。
  Future<void> checkNow() async {
    if (!_canNotify) return;
    await _pollOnce(silent: true);
  }

  Future<void> _pollOnce({bool initial = false, bool silent = false}) async {
    if (_polling) return;
    _polling = true;
    try {
      // silent=true：只更新基线，不发任何通知
      if (Pref.enableMsgNotif) await _checkMsg(initial: initial || silent);
      if (Pref.enableDynNotif) {
        await _checkDynamic(initial: initial || silent);
      }
      if (Pref.enableLiveNotif) {
        await _checkLive(initial: initial || silent);
      }
    } catch (e) {
      debugPrint('本地通知轮询错误: $e');
    } finally {
      _polling = false;
    }
  }

  /// 消息未读（私信 / @ / 回复 / 点赞 / 系统）增加时发通知
  ///
  /// 这是「来消息及时通知」的主体 —— 之前只做了动态红点和开播，
  /// 私信/回复/@ 完全没提醒，所以用户觉得「有未读但不提醒」。
  Future<void> _checkMsg({required bool initial}) async {
    var total = 0;
    // 私信
    final single = await MsgHttp.msgUnread();
    if (single case Success(:final response)) {
      total += response.followUnread +
          response.unfollowUnread +
          response.bizMsgFollowUnread +
          response.bizMsgUnfollowUnread +
          response.unfollowPushMsg +
          response.customUnread;
    }
    // @ / 回复 / 点赞 / 系统
    final feed = await MsgHttp.msgFeedUnread();
    if (feed case Success(:final response)) {
      total += response.at + response.reply + response.like + response.sysMsg;
    }

    final prev = _lastMsgCount;
    _lastMsgCount = total;
    if (initial || prev == null) return; // 首次只建基线
    if (total > prev && total != _notifiedMsgCount) {
      _notifiedMsgCount = total;
      await _show(
        id: 1000,
        title: '新消息',
        body: '有 ${total - prev} 条新的未读消息',
        payload: 'msg',
      );
    }
  }

  /// 有新动态时发通知（文本 / 图片 / 视频全覆盖）
  ///
  /// 直接拉动态列表对比最新 id，不再依赖 dynRed 红点计数。
  Future<void> _checkDynamic({required bool initial}) async {
    // 角标仍用 dynRed（它是红点语义），仅同步显示，不用来判断通知
    if (onDynCount != null) {
      final redCount = await DynGrpc.dynRed();
      if (redCount != null) onDynCount?.call(redCount);
    }
    final model = await DynamicsHttp.followDynamic();
    final items = model.dataOrNull?.items;
    if (items == null || items.isEmpty) return;
    final latestId = items.first.idStr;
    if (latestId == null) return;

    final prev = _lastDynId;
    _lastDynId = latestId;
    debugPrint('动态最新 id: $prev -> $latestId (initial=$initial)');
    if (initial || prev == null) return; // 首次只建基线
    if (latestId != prev && latestId != _notifiedDynId) {
      _notifiedDynId = latestId;
      await _show(
        id: 1001,
        title: '动态更新',
        body: '关注的 UP 发布了新动态',
        payload: 'dyn',
      );
    }
  }

  /// 对比直播状态，新开播的 UP 发通知
  Future<void> _checkLive({required bool initial}) async {
    if (_lastLive.isEmpty && initial) {
      // 首次先拉一次建立基线，下面逻辑统一处理
    }
    // 关注的 uid 从账号信息取不到完整列表时，用动态页 liveUsers 的 mid。
    // 这里用 PiliPlus 已有的 followDynamic 拿到的直播列表。
    final live = await _fetchLiveUsers();
    if (live == null) return;

    final current = {for (final e in live.entries) e.key: e.value};
    if (initial) {
      _lastLive
        ..clear()
        ..addAll(current);
      return;
    }
    for (final entry in current.entries) {
      final wasLive = _lastLive.containsKey(entry.key);
      if (!wasLive) {
        await _show(
          id: 2000 + entry.key,
          title: '${entry.value} 开播了',
          body: '快去看直播',
          payload: 'live:${entry.key}',
        );
      }
    }
    _lastLive
      ..clear()
      ..addAll(current);
  }

  /// 拉取正在直播的 UP（mid → uname）
  Future<Map<int, String>?> _fetchLiveUsers() async {
    try {
      // followUp() 返回的 FollowUpModel.liveUsers 就是「正在直播」列表，
      // 是项目现成接口，比自己拉全量关注 uid 再逐个查状态轻得多
      final model = await DynamicsHttp.followUp();
      final live = model.dataOrNull?.liveUsers;
      if (live == null) return null;
      final result = <int, String>{};
      for (final item in live.items ?? const []) {
        result[item.mid] = item.uname ?? 'UP主';
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '关注的 UP 发布动态或开播时的本地提醒',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'PiliPlus 提醒',
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
      playSound: true,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details, payload: payload);
  }

  void _onTap(NotificationResponse response) {
    // 点击通知目前不做跳转：service 层静态依赖 MainController 会形成
    // controller → service → controller 的循环 import，得不偿失。
    // 通知本身已经起到提醒作用，用户点开 App 自己进动态页即可。
    // 后续若要精确跳转，可通过 Get.key 或回调注入实现。
  }
}
