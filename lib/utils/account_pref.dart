import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage.dart';

/// 按登录账号隔离的「个人习惯」偏好存储。
///
/// 播放体验记忆：默认倍速 / 默认画质 / 字幕偏好 / 音频输出等按账号记忆，
/// 切换账号后自动使用该账号的偏好，未登录账号用 `anon` 命名空间，
/// 每项都支持回退到全局默认值（读取方自行兜底）。
///
/// 存储落在 GStorage.video 箱里，键名前缀 `acc:<mid>:`，
/// 不影响原有全局设置，也不进设置导入导出。
abstract final class AccountPrefs {
  static String get _ns {
    final mid = Accounts.main.mid;
    return mid <= 0 ? 'anon' : 'acc:$mid';
  }

  static String keyOf(String key) => '$_ns:$key';

  /// 读取当前账号的偏好值；未设置返回 null
  static T? get<T>(String key) {
    final value = GStorage.video.get(keyOf(key));
    return value is T ? value : null;
  }

  static Future<void> put(String key, Object? value) =>
      GStorage.video.put(keyOf(key), value);
}
