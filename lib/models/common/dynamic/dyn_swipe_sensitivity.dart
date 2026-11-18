import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 动态页横向滑动的灵敏度
///
/// 数值越小越容易触发滑动切换，越接近官方 bilibili 的跟手感
enum DynSwipeSensitivity implements EnumWithLabel {
  /// 容易触发（横向位移约等于系统 touchSlop 即响应）
  loose('灵敏'),

  /// 默认：沿用全局「横向滑动阈值」
  standard('标准'),

  /// 需要更长的横向位移才触发，减少误触
  strict('稳重'),

  ;
  @override
  final String label;
  const DynSwipeSensitivity(this.label);

  /// 判定横向滑动的角度比：|dx| > |dy| * angleRatio
  ///
  /// 灵敏档原本取 2，斜着滑列表时容易被判成横滑，
  /// 提到 2.5 后既保留跟手，又不会跟竖向滚动打架。
  double get angleRatio => switch (this) {
    .loose => 2.5,
    .standard => 3,
    .strict => 4,
  };

  /// 相对系统 touchSlop 的额外像素
  double get extraSlop => switch (this) {
    .loose => 2,
    .standard => 8,
    .strict => 20,
  };
}
