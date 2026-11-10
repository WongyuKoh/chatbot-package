import '../api/chat_api_types.dart';

export '../api/chat_api_types.dart'
    show
        ChatSource,
        ChatSourceKind,
        FeedbackRating,
        ResearchStep,
        ResearchStepStatus;

enum MessageRole { user, assistant }

/// 채팅 메시지 모델
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.sources = const [],
    this.steps = const [],
    this.serverId,
    this.feedback,
    this.regeneratedAnswer = false,
    this.regenerationUsed = false,
  });

  final String id;
  final MessageRole role;
  final String text;
  final List<ChatSource> sources;

  /// 이 답변을 만들며 거친 조사 단계. 단계 id는 질문마다 재사용되므로 메시지별로 둔다.
  final List<ResearchStep> steps;

  /// 백엔드에 저장된 메시지 ID (피드백/재생성 API 호출용)
  final String? serverId;

  /// 현재 저장된 피드백
  final FeedbackRating? feedback;

  /// 재생성으로 만들어진 답변 (다시 재생성 불가)
  final bool regeneratedAnswer;

  /// 이 답변의 재생성 기회를 이미 썼다 (재생성이 실패해 원본으로 되돌린 경우 포함)
  final bool regenerationUsed;

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? text,
    List<ChatSource>? sources,
    List<ResearchStep>? steps,
    String? serverId,
    FeedbackRating? feedback,
    bool? regeneratedAnswer,
    bool? regenerationUsed,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      sources: sources ?? this.sources,
      steps: steps ?? this.steps,
      serverId: serverId ?? this.serverId,
      feedback: feedback ?? this.feedback,
      regeneratedAnswer: regeneratedAnswer ?? this.regeneratedAnswer,
      regenerationUsed: regenerationUsed ?? this.regenerationUsed,
    );
  }
}
