import 'package:PiliPlus/common/widgets/scroll_physics.dart'
    show dynamicHorizontalDragRecognizer, tabBarView;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/pages/dynamics_create/view.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/dynamics_up/up_page_view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin {
  final _dynamicsController = Get.putOrFind(DynamicsController.new);
  UpPanelPosition get upPanelPosition => _dynamicsController.upPanelPosition;
  late final MainController _mainController = Get.find<MainController>();

  static const double _upBarHeight = 76;

  @override
  bool get wantKeepAlive => true;

  /// 发布按钮：固定在头像栏最左、「全部动态」之前。
  ///
  /// 形状用正圆 38×38 —— 和 UP 头像完全同形同尺寸，最贴合这一栏。
  /// 底色中灰（outline 62% 叠加，白底上约 #B5B5BA）+ 白色加号：
  /// 灰底白号有明确对比、看起来是「可点的主操作」，又不会比头像抢眼。
  /// 下方「发布」12.5px，与头像名字同一基线；占宽 70 与头像项一致。
  Widget _createDynamicBtn(ColorScheme colorScheme, {bool isRight = true}) =>
      SizedBox(
        width: 70,
        height: _upBarHeight,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => CreateDynPanel.onCreateDyn(context),
          child: Column(
            spacing: 4,
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: .circle,
                  color: colorScheme.outline.withValues(alpha: 0.62),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              // 和头像名字完全同构：头像名字在 isTop 下是 '${uname}\n'
              // (maxLines:2)，占两行高度。这里若只放一行，「发布」的 Column
              // 内容比头像项矮约 14px，居中后圆会往下掉一截 ——
              // 就是「发布按钮偏下、没和头像上方齐平」的原因。
              Text(
                '发布\n',
                maxLines: 2,
                textAlign: .center,
                overflow: .ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.1,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );

  Widget upPanelPart(ColorScheme colorScheme) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? 76 : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              _dynamicsController.onLoadMore();
            }
            return false;
          },
          child: Obx(
            () => _buildUpPanel(_dynamicsController.loadingState.value),
          ),
        ),
      ),
    );
  }

  Widget _buildUpPanel(LoadingState<FollowUpModel> upState) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
        upData: response,
        dynamicsController: _dynamicsController,
      ),
      Error() => Center(
        child: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _dynamicsController.onReload,
        ),
      ),
    };
  }

  /// 吸顶的 UP 头像栏。
  ///
  /// 发布按钮固定在整栏最左侧、「全部动态」之前，头像栏从它右边开始滚动。
  /// 之前放最右用 Stack 悬浮，会盖住最后一个 UP（截图中「笨笨的韭菜」被遮），
  /// 改成左侧固定位后任何头像都不会被压住。
  Widget _upBar(ColorScheme colorScheme) {
    return Row(
      children: [
        _createDynamicBtn(colorScheme),
        Expanded(
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              if (metrics.pixels >= metrics.maxScrollExtent - 300) {
                _dynamicsController.onLoadMore();
              }
              return false;
            },
            child: Obx(
              () => _buildUpPanel(_dynamicsController.loadingState.value),
            ),
          ),
        ),
      ],
    );
  }

  /// 吸顶的 UP 头像栏
  ///
  /// 对齐官方动态页：头像栏固定不动，滚动时不收起。
  /// 之前那套「随滚动收起」每帧都在改列表可用高度，整页反复重新布局，
  /// 加上头像列表跟着重建，就成了滑动发涩的主因。
  Widget _pinnedUpBar(ColorScheme colorScheme) {
    return RepaintBoundary(
      child: Material(
        type: .canvas,
        color: colorScheme.surface,
        child: SizedBox(
          width: double.infinity,
          height: _upBarHeight,
          child: _upBar(colorScheme),
        ),
      ),
    );
  }

  /// 「只保留 UP 主栏」布局：头像栏吸顶 + 当前 UP 的动态流
  Widget _buildUpOnly(BuildContext context, ColorScheme colorScheme) {
    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: onBuild(
        Column(
          children: [
            _pinnedUpBar(colorScheme),
            const Expanded(child: DynUpPageView()),
          ],
        ),
      ),
    );
  }

  bool get checkPage =>
      _mainController.navigationBars[0] != .dynamics &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType2(notification);
  }

  /// 顶部分类指示器：一排跟随手势的小圆点（不含文字）
  ///
  /// 取代原来的 [TabBar]：横向滑动切换分类时圆点连续跟随，
  /// 当前分类显示为稍长的胶囊，点圆点可直达对应分类。
  Widget _dynTabIndicator(ColorScheme colorScheme) {
    final tabController = _dynamicsController.tabController;
    final animation = tabController.animation;
    const tabTypes = DynamicsTabType.values;

    Widget buildIndicator(double position) {
      return Row(
        mainAxisSize: .min,
        children: [
          for (int i = 0; i < tabTypes.length; i++)
            GestureDetector(
              behavior: .opaque,
              onTap: () => _toDynTab(i),
              child: SizedBox(
                height: 28,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width:
                        4 + 8 * (1 - (position - i).abs()).clamp(0.0, 1.0),
                    height: 4.5,
                    margin: const .symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(
                        alpha:
                            .22 +
                            .78 * (1 - (position - i).abs()).clamp(0.0, 1.0),
                      ),
                      borderRadius: const .all(.circular(2.25)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final Widget child;
    if (animation == null) {
      child = buildIndicator(tabController.index.toDouble());
    } else {
      child = AnimatedBuilder(
        animation: animation,
        builder: (context, _) => buildIndicator(animation.value),
      );
    }
    return Center(child: child);
  }

  void _toDynTab(int index) {
    final tabController = _dynamicsController.tabController;
    if (tabController.index != index) {
      tabController.animateTo(index);
      _dynamicsController.animateToTop();
    } else {
      _dynamicsController.animateToTop();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);

    if (_dynamicsController.upOnlyMode) {
      return _buildUpOnly(context, colorScheme);
    }

    Widget? drawer;
    Widget? endDrawer;

    Widget? leading;
    Widget actions;

    final swipeSensitivity = Pref.dynSwipeSensitivity;
    final useUpPageView = _dynamicsController.useUpPageView;

    Widget child = tabBarView(
      controller: _dynamicsController.tabController,
      recognizer: () =>
          dynamicHorizontalDragRecognizer(swipeSensitivity),
      children: DynamicsTabType.values
          .map(
            (e) => e == .up && useUpPageView
                ? const DynUpPageView()
                : DynamicsTabPage(dynamicsType: e),
          )
          .toList(),
    );

    switch (upPanelPosition) {
      case .top:
        child = Column(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftFixed:
        child = Row(
          children: [
            upPanelPart(colorScheme),
            Expanded(child: child),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .rightFixed:
        child = Row(
          children: [
            Expanded(child: child),
            upPanelPart(colorScheme),
          ],
        );
        actions = _createDynamicBtn(colorScheme);
      case .leftDrawer:
        drawer = upPanelPart(colorScheme);
        actions = _createDynamicBtn(colorScheme);
        leading = const DrawerButton();
      case .rightDrawer:
        endDrawer = upPanelPart(colorScheme);
        leading = _createDynamicBtn(colorScheme, isRight: false);
        actions = const EndDrawerButton();
    }

    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const .fromHeight(40),
        child: Row(
          children: [
            ?leading,
            Expanded(child: _dynTabIndicator(colorScheme)),
            actions,
          ],
        ),
      ),
      drawer: drawer,
      endDrawer: endDrawer,
      body: onBuild(child),
    );
  }
}
