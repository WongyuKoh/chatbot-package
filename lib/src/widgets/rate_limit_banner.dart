import 'dart:async';

import 'package:flutter/material.dart';

/// 세션 질문 한도 소진 배너 + 재시도 카운트다운 (웹 위젯과 동일)
class RateLimitBanner extends StatefulWidget {
  const RateLimitBanner({
    super.key,
    required this.retryAt,
    required this.onExpired,
    this.limit,
  });

  /// 재시도 가능 시각 (ms since epoch)
  final int retryAt;
  final VoidCallback onExpired;

  /// 서버가 알려 준 세션 질문 한도. 모르면 숫자 없이 안내한다.
  final int? limit;

  @override
  State<RateLimitBanner> createState() => _RateLimitBannerState();
}

class _RateLimitBannerState extends State<RateLimitBanner> {
  Timer? _timer;
  String _remainingText = '';

  @override
  void initState() {
    super.initState();
    // 시간이 지난 뒤 패널을 다시 열면 이미 만료된 채로 생성됨.
    // 빌드 중 onExpired가 부모를 갱신하면 에러이므로 프레임이 끝난 뒤 해제
    if (DateTime.now().millisecondsSinceEpoch >= widget.retryAt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpired();
      });
      return;
    }
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= widget.retryAt) {
      _timer?.cancel();
      widget.onExpired();
      return;
    }
    final sec = ((widget.retryAt - now) / 1000).ceil();
    setState(() {
      if (sec < 60) {
        _remainingText = '$sec초 후에 다시 시도할 수 있습니다.';
      } else {
        final min = sec ~/ 60;
        final s = sec % 60;
        _remainingText = s == 0
            ? '$min분 후에 다시 시도할 수 있습니다.'
            : '$min분 $s초 후에 다시 시도할 수 있습니다.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.limit != null
                  ? '한 번에 최대 ${widget.limit}번까지만 질문할 수 있습니다.'
                  : '질문 횟수를 모두 사용했습니다.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7F1D1D),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _remainingText,
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF7F1D1D).withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
