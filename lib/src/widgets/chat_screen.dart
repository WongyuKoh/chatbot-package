import 'package:flutter/material.dart';

import '../config/gist_chatbot_config.dart';
import '../state/chat_controller.dart';
import 'message_input.dart';
import 'message_list.dart';
import 'rate_limit_banner.dart';

/// 채팅 화면: 메시지 리스트 + 429 배너 + 입력창
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.controller, required this.config});

  final ChatController controller;
  final GistChatbotConfig config;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colors = widget.config.colors;
    final retryAt = controller.rateLimitRetryAt;

    return Container(
      color: colors.background,
      child: Column(
        children: [
          Expanded(
            child: MessageList(controller: controller, colors: colors),
          ),
          if (retryAt != null)
            RateLimitBanner(
              retryAt: retryAt,
              limit: controller.questionLimit,
              onExpired: controller.clearRateLimitWarning,
            ),
          MessageInput(
            onSend: controller.sendMessage,
            onStop: controller.stopStreaming,
            colors: colors,
            loading: controller.loading,
          ),
        ],
      ),
    );
  }
}
