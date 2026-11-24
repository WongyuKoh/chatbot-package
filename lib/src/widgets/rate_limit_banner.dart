import 'dart:async';

import 'package:flutter/material.dart';

/// 질문 한도 소진 배너 + 재시도 카운트다운
class RateLimitBanner extends StatefulWidget {
  const RateLimitBanner({
    super.key,
    required this.retryAt,
    required this.onExpired,
    this.limit,
    this.windowSeconds,
  });

  /// 재시도 가능 시각 (ms since epoch)
  final int retryAt;
  final VoidCallback onExpired;

  /// 서버가 알려 준 질문 한도. 모르면 숫자 없이 안내한다.
  final int? limit;

  /// 한도를 세는 기간(초). 이전 서버(세션당 고정 한도)는 보내지 않는다.
  final int? windowSeconds;

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
      _remainingText = '${_formatRemaining(sec)} 후에 다시 시도할 수 있습니다.';
    });
  }

  /// 기간 한도에서는 남은 시간이 몇 시간·며칠일 수 있어 큰 단위 두 개까지 보여 준다
  static String _formatRemaining(int sec) {
    String pair(int big, String bigUnit, int small, String smallUnit) =>
        small == 0 ? '$big$bigUnit' : '$big$bigUnit $small$smallUnit';
    if (sec < 60) return '$sec초';
    if (sec < 3600) return pair(sec ~/ 60, '분', sec % 60, '초');
    if (sec < 86400) return pair(sec ~/ 3600, '시간', sec % 3600 ~/ 60, '분');
    return pair(sec ~/ 86400, '일', sec % 86400 ~/ 3600, '시간');
  }

  /// 한도 기간을 나누어떨어지는 가장 큰 단위로 (86400 → 1일, 5400 → 90분)
  static String _formatWindow(int sec) {
    if (sec % 86400 == 0) return '${sec ~/ 86400}일';
    if (sec % 3600 == 0) return '${sec ~/ 3600}시간';
    if (sec % 60 == 0) return '${sec ~/ 60}분';
    return '$sec초';
  }

  String get _limitText {
    final limit = widget.limit;
    final window = widget.windowSeconds;
    if (limit == null) return '질문 횟수를 모두 사용했습니다.';
    if (window == null) return '한 번에 최대 $limit번까지만 질문할 수 있습니다.';
    return '${_formatWindow(window)} 동안 최대 $limit번까지 질문할 수 있습니다.';
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
              _limitText,
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
