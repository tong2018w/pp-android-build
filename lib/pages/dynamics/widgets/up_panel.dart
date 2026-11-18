import 'dart:math' as math;

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 直播头像外圈的渐变呼吸环
class _LiveRing extends StatefulWidget {
  const _LiveRing({required this.child});

  final Widget child;

  @override
  State<_LiveRing> createState() => _LiveRingState();
}

class _LiveRingState extends State<_LiveRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        // 呼吸 + 缓慢旋转的粉紫渐变环，套在头像外圈
        return CustomPaint(
          foregroundPainter: _RingPainter(
            progress: t,
            color: color,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = Rect.fromCircle(
      center: rect.center,
      radius: rect.shortestSide / 2 + 2.5,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..shader = SweepGradient(
        startAngle: progress * math.pi * 2,
        endAngle: progress * math.pi * 2 + math.pi * 1.6,
        colors: [color.withValues(alpha: 0.15), color, color.withValues(alpha: 0.15)],
      ).createShader(r);
    canvas.drawArc(r, 0, math.pi * 2, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

class UpPanel extends StatefulWidget {
  const UpPanel({
    super.key,
    required this.upData,
    required this.dynamicsController,
  });

  final FollowUpModel upData;
  final DynamicsController dynamicsController;

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  late final controller = widget.dynamicsController;
  late final isTop = controller.upPanelPosition == UpPanelPosition.top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upData = widget.upData;
    // 统一用模型层的排序：直播 → 未读 → 其余；「全部动态」「我」单独置顶
    final ordered = upData.orderedUpList;
    return CustomScrollView(
      scrollDirection: isTop ? .horizontal : .vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      controller: controller.scrollController,
      slivers: [
        // 去掉原 Live(x) 入口区域：直播 UP 现在直接混在关注列表里
        // （头像带呼吸环 + LIVE 标），不再单独占一块、也不再插在「全部动态」前。
        SliverToBoxAdapter(
          child: Obx(
            () => upItemBuild(
              theme,
              UpItem(face: '', uname: '全部动态', mid: -1),
            ),
          ),
        ),
        if (ordered.isNotEmpty)
          SliverList.builder(
            itemCount: ordered.length,
            itemBuilder: (context, index) {
              // 逐 UP 横向分页滑动时，高亮跟随当前 UP
              return Obx(() => upItemBuild(theme, ordered[index]));
            },
          ),
        // 发布按钮已移到滚动区左侧（见 _upBar），这里只需一点收尾间距
        if (isTop) const SliverToBoxAdapter(child: SizedBox(width: 8)),
        if (!isTop) const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  void _onSelect(UpItem item) {
    item.hasUpdate = false;
    controller.onSelectUp(item.mid);
    setState(() {});
  }

  Widget upItemBuild(ThemeData theme, UpItem item) {
    final currentMid = controller.currentMid;
    final isLive = item is LiveUserItem;
    // 只有「全部动态」和自己那一位算选中；原来是 currentMid == -1 就全高亮，
    // 导致头像栏一片全亮，看不出当前停在哪位 UP
    // 未读 UP 也保持全亮，别让未读小圆点跟着变半透明看不清
    final hasUnread = item.hasUpdate ?? false;
    final isCurrent = isLive || hasUnread || currentMid == item.mid;

    final isAll = item.mid == -1;
    void toMemberPage() => Get.toNamed('/member?mid=${item.mid}');

    Widget avatar;
    if (isAll) {
      avatar = DecoratedBox(
        decoration: const BoxDecoration(
          shape: .circle,
          color: Color(0xFF5CB67B),
        ),
        child: Image.asset(
          width: 38,
          height: 38,
          cacheWidth: 38.cacheSize(context),
          Assets.logo2,
          color: Colors.white,
        ),
      );
    } else {
      avatar = Padding(
        padding: const .symmetric(horizontal: 4),
        child: NetworkImgLayer(
          width: 38,
          height: 38,
          src: item.face,
          type: .avatar,
        ),
      );
      if (isLive) {
        // 直播头像：外圈渐变呼吸环 + 右下角小 LIVE 标
        avatar = _LiveRing(
          child: Stack(
            clipBehavior: .none,
            children: [
              avatar,
              Positioned(
                bottom: -2,
                right: -8,
                child: IgnorePointer(
                  child: Container(
                    padding: const .symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const .all(.circular(4)),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        fontSize: 8,
                        height: 1.1,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      // 未读小圆点：和直播态互不排斥。
      // 原来是 `else if (item.hasUpdate)`，直播头像走了 if(isLive) 分支后
      // 就不会再叠加未读点 —— 直播 UP 的未读提示整个丢了。
      // 拆成独立 if，直播环 + LIVE 标 + 未读点三者可共存。
      if (item.hasUpdate ?? false) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: 0,
              right: 4,
              child: Badge(
                smallSize: 8,
                backgroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        );
      }
    }

    return SizedBox(
      height: 76,
      width: isTop ? 70 : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          feedBack();
          if (isLive) {
            PageUtils.toLiveRoom(item.roomId);
          } else {
            _onSelect(item);
          }
        },
        // onDoubleTap: isLive ? () => _onSelect(data) : null,
        onLongPress: !isAll ? toMemberPage : null,
        onSecondaryTap: !isAll && !PlatformUtils.isMobile ? toMemberPage : null,
        child: AnimatedOpacity(
          opacity: isCurrent ? 1 : 0.62,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          child: Column(
            spacing: 4,
            mainAxisSize: .min,
            mainAxisAlignment: .center,
            children: [
              avatar,
              Padding(
                padding: const .symmetric(horizontal: 4),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    // 名字只在「确实是当前这位 UP」时高亮，
                    // live 头像保持全亮但不染成主题色
                    color: currentMid == item.mid
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    height: 1.1,
                    fontSize: 12.5,
                  ),
                  child: Text(
                    isTop ? '${item.uname}\n' : item.uname!,
                    maxLines: 2,
                    textAlign: .center,
                    overflow: .ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
