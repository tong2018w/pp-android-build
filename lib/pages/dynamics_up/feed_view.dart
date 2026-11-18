import 'dart:async' show Timer;

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliPlus/pages/dynamics_up/feed_controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 「逐个浏览 UP」模式下的单页：一位 UP 的动态流
class DynUpFeedPage extends StatefulWidget {
  const DynUpFeedPage({super.key, required this.mid});

  /// -1 表示「全部动态」
  final int mid;

  @override
  State<DynUpFeedPage> createState() => _DynUpFeedPageState();
}

class _DynUpFeedPageState extends State<DynUpFeedPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  late final _tag = 'dynUpFeed${widget.mid}';
  late final controller = Get.putOrFind(
    () => DynUpFeedController(mid: widget.mid),
    tag: _tag,
  );

  /// 延迟销毁表：横滑离开页面后先留一会儿
  ///
  /// PageView 只保留当前页和正在动画的那一页，来回横滑时旧页面会被销毁。
  /// 之前是立刻 Get.delete，滑回去就得重新请求一遍，列表还会跳回顶部。
  /// 这里给 8 秒宽限期：来回滑的窗口内沿用原来的 controller 和滚动位置。
  static final Map<String, Timer> _pendingDispose = {};

  @override
  void initState() {
    super.initState();
    _pendingDispose.remove(_tag)?.cancel();
  }

  @override
  void dispose() {
    _pendingDispose.remove(_tag)?.cancel();
    _pendingDispose[_tag] = Timer(const Duration(seconds: 8), () {
      _pendingDispose.remove(_tag);
      if (Get.isRegistered<DynUpFeedController>(tag: _tag)) {
        Get.delete<DynUpFeedController>(tag: _tag, force: true);
      }
    });
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> onRefresh() => controller.onRefresh();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final refreshStyle = Pref.dynRefreshStyle;
    return refreshIndicator(
      key: controller.refreshKey,
      onRefresh: onRefresh,
      // 官方风格：指示器更贴近顶部，下拉一点点就会触发刷新
      displacement: refreshStyle == .official ? 12.0 : null,
      child: NotificationListener<ScrollNotification>(
        // 离底部还有 800px 就提前加载，不要等贴到底再顿一下
        onNotification: _onScroll,
        child: CustomScrollView(
          // 显式指定父级，Android / iOS 的边界行为保持一致
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          controller: controller.scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: buildPage(
                Obx(() => _buildBody(controller.loadingState.value)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 滚动到接近底部时预取下一页
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != .vertical) return false;
    if (notification.metrics.extentAfter < 800) {
      controller.onLoadMore();
    }
    return false;
  }

  /// 个别动态上滑才显示、刷新又消失的第二个原因：
  /// 瀑布流 (SliverMasonryGrid) 会把每张卡片按「估算高度」放进列里，
  /// 卡片内部图片/视频异步加载后高度变化，若估算偏小，下面那张会被
  /// 压到视口外，看起来就像「还没加载」。列表流没有这个问题。
  /// 动态卡片本身已经是单列全宽，用瀑布流没有收益，这里强制用列表流，
  /// 高度由内容自撑，不再出现裁剪。
  bool get _useWaterfall => false;

  Widget _buildBody(LoadingState<List<DynamicItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => dynSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? _useWaterfall
                  ? SliverMasonryGrid(
                      crossAxisSpacing: 4,
                      gridDelegate: dynGridDelegate,
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _itemBuilder(response, index),
                        childCount: response.length,
                      ),
                    )
                  : SliverList.builder(
                      itemBuilder: (context, index) =>
                          _itemBuilder(response, index),
                      itemCount: response.length,
                    )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _itemBuilder(List<DynamicItemModel> list, int index) {
    final item = list[index];
    return DynamicPanel(
      item: item,
      onRemove: (idStr) => controller.onRemove(index, idStr),
      onBlock: () => controller.onBlock(index),
      onUnfold: () => controller.onUnfold(item, index),
    );
  }
}
