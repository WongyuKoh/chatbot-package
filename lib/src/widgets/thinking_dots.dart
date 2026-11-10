import 'package:flutter/material.dart';

/// 순서대로 깜빡이는 점 3개 (웹 위젯의 thinking-dot)
///
/// 시스템에서 애니메이션 줄이기가 켜져 있으면 멈춘 점으로 표시한다.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({
    super.key,
    required this.color,
    this.size = 6,
    this.gap = 6,
  });

  final Color color;

  /// 점 하나의 지름. 기본값은 로딩 말풍선에서 쓰는 크기(웹 위젯 thinking-dot의 6px)
  final double size;

  /// 점 사이 간격
  final double gap;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  // thinking-dot: 1.4s ease-in-out infinite
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final animating = _controller.isAnimating;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // delay 0 / 0.2s / 0.4s, keyframes: 0%,80%,100% → 0.3/0.8, 40% → 1/1
            final delay = i * 0.2 / 1.4;
            var t = _controller.value - delay;
            if (t < 0) t += 1;
            double progress;
            if (!animating) {
              progress = 1;
            } else if (t <= 0.4) {
              progress = t / 0.4;
            } else if (t <= 0.8) {
              progress = 1 - (t - 0.4) / 0.4;
            } else {
              progress = 0;
            }
            final eased = Curves.easeInOut.transform(progress);
            final opacity = 0.3 + 0.7 * eased;
            final scale = 0.8 + 0.2 * eased;
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : widget.gap),
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
