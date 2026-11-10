import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../config/gist_chatbot_config.dart';
import '../state/chat_controller.dart';
import '../state/chat_message.dart';
import 'feedback_row.dart';
import 'frequent_questions.dart';
import 'message_bubble.dart';
import 'scroll_to_bottom_button.dart';

/// 바닥에서 이만큼 떨어져야 맨 아래로 버튼을 띄움 (살짝 올린 정도로는 띄우지 않음)
const double _scrollButtonDistance = 100;

/// 메시지 리스트: 웰컴 → FAQ → 대화, 스트리밍 시 하단 자동 스크롤 (웹 위젯과 동일)
class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.controller,
    required this.colors,
  });

  final ChatController controller;
  final GistChatbotColors colors;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _scrollController = ScrollController();
  String _scrollSignal = '';
  String? _lastUserMessageId;

  /// 하단 따라가기 여부. 사용자가 위로 스크롤하면 끄고, 바닥으로 돌아오면 다시 켬
  bool _follow = true;

  /// 맨 아래로 버튼 표시 여부. 스크롤할 때마다 리스트 전체가 다시 그려지지 않도록 따로 둠
  final ValueNotifier<bool> _showScrollButton = ValueNotifier(false);

  /// 맨 아래로 버튼의 스크롤 애니메이션 진행 여부
  bool _scrollingToBottom = false;

  /// 레이아웃 중 요청된 버튼 갱신이 다음 프레임으로 예약돼 있는지 여부
  bool _scrollButtonUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _lastUserMessageId = _findLastUserMessageId();
    widget.controller.addListener(_onUpdate);
    // 대화가 이미 있을 때 패널을 다시 열면 맨 아래에서 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    _scrollController.dispose();
    _showScrollButton.dispose();
    super.dispose();
  }

  String? _findLastUserMessageId() {
    // 가장 마지막 유저 메세지 찾기
    for (final m in widget.controller.messages.reversed) {
      if (m.role == MessageRole.user) return m.id;
    }
    return null;
  }

  /// 메시지 본문/로딩 변화에만 하단 스크롤.
  /// 피드백 등 메타 갱신 시 스크롤하면 화면이 튀므로 제외 (웹과 동일)
  void _onUpdate() {
    final signal = widget.controller.messages
        .map((m) => '${m.id}:${m.text.length}:${m.sources.length}')
        .join('|');
    if (signal == _scrollSignal) return;
    _scrollSignal = signal;

    // 사용자가 새 질문을 보내면 스크롤 위치와 관계없이 다시 따라감
    final lastUserMessageId = _findLastUserMessageId();
    final sentNewMessage = lastUserMessageId != _lastUserMessageId;
    _lastUserMessageId = lastUserMessageId;
    if (sentNewMessage) {
      _follow = true;
      _updateScrollButton();
    }
    if (!_follow) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 프레임 사이에 사용자가 스크롤을 시작했을 수 있으므로 다시 확인.
      // 맨 아래로 버튼 애니메이션 중에는 여기서 jumpTo하면 애니메이션이 끊기므로 건너뜀
      if (!mounted ||
          !_follow ||
          _scrollingToBottom ||
          !_scrollController.hasClients) {
        return;
      }
      final bottom = _scrollController.position.maxScrollExtent;
      if (sentNewMessage) {
        _scrollController.animateTo(
          bottom,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        // 스트리밍 토큰마다 animateTo를 걸면 애니메이션이 계속 재시작되므로 jumpTo
        _scrollController.jumpTo(bottom);
      }
    });
  }

  /// UserScrollNotification은 터치 드래그·휠 등 사용자 입력에서만 발생하고
  /// jumpTo/animateTo에서는 발생하지 않으므로 사용자 의도만 구분할 수 있음
  bool _onScrollNotification(ScrollNotification notification) {
    // 말풍선 안 가로 스크롤(표·코드 블록)도 읽는 중이므로 따라가기를 끔.
    // 바닥 복귀는 리스트 자체의 세로 스크롤로만 판단
    if (notification.depth != 0) {
      if (notification is UserScrollNotification &&
          notification.direction != ScrollDirection.idle) {
        _follow = false;
        _updateScrollButton();
      }
      return false;
    }
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward) {
      _follow = false;
    } else if (notification is ScrollEndNotification &&
        notification.metrics.extentAfter < 1) {
      _follow = true;
    }
    _updateScrollButton();
    return false;
  }

  /// ScrollNotification은 스크롤 위치가 바뀔 때만 옴.
  /// 위로 올려 둔 동안 아래에서 답변이 길어지면 위치는 그대로고 바닥까지 거리만 늘어나므로,
  /// 콘텐츠 길이 변화는 ScrollMetricsNotification으로 따로 받아 버튼 표시를 갱신
  bool _onScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _updateScrollButton();
    return false;
  }

  /// 따라가는 중에는 숨김: 스트리밍 중 바닥과 잠깐 벌어질 때 깜빡이지 않도록
  void _updateScrollButton() {
    // 관성 스크롤 중 콘텐츠 길이가 바뀌면 레이아웃 도중 스크롤 알림이 동기로 옴.
    // 이때 값을 바꾸면 빌드가 예약돼 "Build scheduled during frame" → 프레임이 끝난 뒤 반영
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_scrollButtonUpdateScheduled) return;
      _scrollButtonUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollButtonUpdateScheduled = false;
        if (mounted) _updateScrollButton();
      });
      return;
    }
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;
    _showScrollButton.value =
        !_follow && position.extentAfter > _scrollButtonDistance;
  }

  /// 맨 아래로 버튼: 멀리 있으면 바닥 한 화면 위까지 jumpTo 한 뒤 마지막 구간만 animateTo
  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) return;
    _follow = true;
    _updateScrollButton();

    final position = _scrollController.position;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scrollController.jumpTo(position.maxScrollExtent);
      return;
    }
    final viewport = position.viewportDimension;
    if (position.extentAfter > viewport * 2) {
      _scrollController.jumpTo(position.maxScrollExtent - viewport);
    }
    final target = position.maxScrollExtent;
    _scrollingToBottom = true;
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    _scrollingToBottom = false;

    // 애니메이션 목표는 시작 시점의 바닥이므로, 그사이 늘어난 답변만큼 마저 내려감.
    // 사용자가 터치해 중간에 멈췄으면(목표에 못 미침) 그대로 둠
    if (!mounted || !_follow || !_scrollController.hasClients) return;
    final end = _scrollController.position;
    if ((end.pixels - target).abs() < 1) {
      _scrollController.jumpTo(end.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final messages = controller.messages;

    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: _onScrollMetricsNotification,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isStreamingPlaceholder =
                    controller.loading &&
                    index == messages.length - 1 &&
                    message.role == MessageRole.assistant &&
                    message.text.isEmpty;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MessageBubble(
                      message: message,
                      colors: widget.colors,
                      isLoadingPlaceholder: isStreamingPlaceholder,
                      loadingMessage: controller.loadingMessage,
                    ),
                    // 서버에 저장된 assistant 답변에만 피드백 표시
                    if (message.role == MessageRole.assistant &&
                        message.serverId != null)
                      FeedbackRow(
                        message: message,
                        colors: widget.colors,
                        disabled:
                            controller.loading ||
                            controller.feedbackBusyId != null,
                        onFeedback: (rating) =>
                            controller.submitFeedback(message, rating),
                      ),
                    // 첫 번째 메시지 뒤에 자주 묻는 질문 표시
                    if (index == 0 && controller.showFrequentQuestions)
                      FrequentQuestionsSection(
                        colors: widget.colors,
                        onSelect: controller.sendMessage,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        // 입력창 위 가운데. 터치 영역(48px)이 보이는 버튼(36px)보다 6px씩 커서
        // bottom 6이면 입력창과 보이는 간격은 12px
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: _showScrollButton,
              builder: (context, visible, _) => ScrollToBottomButton(
                visible: visible,
                generating: controller.loading,
                colors: widget.colors,
                onTap: _scrollToBottom,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
