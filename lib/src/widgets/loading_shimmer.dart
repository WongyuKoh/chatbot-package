import 'package:flutter/material.dart';

/// 로딩 문구 shimmer + thinking dots (웹 위젯의 loading-text-shimmer / thinking-dot)
class LoadingIndicatorRow extends StatefulWidget {
  const LoadingIndicatorRow({
    super.key,
    required this.message,
    required this.color,
  });

  final String message;
  final Color color;

  @override
  State<LoadingIndicatorRow> createState() => _LoadingIndicatorRowState();
}

class _LoadingIndicatorRowState extends State<LoadingIndicatorRow>
    with TickerProviderStateMixin {
  late final AnimationController _shimmerController;
  late final AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    // text-shimmer: 3s ease-in-out infinite
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    // thinking-dot: 1.4s ease-in-out infinite
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 서버가 보낸 단계 문구는 길 수 있어 말풍선 폭 안에서 줄바꿈되게 한다
        Flexible(
          child: AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              // 90deg 그라데이션이 좌→우로 흐르는 효과 (background-position 200%→-200%)
              final t = _shimmerController.value;
              return ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: const [
                      Color(0xFF64748B),
                      Color(0xFF64748B),
                      Color(0xFF94A3B8),
                      Color(0xFFCBD5E1),
                      Color(0xFF94A3B8),
                      Color(0xFF64748B),
                      Color(0xFF64748B),
                    ],
                    stops: const [0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 1.0],
                    begin: Alignment(-1 - 4 * (1 - t) + 2, 0),
                    end: Alignment(1 - 4 * (1 - t) + 2, 0),
                    tileMode: TileMode.clamp,
                  ).createShader(
                    Rect.fromLTWH(
                      -bounds.width * 2 + bounds.width * 4 * t,
                      0,
                      bounds.width * 3,
                      bounds.height,
                    ),
                  );
                },
                blendMode: BlendMode.srcIn,
                child: child,
              );
            },
            child: Text(
              widget.message,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 6),
        AnimatedBuilder(
          animation: _dotsController,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // delay 0 / 0.2s / 0.4s, keyframes: 0%,80%,100% → 0.3/0.8, 40% → 1/1
                final delay = i * 0.2 / 1.4;
                var t = _dotsController.value - delay;
                if (t < 0) t += 1;
                double progress;
                if (t <= 0.4) {
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
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 6,
                        height: 6,
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
        ),
      ],
    );
  }
}
