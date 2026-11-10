import 'package:flutter/material.dart';

import '../config/gist_chatbot_config.dart';
import 'pressable.dart';

/// 맨 아래로 버튼: 사용자가 위로 스크롤해 하단 따라가기가 꺼졌을 때 메시지 영역 하단 가운데에 표시.
/// 평소엔 ↓ 원형, 답변 생성 중엔 "답변 작성 중" 라벨을 붙인 pill로 바뀐다.
class ScrollToBottomButton extends StatelessWidget {
  const ScrollToBottomButton({
    super.key,
    required this.visible,
    required this.generating,
    required this.colors,
    required this.onTap,
  });

  final bool visible;

  /// 아래에서 답변이 아직 생성되고 있는지 여부
  final bool generating;
  final GistChatbotColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 패널 전환과 같은 fade + scale로 나타나고 사라짐
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: visible
          ? _ScrollToBottomFace(
              key: ValueKey(generating),
              generating: generating,
              colors: colors,
              onTap: onTap,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _ScrollToBottomFace extends StatelessWidget {
  const _ScrollToBottomFace({
    super.key,
    required this.generating,
    required this.colors,
    required this.onTap,
  });

  final bool generating;
  final GistChatbotColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 빨간색은 전송 버튼에만 쓰고, 이 버튼은 배경색 + 테두리로 한 단계 낮춤
    final decoration = ShapeDecoration(
      color: colors.background,
      shape: StadiumBorder(side: BorderSide(color: colors.border)),
      shadows: const [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );

    final face = generating
        ? Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: decoration,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 6, height: 6),
                ),
                const SizedBox(width: 6),
                Text(
                  '답변 작성 중',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.text,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 16,
                  color: colors.text,
                ),
              ],
            ),
          )
        : Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: decoration,
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 20,
              color: colors.text,
            ),
          );

    return Tooltip(
      message: '맨 아래로 이동',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.92,
        // 보이는 크기는 36px이지만 터치 영역은 48px 확보 (Material 최소 터치 영역)
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(widthFactor: 1, heightFactor: 1, child: face),
        ),
      ),
    );
  }
}
