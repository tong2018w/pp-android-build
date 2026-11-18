import 'package:PiliPlus/models_new/follow/list.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/parse_int.dart';

class FollowUpModel {
  LiveUsers? liveUsers;
  List<UpItem>? upList;
  bool? hasMore;
  String? offset;

  void addAllUpList(List<UpItem> newList) {
    if (upList != null) {
      upList!.addAll(newList);
    } else {
      upList = newList;
    }
  }

  /// 顶部头像栏 / 横向分页共用的「展示顺序」。
  ///
  /// 顺序：正在直播的 UP → 有未读动态的 UP → 其余关注 UP。
  /// 直播列表(live_users)和动态列表(up_list)里可能有同一个 mid，
  /// 这里按 mid 去重，并优先保留 LiveUserItem（这样头像能带上直播环/LIVE 标）。
  /// 「全部动态」(-1) 和「我」由头像栏/分页单独置顶，不在这里，
  /// 从而保证直播 UP 不会排到「全部动态」前面。
  List<UpItem> get orderedUpList {
    // -1(全部动态) 和 我 由头像栏/分页单独置顶，这里排除，避免重复出现
    final selfMid = Accounts.main.mid;
    final seen = <int>{-1, selfMid};
    final result = <UpItem>[];

    // 直播 mid 集合，用于给同一 UP 合并「直播 + 未读」两个状态
    final liveMap = <int, LiveUserItem>{
      for (final item in liveUsers?.items ?? const <LiveUserItem>[])
        item.mid: item,
    };

    // 1. 有未读动态的 UP 优先
    //    之前把「直播」排在「未读」前面，直播 UP 一多，
    //    未读的普通 UP 全被挤到后面看不见 —— 用户反馈的
    //    「未读动态 up 不在前面显示」就是这个。
    for (final item in upList ?? const <UpItem>[]) {
      if (item.hasUpdate == true && seen.add(item.mid)) {
        // 若这位同时也在直播，用 LiveUserItem 保留直播环 + LIVE 标
        final liveItem = liveMap[item.mid];
        result.add(liveItem ?? item);
      }
    }
    // 2. 正在直播但没未读的 UP
    for (final entry in liveMap.entries) {
      if (seen.add(entry.key)) result.add(entry.value);
    }
    // 3. 其余关注 UP（保持原顺序）
    for (final item in upList ?? const <UpItem>[]) {
      if (seen.add(item.mid)) result.add(item);
    }
    return result;
  }

  factory FollowUpModel.fromJson(Map<String, dynamic> json) {
    final model = FollowUpModel.fromUpList(json['up_list']);
    final liveUsers = json['live_users'];
    if (liveUsers != null) {
      model.liveUsers = LiveUsers.fromJson(liveUsers);
    }
    return model;
  }

  FollowUpModel.fromUpList(Map<String, dynamic>? json) {
    if (json != null) {
      upList = (json['items'] as List?)
          ?.map((e) => UpItem.fromJson(e))
          .toList();
      hasMore = json['has_more'];
      offset = json['offset'];
    }
  }

  FollowUpModel.fromFollowList(Map<String, dynamic> json) {
    upList = (json['list'] as List?)
        ?.map((e) => FollowItemModel.fromJson(e))
        .toList();
  }
}

class LiveUsers {
  LiveUsers({
    this.count,
    this.group,
    this.items,
  });

  int? count;
  String? group;
  List<LiveUserItem>? items;

  LiveUsers.fromJson(Map<String, dynamic> json) {
    count = safeToInt(json['count']) ?? 0;
    group = json['group'];
    items = (json['items'] as List?)
        ?.map<LiveUserItem>((e) => LiveUserItem.fromJson(e))
        .toList();
  }
}

class LiveUserItem extends UpItem {
  bool? isReserveRecall;
  String? jumpUrl;
  int? roomId;
  String? title;

  LiveUserItem.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    isReserveRecall = json['is_reserve_recall'];
    jumpUrl = json['jump_url'];
    roomId = safeToInt(json['room_id']);
    title = json['title'];
  }
}

class UpItem {
  String? face;
  bool? hasUpdate;
  late int mid;
  String? uname;

  UpItem({
    this.face,
    this.hasUpdate,
    required this.mid,
    this.uname,
  });

  UpItem.fromJson(Map<String, dynamic> json) {
    face = json['face'];
    hasUpdate = json['has_update'];
    mid = safeToInt(json['mid']) ?? 0;
    uname = json['uname'];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UpItem && mid == other.mid;

  @override
  int get hashCode => mid.hashCode;
}
