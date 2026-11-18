import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show HapticFeedback;

bool enableFeedback = Pref.feedBackEnable;

/// 上次触发震动的时间戳（毫秒）
///
/// 有些点击链路里 feedBack() 会被连着调两次（卡片 + 内部按钮、
/// 或 Material ripple 与手势识别叠加），user 反馈「点开视频出现两声震动」。
/// 这里做 120ms 节流：同一瞬间的重复调用只震一次。
int _lastFeedbackAt = 0;

void feedBack() {
  if (!enableFeedback) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (now - _lastFeedbackAt < 120) return;
  _lastFeedbackAt = now;
  HapticFeedback.lightImpact();
}
