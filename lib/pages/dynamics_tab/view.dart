import 'dart:async';

import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamic_filter.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliPlus/pages/dynamics_tab/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class DynamicsTabPage extends StatefulWidget {
  const DynamicsTabPage({super.key, required this.dynamicsType});

  final DynamicsTabType dynamicsType;

  @override
  State<DynamicsTabPage> createState() => _DynamicsTabPageState();
}

class _DynamicsTabPageState extends State<DynamicsTabPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  final dynamicsController = Get.putOrFind(DynamicsController.new);
  late final DynamicsTabController controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    controller = Get.putOrFind(
      () => DynamicsTabController(dynamicsType: widget.dynamicsType),
      tag: widget.dynamicsType.name,
    );
    super.initState();
  }

  Future<void> onRefresh() {
    dynamicsController.singleRefresh();
    return controller.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return refreshIndicator(
      key: controller.refreshKey,
      onRefresh: onRefresh,
      // 官方风格：指示器贴近顶部，下拉很短就会触发刷新
      displacement: Pref.dynRefreshStyle == .official ? 12.0 : null,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: controller.scrollController,
        slivers: [
          if (widget.dynamicsType == .all)
            SliverToBoxAdapter(child: _filterBar(ColorScheme.of(context))),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 100),
            sliver: buildPage(
              Obx(() => _buildBody(controller.loadingState.value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LoadingState<List<DynamicItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => dynSkeleton,
      Success(:final response) => _buildSuccess(response),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _buildSuccess(List<DynamicItemModel>? response) {
    // 全部页按筛选条件展示，其它分类原样展示
    final data = controller.displayData;
    if (data.isEmpty) {
      final raw = response;
      if (raw != null && raw.isNotEmpty) {
        return SliverToBoxAdapter(
          child: Center(
            child: Column(
              mainAxisSize: .min,
              children: [
                const Text('该分类下没有更多内容'),
                TextButton(
                  onPressed: controller.onReload,
                  child: const Text('刷新'),
                ),
              ],
            ),
          ),
        );
      }
      return HttpError(onReload: controller.onReload);
    }
    return GlobalData().dynamicsWaterfallFlow
            ? SliverMasonryGrid(
                crossAxisSpacing: 4,
                gridDelegate: dynGridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _itemBuilder(data, index),
                  childCount: data.length,
                ),
              )
            : SliverList.builder(
                itemBuilder: (context, index) => _itemBuilder(data, index),
                itemCount: data.length,
              );
  }

  /// 「全部动态」的二级筛选条：内容类型快捷过滤 + 一键清空未读
  Widget _filterBar(ColorScheme colorScheme) {
    return Obx(
      () => Material(
        color: colorScheme.surface,
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: .horizontal,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      for (final filter in DynamicsFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _filterChip(colorScheme, filter),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.dynamicsType == .all)
                TextButton(
                  onPressed: controller.clearAllRead,
                  child: const Text('清空未读'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(ColorScheme colorScheme, DynamicsFilter filter) {
    final selected = controller.filter == filter;
    return InkWell(
      onTap: () => controller.setFilter(filter),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: const BorderRadius.all(.circular(16)),
        ),
        child: Text(
          filter.label,
          style: TextStyle(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _itemBuilder(List<DynamicItemModel> list, int index) {
    if (index == list.length - 1) {
      controller.onLoadMore();
    }
    final item = list[index];
    // 筛选后展示下标可能与原始列表下标不一致，操作按原始下标进行
    final rawIndex = controller.rawIndexOf(item);
    final targetIndex = rawIndex >= 0 ? rawIndex : index;
    return DynamicPanel(
      item: item,
      onRemove: (idStr) => controller.onRemove(targetIndex, idStr),
      onBlock: () => controller.onBlock(targetIndex),
      onUnfold: () => controller.onUnfold(item, targetIndex),
    );
  }
}
