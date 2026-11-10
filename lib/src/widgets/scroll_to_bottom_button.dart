import 'package:flutter/material.dart';

import '../config/gist_chatbot_config.dart';
import 'pressable.dart';
import 'thinking_dots.dart';

/// 맨 아래로 버튼: 사용자가 위로 스크롤해 하단 따라가기가 꺼졌을 때 메시지 영역 하단 가운데에 표시.
/// 평소엔 ↓ 원형이고, 답변 생성 중엔 같은 원 안에서 화살표 대신 점 3개(…)가 깜빡인다 (웹 위젯과 동일).
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
    // 패널 전환과 같은 fade + scale로 나타나고 사라짐.
    // 생성 여부가 바뀔 때는 버튼을 바꿔 끼우지 않고 안의 내용만 바뀐다 (웹 위젯과 동일)
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
    required this.generating,
    required this.colors,
    required this.onTap,
  });

  final bool generating;
  final GistChatbotColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 웹 위젯과 동일: assistant 말풍선 배경 + 테두리 + shadow-md
    final decoration = ShapeDecoration(
      color: colors.assistantMessageBg,
      shape: StadiumBorder(side: BorderSide(color: colors.border)),
      shadows: const [
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 6,
          spreadRadius: -1,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: Color(0x1A000000),
          blurRadius: 4,
          spreadRadius: -2,
          offset: Offset(0, 2),
        ),
      ],
    );

    // 생성 중에도 크기와 모양은 그대로 32px 원이다
    final face = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: decoration,
      child: generating
          // 화살표 대신 점 애니메이션으로 생성 중임을 보여주고, 스크린 리더엔 문구로 알림.
          // 웹 위젯과 동일: 4px 점, 간격 3px, 버튼 글자색
          ? Semantics(
              label: '답변 작성 중',
              child: ThinkingDots(color: colors.text, size: 4, gap: 3),
            )
          : Icon(Icons.arrow_downward_rounded, size: 16, color: colors.text),
    );

    return Tooltip(
      message: '맨 아래로 이동',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.92,
        // 보이는 크기는 32px이지만 터치 영역은 48px 확보 (Material 최소 터치 영역)
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(widthFactor: 1, heightFactor: 1, child: face),
        ),
      ),
    );
  }
}
