import 'package:PiliPlus/http/dynamics.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/models/common/dynamic/dynamic_filter.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/common/common_controller.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class DynamicsTabController
    extends CommonListController<DynamicsDataModel, DynamicItemModel>
    with AccountMixin, RefreshImplMixin {
  DynamicsTabController({required this.dynamicsType});
  final DynamicsTabType dynamicsType;

  String? offset;

  /// 「全部动态」内的二级内容筛选（仅全部页生效）
  final _filter = DynamicsFilter.all.obs;
  DynamicsFilter get filter => _filter.value;

  late final mainController = Get.find<MainController>();
  final dynamicsController = Get.find<DynamicsController>();

  /// 实际展示的数据：全部页按筛选条件过滤，其它分类原样返回
  List<DynamicItemModel> get displayData {
    final list = loadingState.value.data;
    if (list == null || dynamicsType != .all) return list ?? const [];
    final filter = _filter.value;
    if (filter == DynamicsFilter.all) return list;
    return list.where(filter.matches).toList();
  }

  /// 某条动态在原始列表中的下标（筛选后展示下标与原始下标可能不同，
  /// 删除/折叠等操作需按原始下标操作，避免删错）
  int rawIndexOf(DynamicItemModel item) {
    final list = loadingState.value.data;
    return list == null ? -1 : list.indexOf(item);
  }

  void setFilter(DynamicsFilter filter) {
    if (_filter.value == filter) return;
    _filter.value = filter;
    scrollController.jumpToTop();
  }

  /// 一键清空所有关注 UP 的「未读动态」标记
  void clearAllRead() {
    dynamicsController.markUpRead(-1);
    if (dynamicsType == .all) mainController.setDynCount();
    SmartDialog.showToast('已清空未读标记');
  }

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> onRefresh() {
    if (dynamicsType == .all) {
      mainController.setDynCount();
    }
    offset = null;
    return super.onRefresh();
  }

  @override
  List<DynamicItemModel>? getDataList(DynamicsDataModel response) {
    offset = response.offset;
    return response.items;
  }

  @override
  Future<LoadingState<DynamicsDataModel>> customGetData() =>
      DynamicsHttp.followDynamic(
        offset: offset,
        type: dynamicsType,
        hostMid: dynamicsController.hostMid,
        tempBannedList: dynamicsController.tempBannedList,
      );

  Future<void> onRemove(int index, dynamic dynamicId) async {
    final res = await MsgHttp.removeDynamic(dynIdStr: dynamicId);
    if (res.isSuccess) {
      loadingState
        ..value.data!.removeAt(index)
        ..refresh();
      SmartDialog.showToast('删除成功');
    } else {
      res.toast();
    }
  }

  @override
  Future<void> onReload() {
    scrollController.jumpToTop();
    return super.onReload();
  }

  void onBlock(int index) {
    if (dynamicsType != .up) {
      loadingState
        ..value.data!.removeAt(index)
        ..refresh();
    }
  }

  void onUnfold(DynamicItemModel item, int index) {
    try {
      final list = loadingState.value.data!;
      final ids = item.modules.moduleFold!.ids!;
      final flag = index + ids.length + 1;
      for (int i = index + 1; i < flag; i++) {
        list[i].visible = true;
      }
      item.modules.moduleFold = null;
      loadingState.refresh();
    } catch (_) {}
  }

  @override
  void onChangeAccount(bool isLogin) => onReload();
}
