import 'package:PiliPlus/common/widgets/scroll_physics.dart' show dynPageView;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics_up/feed_controller.dart';
import 'package:PiliPlus/pages/dynamics_up/feed_view.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 「逐个浏览 UP」：横向分页，每页一位 UP 的动态流
///
/// 对应 issue #3434 的诉求：不想来回点进点出主页，横划一下到下一位关注 UP。
class DynUpPageView extends StatefulWidget {
  const DynUpPageView({super.key});

  @override
  State<DynUpPageView> createState() => _DynUpPageViewState();
}

class _DynUpPageViewState extends State<DynUpPageView>
    with AutomaticKeepAliveClientMixin {
  final dynamicsController = Get.find<DynamicsController>();
  late final sensitivity = Pref.dynSwipeSensitivity;
  late final PageController pageController;

  /// 当前参与分页的 UP：第 0 项固定是「全部动态」
  List<int> mids = const [-1];

  /// UP 列表刷新后重建分页（只在数据真的变化时触发，不再每帧轮询）
  late final Worker _loadingWorker;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    pageController = PageController(
      initialPage: _indexOf(dynamicsController.currentMid),
    );
    _register();
    syncUpList();
    _loadingWorker = ever<LoadingState<FollowUpModel>>(
      dynamicsController.loadingState,
      (_) => syncUpList(),
    );
    pageController.addListener(_syncUpBarToPage);
  }

  @override
  void dispose() {
    pageController.removeListener(_syncUpBarToPage);
    _loadingWorker.dispose();
    // 同一时刻只存在一个分页容器，直接清空钩子；
    // 不要用 identical() 比较方法 tear-off，那个比较不可靠。
    dynamicsController
      ..upPageSync = null
      ..upPageJump = null
      ..upPageRefresh = null
      ..upPageScrollToTop = null
      ..upPageToTopOrRefresh = null;
    pageController.dispose();
    super.dispose();
  }

  /// 把自身注册到动态控制器，供 UP 面板联动与刷新
  void _register() {
    dynamicsController
      ..upPageSync = syncUpList
      ..upPageJump = jumpToMid
      ..upPageRefresh = refreshCurrent
      ..upPageScrollToTop = toTop
      ..upPageToTopOrRefresh = toTopOrRefresh;
  }

  /// 当前可见页对应的动态流
  DynUpFeedController? get _currentFeed {
    try {
      final mid = mids.elementAtOrNull(_currentIndex);
      if (mid == null) return null;
      return Get.find<DynUpFeedController>(tag: 'dynUpFeed$mid');
    } catch (_) {
      return null;
    }
  }

  /// 下拉刷新：先刷新 UP 列表（更新未读红点），再刷新当前 UP 的动态
  Future<void> refreshCurrent() async {
    await dynamicsController.singleRefresh();
    await _currentFeed?.onRefresh();
  }

  void toTop() => _currentFeed?.animateToTop();

  /// 头像栏跟随横滑实时滚动
  ///
  /// 之前有两处导致「动效看不见」：
  /// 1. target 用 (page-1)*70 做偏移 —— 那是给已删除的 Live 区域留的位置。
  ///    现在头像栏第 0 项就是「全部动态」，对应 page=0，偏移应为 page*70。
  ///    偏移错了，头像栏跟着滑时高亮和实际页面对不上，看着像没动。
  /// 2. 一直用 jumpTo 硬跳，没有过渡观感。
  /// 现在手指拖动/jump 时用 jumpTo 保证跟手；松手后 page 是整数、
  /// 差值较大时用短 animateTo 补一个可见的滑动动画。
  void _syncUpBarToPage() {
    if (!mounted || !pageController.hasClients) return;
    if (!pageController.position.hasContentDimensions) return;
    final page = pageController.page;
    if (page == null) return;
    final sc = dynamicsController.scrollController;
    if (!sc.hasClients) return;
    final scPos = sc.position;
    if (!scPos.hasContentDimensions) return;

    const itemWidth = 70.0;
    final target = (page * itemWidth).clamp(0.0, scPos.maxScrollExtent);
    final delta = (sc.offset - target).abs();
    if (delta < 1.0) return;

    final isSettling = (page - page.round()).abs() < 0.01;
    if (isSettling && delta > itemWidth * 0.4) {
      // 松手归位、且差得较多：给一个可见的短动画
      sc.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      // 手指拖动中：瞬间跟随，保证跟手不卡顿
      sc.jumpTo(target);
    }
  }

  void toTopOrRefresh() => _currentFeed?.toTopOrRefresh();

  int _indexOf(int mid, [List<int>? list]) {
    final index = (list ?? mids).indexOf(mid);
    return index == -1 ? 0 : index;
  }

  int get _currentIndex {
    final page = pageController.hasClients &&
            pageController.position.hasContentDimensions
        ? pageController.page
        : null;
    return (page ?? pageController.initialPage.toDouble()).round();
  }

  /// 关注 UP 列表更新后重建分页，并尽量停在原来那位 UP 上
  void syncUpList() {
    if (!mounted) return;
    final model = dynamicsController.loadingState.value.dataOrNull;
    // 与头像栏共用同一顺序：直播/未读优先。头像栏点是第几项，
    // 分页就必须对应同一个 mid，否则排序后会跳错页。
    final ordered = model?.orderedUpList ?? const <UpItem>[];
    final seen = <int>{-1};
    final newMids = <int>[
      -1,
      for (final item in ordered)
        if (seen.add(item.mid)) item.mid,
    ];
    if (newMids.length == mids.length) {
      var same = true;
      for (int i = 0; i < mids.length; i++) {
        if (mids[i] != newMids[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }

    final anchor = mids.elementAtOrNull(_currentIndex);
    final target = _indexOf(anchor ?? -1, newMids);
    final hadClients = pageController.hasClients;
    setState(() {
      mids = newMids;
    });
    if (hadClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !pageController.hasClients) return;
        final current = _currentIndex;
        if (current != target && target < mids.length) {
          pageController.jumpToPage(target);
        }
      });
    }
  }

  /// 点击 UP 面板头像时跳到对应分页
  void jumpToMid(int mid) {
    if (!mounted) return;
    final target = _indexOf(mid);
    if (!pageController.hasClients) return;
    if (_currentIndex == target) return;
    final distance = (target - _currentIndex).abs();
    if (distance > 5) {
      // 跳太远做动画会一路刷过好几页，直接落位更干净
      pageController.jumpToPage(target);
    } else {
      // 时长跟着距离走：相邻一位 240ms，跨几页也不显得拖沓
      pageController.animateToPage(
        target,
        duration: Duration(milliseconds: (240 + distance * 45).clamp(240, 420)),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return dynPageView(
      controller: pageController,
      sensitivity: sensitivity,
      itemCount: mids.length,
      itemBuilder: (context, index) {
        final mid = mids[index];
        return DynUpFeedPage(key: ValueKey(mid), mid: mid);
      },
      onPageChanged: (index) {
        feedBack();
        final mid = mids.elementAtOrNull(index);
        if (mid != null) dynamicsController.onSwipeToUp(mid);
      },
    );
  }
}
