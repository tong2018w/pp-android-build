import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/models/dynamics/result.dart';

/// 「全部动态」页内的二级内容筛选。
///
/// 顶部 Tab 已经做了 全部/投稿/番剧/专栏/UP 的分类，这里在「全部」列表内
/// 再加一层按内容形态快速过滤，让用户不用翻长列表就能定位想看的类型。
enum DynamicsFilter implements EnumWithLabel {
  all('全部'),
  video('视频'),
  draw('图文'),
  article('专栏'),
  live('直播'),
  ;

  @override
  final String label;
  const DynamicsFilter(this.label);

  /// 该动态是否命中此筛选条件
  bool matches(DynamicItemModel item) {
    final type = item.type;
    final additional = item.modules.moduleDynamic?.additional;
    final live =
        item.modules.moduleDynamic?.major?.live != null ||
            item.modules.moduleDynamic?.major?.liveRcmd != null;
    return switch (this) {
      DynamicsFilter.all => true,
      DynamicsFilter.video => matchesVideo(type),
      DynamicsFilter.draw => matchesDraw(type),
      DynamicsFilter.article => type == 'DYNAMIC_TYPE_ARTICLE',
      DynamicsFilter.live => live,
    };
  }
}

bool matchesVideo(String? type) => type == 'DYNAMIC_TYPE_AV' ||
    type == 'DYNAMIC_TYPE_UGC_SEASON' ||
    type == 'DYNAMIC_TYPE_PGC' ||
    type == 'DYNAMIC_TYPE_PGC_UNION' ||
    type == 'DYNAMIC_TYPE_COURSES_SEASON' ||
    type == 'DYNAMIC_TYPE_MEDIALIST';

bool matchesDraw(String? type) =>
    type == 'DYNAMIC_TYPE_DRAW' || type == 'DYNAMIC_TYPE_WORD';
