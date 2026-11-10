import 'package:flutter/material.dart';

import '../api/chat_api_types.dart' show SendChatRequest;
import '../config/gist_chatbot_config.dart';
import 'pressable.dart';

/// 메시지 입력창 + 전송/중지 버튼 (웹 위젯과 동일: 로딩 중엔 중지 버튼으로 전환)
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    required this.onStop,
    required this.colors,
    this.loading = false,
    this.placeholder = '메시지를 입력하세요',
  });

  final void Function(String text) onSend;
  final VoidCallback onStop;
  final GistChatbotColors colors;
  final bool loading;
  final String placeholder;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.loading) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final canSend = _hasText && !widget.loading;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 4,
              minLines: 1,
              // 서버 한도를 넘는 질문은 400으로 거절되므로 입력 단계에서 막는다
              maxLength: SendChatRequest.maxQuestionLength,
              // 평소에는 글자 수를 숨기고 한도에 가까워졌을 때만 보여 준다
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) {
                    if (maxLength == null || currentLength < maxLength * 0.9) {
                      return null;
                    }
                    return Text(
                      '$currentLength / $maxLength',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    );
                  },
              style: TextStyle(fontSize: 14, color: colors.text),
              decoration: InputDecoration(
                hintText: widget.placeholder,
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
                isDense: true,
                filled: true,
                fillColor: colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 40,
            child: widget.loading
                ? _RoundIconButton(
                    color: colors.primary,
                    icon: Icons.stop_rounded,
                    iconSize: 20,
                    tooltip: '응답 중지',
                    onTap: widget.onStop,
                  )
                : _RoundIconButton(
                    color: canSend
                        ? colors.button
                        : colors.button.withValues(alpha: 0.5),
                    icon: Icons.arrow_upward_rounded,
                    iconSize: 24,
                    tooltip: '전송',
                    onTap: canSend ? _submit : null,
                  ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.color,
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.92,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }
}
