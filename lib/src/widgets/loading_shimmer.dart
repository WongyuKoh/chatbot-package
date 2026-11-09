import 'package:flutter/material.dart';

import 'thinking_dots.dart';

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    // text-shimmer: 3s ease-in-out infinite
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
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
        const SizedBox(width: 6),
        ThinkingDots(color: widget.color),
      ],
    );
  }
}
