import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gist_chatbot_flutter/src/api/chat_api_client.dart';
import 'package:gist_chatbot_flutter/src/api/chat_api_types.dart';
import 'package:gist_chatbot_flutter/src/config/gist_chatbot_config.dart';
import 'package:gist_chatbot_flutter/src/session/session_manager.dart';
import 'package:gist_chatbot_flutter/src/state/chat_controller.dart';
import 'package:gist_chatbot_flutter/src/state/chat_message.dart';

/// 스트림 이벤트(본문·조사 단계)와 종료 시점을 테스트에서 직접 흘려보내는 API 클라이언트
class _FakeApiClient extends Fake implements ChatApiClient {
  void Function(String text)? _onChunk;
  void Function(List<ResearchStep> steps)? _onSteps;
  Completer<SendChatResponse>? _response;
  List<ResearchStep> _steps = const [];
  String? regeneratedServerId;

  /// 보낸 질문 (재생성은 포함하지 않는다)
  final questions = <String>[];

  /// 가장 최근 요청의 중지 토큰
  StreamCancelToken? cancelToken;

  /// 서버에 저장된 히스토리 (최신순)
  List<ChatMessageDto> history = const [
    ChatMessageDto(id: 'server-1', role: 'assistant', content: ''),
  ];

  Future<SendChatResponse> _start(
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? token,
  ) {
    _onChunk = onChunk;
    _onSteps = onSteps;
    cancelToken = token;
    _steps = const [];
    _response = Completer();
    return _response!.future;
  }

  @override
  void setSessionToken(String? value) {}

  @override
  Future<SendChatResponse> sendChatMessage(
    SendChatRequest request, {
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? cancelToken,
  }) {
    questions.add(request.question);
    return _start(onChunk, onSteps, cancelToken);
  }

  @override
  Future<SendChatResponse> regenerateAnswer(
    String messageId, {
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? cancelToken,
  }) {
    regeneratedServerId = messageId;
    return _start(onChunk, onSteps, cancelToken);
  }

  @override
  Future<GetMessagesResponse> getMessages({
    String? cursor,
    int limit = 20,
  }) async => GetMessagesResponse(messages: history.take(limit).toList());

  @override
  Future<ChatMessageDto?> getLatestAssistantMessage() async {
    final latest = history.isEmpty ? null : history.first;
    return latest != null && latest.isAssistant ? latest : null;
  }

  @override
  Future<void> submitFeedback(String messageId, FeedbackRating rating) async {}

  void chunk(String text) => _onChunk!(text);

  /// 실제 클라이언트처럼 같은 id는 갱신한 전체 스냅샷을 넘긴다
  void step(
    String id,
    String label,
    ResearchStepStatus status, {
    String kind = 'research',
  }) {
    _steps = upsertStep(
      _steps,
      ResearchStep(id: id, kind: kind, label: label, status: status),
    );
    _onSteps!(_steps);
  }

  void finish(String answer, {List<ChatSource> sources = const []}) =>
      _response!.complete(
        SendChatResponse(answer: answer, sources: sources, steps: _steps),
      );

  void fail(Object error) => _response!.completeError(error);

  /// 진행 중인 요청의 응답. 다음 요청이 시작된 뒤에도 이 요청을 끝낼 수 있다.
  Completer<SendChatResponse> get pending => _response!;
}

class _FakeSessionManager extends Fake implements SessionManager {
  bool cleared = false;

  /// 설정하면 세션 확인이 이 시점까지 끝나지 않는다
  Completer<void>? gate;

  @override
  Future<String?> loadSession() async {
    await gate?.future;
    return 'session-token';
  }

  @override
  Future<int?> expiresAt() async => 1900000000000;

  @override
  Future<void> clearSession() async => cleared = true;
}

const _config = GistChatbotConfig(widgetKey: 'wk_test');

void main() {
  late _FakeApiClient api;
  late ChatController controller;
  late _FakeSessionManager session;

  /// 진행 중인 전송 (스트림이 끝나야 완료된다)
  late Future<void> sent;

  setUp(() {
    api = _FakeApiClient();
    session = _FakeSessionManager();
    controller = ChatController(
      config: _config,
      apiClient: api,
      sessionManager: session,
    );
  });

  tearDown(() => controller.dispose());

  /// 질문을 보내고 스트림이 열릴 때까지 기다린다
  Future<void> ask(String question) async {
    sent = controller.sendMessage(question);
    await pumpEventQueue();
  }

  ChatMessage answer() => controller.messages.last;

  group('ChatController research steps', () {
    test(
      'stores steps on the streaming answer and shows the running label',
      () async {
        await ask('장학금 신청 기간 알려줘');
        expect(controller.loadingMessage, '자료를 찾아보는 중');
        expect(answer().steps, isEmpty);

        api.step('research', '자료를 더 찾아보고 있어요', ResearchStepStatus.running);
        api.step(
          'r1_call_1',
          'Ziggle 공지를 찾고 있어요',
          ResearchStepStatus.running,
          kind: 'search_notices',
        );
        expect(answer().steps.map((s) => s.id), ['research', 'r1_call_1']);
        expect(controller.loadingMessage, 'Ziggle 공지를 찾고 있어요');

        // 하위 단계가 끝나면 아직 진행 중인 단계의 문구로 돌아간다
        api.step(
          'r1_call_1',
          'Ziggle 공지 3개를 불러왔어요',
          ResearchStepStatus.done,
          kind: 'search_notices',
        );
        expect(answer().steps, hasLength(2));
        expect(controller.loadingMessage, '자료를 더 찾아보고 있어요');

        api.step('research', '자료 3개를 모았어요', ResearchStepStatus.done);
        api.chunk('답변');
        api.finish('답변');
        await sent;

        expect(controller.loading, isFalse);
        expect(answer().text, '답변');
        expect(answer().steps.map((s) => s.label), [
          '자료 3개를 모았어요',
          'Ziggle 공지 3개를 불러왔어요',
        ]);
        expect(
          answer().steps.every((s) => s.status == ResearchStepStatus.done),
          isTrue,
        );
      },
    );

    test('keeps steps per answer when ids repeat across questions', () async {
      await ask('첫 질문');
      api.step('research', '첫 번째 조사', ResearchStepStatus.done);
      api.finish('첫 답변');
      await sent;
      final firstAnswerId = answer().id;

      await ask('두 번째 질문');
      api.step('research', '두 번째 조사', ResearchStepStatus.running);

      final firstAnswer = controller.messages.firstWhere(
        (m) => m.id == firstAnswerId,
      );
      expect(firstAnswer.steps.single.label, '첫 번째 조사');
      expect(firstAnswer.steps.single.status, ResearchStepStatus.done);
      expect(answer().steps.single.label, '두 번째 조사');

      api.finish('두 번째 답변');
      await sent;
    });

    test('answers without steps keep an empty list', () async {
      await ask('안녕');
      api.chunk('안녕하세요');
      api.finish('안녕하세요');
      await sent;

      expect(answer().text, '안녕하세요');
      expect(answer().steps, isEmpty);
    });

    test('closes steps left running when the stream completes', () async {
      await ask('질문');
      api.step('research', '찾는 중', ResearchStepStatus.running);
      api.finish('답변');
      await sent;

      expect(answer().steps.single.status, ResearchStepStatus.stopped);
    });

    test('stopping marks running steps as stopped', () async {
      await ask('질문');
      api.step('research', '찾는 중', ResearchStepStatus.running);
      api.step('call', '문서 검색 완료', ResearchStepStatus.done);

      controller.stopStreaming();
      api.fail(StreamCancelledException());
      await sent;

      expect(controller.loading, isFalse);
      expect(answer().text, '응답이 중지되었습니다.');
      expect(answer().steps.map((s) => s.status), [
        ResearchStepStatus.stopped,
        ResearchStepStatus.done,
      ]);
    });

    test('a stream error marks running steps as failed', () async {
      await ask('질문');
      api.step('research', '찾는 중', ResearchStepStatus.running);
      api.chunk('받다 만 답변');
      api.fail(ChatApiException('답변 생성 중 오류가 발생했습니다.'));
      await sent;

      expect(controller.loading, isFalse);
      // 받은 본문은 남기되 완성된 답변처럼 보이지 않게 한다
      expect(answer().text, '받다 만 답변\n\n*(응답이 끝까지 전달되지 않았습니다)*');
      expect(answer().steps.single.status, ResearchStepStatus.failed);
    });

    test('regeneration tracks its own steps', () async {
      await ask('질문');
      api.step('research', '처음 조사', ResearchStepStatus.done);
      api.finish('처음 답변');
      await sent;
      expect(answer().serverId, 'server-1');

      final regenerated = controller.submitFeedback(
        answer(),
        FeedbackRating.bad,
      );
      await pumpEventQueue();
      expect(api.regeneratedServerId, 'server-1');
      expect(controller.loadingMessage, '답변을 다시 생성하는 중');
      expect(answer().steps, isEmpty);

      api.step('research', '다시 조사', ResearchStepStatus.running);
      expect(controller.loadingMessage, '다시 조사');
      api.step('research', '다시 조사 완료', ResearchStepStatus.done);
      api.finish('새 답변');
      await regenerated;

      expect(answer().text, '새 답변');
      expect(answer().regeneratedAnswer, isTrue);
      expect(answer().steps.single.label, '다시 조사 완료');
    });

    test('a failed regeneration is not offered again', () async {
      await ask('질문');
      api.finish('처음 답변');
      await sent;

      final regenerated = controller.submitFeedback(
        answer(),
        FeedbackRating.bad,
      );
      await pumpEventQueue();
      api.fail(ChatApiException('답변 생성 중 오류가 발생했습니다.'));
      await regenerated;

      // 원본 답변으로 되돌아온다
      expect(controller.loading, isFalse);
      expect(answer().text, '처음 답변');
      expect(answer().regeneratedAnswer, isFalse);
      expect(answer().regenerationUsed, isTrue);

      // 서버가 재생성 기회를 이미 선점했으므로 BAD를 다시 눌러도 요청하지 않는다
      api.regeneratedServerId = null;
      await controller.submitFeedback(answer(), FeedbackRating.bad);
      expect(api.regeneratedServerId, isNull);
      expect(controller.loading, isFalse);
    });

    testWidgets('default loading phrases stop once a real step arrives', (
      tester,
    ) async {
      sent = controller.sendMessage('질문');
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(controller.loadingMessage, '파일을 읽어보는 중');

      api.step('research', '자료를 더 찾아보고 있어요', ResearchStepStatus.running);
      await tester.pump(const Duration(seconds: 10));
      expect(controller.loadingMessage, '자료를 더 찾아보고 있어요');

      api.finish('답변');
      await sent;
    });
  });

  group('ChatController stream errors', () {
    test('the question limit shows the banner instead of an answer', () async {
      await ask('여섯 번째 질문');
      api.fail(
        ChatApiException(
          '이 세션에서는 최대 5개의 질문만 가능합니다.',
          statusCode: 429,
          limit: 5,
        ),
      );
      await sent;
      await pumpEventQueue();

      expect(controller.rateLimitRetryAt, 1900000000000);
      expect(controller.questionLimit, 5);
      expect(answer().role, MessageRole.user);
    });

    test('a throttle 429 explains itself without the banner', () async {
      await ask('질문');
      api.fail(ChatApiException('요청이 많습니다.', statusCode: 429));
      await sent;
      await pumpEventQueue();

      expect(controller.rateLimitRetryAt, isNull);
      expect(answer().role, MessageRole.assistant);
      expect(answer().text, '지금은 요청이 많습니다. 잠시 후 다시 시도해주세요.');
    });

    test(
      'a rejected question is not reported as a widget key problem',
      () async {
        await ask('질문');
        api.fail(ChatApiException('question too long', statusCode: 400));
        await sent;

        expect(answer().text, '질문을 처리할 수 없습니다. 입력 내용을 확인해주세요.');
      },
    );

    test('a 404 on the stream is a general error', () async {
      await ask('질문');
      api.fail(ChatApiException('Not Found', statusCode: 404));
      await sent;

      expect(answer().text, '죄송합니다. 응답을 받는 중 오류가 발생했습니다.');
    });

    test('a stream that ends without [DONE] is shown as incomplete', () async {
      await ask('질문');
      api.chunk('받다 만 답변');
      api.fail(ChatStreamIncompleteException());
      await sent;

      expect(controller.loading, isFalse);
      expect(answer().text, endsWith('*(응답이 끝까지 전달되지 않았습니다)*'));
      // 저장 여부를 알 수 없으므로 피드백 대상으로 연결하지 않는다
      expect(answer().serverId, isNull);
    });

    test(
      'an expired session is dropped so the next send gets a new one',
      () async {
        await ask('질문');
        api.fail(ChatApiException('Unauthorized', statusCode: 401));
        await sent;

        expect(answer().text, '세션이 만료되었습니다. 다시 시도해주세요.');
        expect(session.cleared, isTrue);
      },
    );
  });

  group('ChatController stopping', () {
    test('stopping aborts the request', () async {
      await ask('질문');
      api.chunk('받은 본문');

      controller.stopStreaming();

      expect(api.cancelToken!.isCancelled, isTrue);
      expect(controller.loading, isFalse);
      expect(answer().text, '받은 본문\n\n*(응답이 중지되었습니다)*');
    });

    test('late events from a stopped request are ignored', () async {
      await ask('질문');
      api.chunk('받은 본문');
      controller.stopStreaming();
      final stopped = answer().text;

      // abort를 지원하지 않는 클라이언트라면 이벤트가 더 올 수 있다
      api.chunk('받은 본문 그리고 늦게 온 조각');
      api.step('research', '늦게 온 단계', ResearchStepStatus.running);
      api.finish('늦게 완성된 답변');
      await sent;

      expect(answer().text, stopped);
      expect(answer().steps, isEmpty);
      expect(answer().serverId, isNull);
    });

    test('a stopped request does not disturb the next one', () async {
      await ask('첫 질문');
      final first = api.pending;
      controller.stopStreaming();

      final firstSent = sent;
      await ask('두 번째 질문');
      expect(controller.loading, isTrue);

      // 이전 요청이 뒤늦게 끝나도 새 요청의 로딩·스트리밍 상태는 그대로다
      first.completeError(StreamCancelledException());
      await firstSent;
      expect(controller.loading, isTrue);

      api.chunk('두 번째 답변');
      expect(answer().text, '두 번째 답변');
      api.finish('두 번째 답변');
      await sent;
      expect(controller.loading, isFalse);
    });

    test(
      'stopping before the session is ready never sends the question',
      () async {
        session.gate = Completer();
        sent = controller.sendMessage('질문');
        await pumpEventQueue();

        controller.stopStreaming();
        session.gate!.complete();
        await sent;

        expect(api.questions, isEmpty);
        expect(controller.loading, isFalse);
        expect(answer().text, '응답이 중지되었습니다.');
      },
    );

    test('nothing is notified after dispose', () async {
      final local = ChatController(
        config: _config,
        apiClient: api,
        sessionManager: session,
      );
      var notified = 0;
      local.addListener(() => notified++);
      final pending = local.sendMessage('질문');
      await pumpEventQueue();
      final before = notified;

      local.dispose();
      expect(api.cancelToken!.isCancelled, isTrue);
      api.fail(StreamCancelledException());
      await pending;

      expect(notified, before);
    });
  });

  group('ChatController history sync', () {
    const notice = ChatSource(
      type: 'url',
      url: 'https://ziggle.gistory.me/notice/42',
      title: '장학금 신청 안내',
      kind: ChatSourceKind.notice,
    );

    ChatMessageDto stored(
      String id,
      String content, {
      Map<String, dynamic>? metadata,
      FeedbackRating? feedback,
    }) => ChatMessageDto(
      id: id,
      role: 'assistant',
      content: content,
      feedback: feedback,
      metadata: metadata == null
          ? null
          : ChatMessageMetadata.fromJson(metadata),
    );

    ChatMessageDto asked(String content) => ChatMessageDto(
      id: 'u-${content.hashCode}',
      role: 'user',
      content: content,
    );

    test('after [DONE] the stored id and metadata are attached', () async {
      await ask('질문');
      api.history = [
        stored(
          'a-1',
          '답변',
          metadata: {
            'steps': [
              {
                'id': 'research',
                'kind': 'research',
                'label': '자료 1개를 모았어요',
                'status': 'done',
                'resultCount': 1,
              },
            ],
            'webSources': [
              {
                'kind': 'web',
                'id': 'w',
                'title': 'www.gist.ac.kr',
                'url': 'https://www.gist.ac.kr/example',
                'official': true,
              },
            ],
          },
        ),
        asked('질문'),
      ];
      api.finish('답변');
      await sent;

      expect(answer().serverId, 'a-1');
      expect(answer().steps.single.label, '자료 1개를 모았어요');
      expect(answer().sources.single.kind, ChatSourceKind.web);
      expect(answer().sources.single.official, isTrue);
    });

    test('a stored message without metadata keeps what was streamed', () async {
      await ask('질문');
      api.step('research', '조사 완료', ResearchStepStatus.done);
      api.history = [stored('a-1', '답변'), asked('질문')];
      api.finish('답변', sources: const [notice]);
      await sent;

      expect(answer().serverId, 'a-1');
      expect(answer().sources.single.url, notice.url);
      expect(answer().steps.single.label, '조사 완료');
    });

    test(
      'an answer already attached elsewhere is not attached again',
      () async {
        await ask('첫 질문');
        api.history = [stored('a-1', '첫 답변'), asked('첫 질문')];
        api.finish('첫 답변');
        await sent;

        // 본문 없이 끝난 요청은 저장되지 않아 이전 답변이 그대로 최신이다
        await ask('두 번째 질문');
        api.finish('');
        await sent;

        expect(answer().serverId, isNull);
        expect(
          controller.messages.where((m) => m.serverId == 'a-1'),
          hasLength(1),
        );
      },
    );

    test(
      'a failed stream is replaced by the answer the server saved',
      () async {
        await ask('장학금 알려줘');
        api.step('research', '찾는 중', ResearchStepStatus.running);
        api.chunk('받다 만 ');
        api.history = [
          stored(
            'a-1',
            '저장된 완성 답변',
            metadata: {
              'sources': [
                {
                  'kind': 'notice',
                  'id': '42',
                  'title': notice.title,
                  'url': notice.url,
                },
              ],
            },
          ),
          asked('장학금 알려줘'),
        ];
        api.fail(ChatStreamErrorException('Failed to save message'));
        await sent;

        expect(answer().text, '저장된 완성 답변');
        expect(answer().serverId, 'a-1');
        expect(answer().sources.single.kind, ChatSourceKind.notice);
        expect(api.questions, ['장학금 알려줘']);
      },
    );

    test('a failed stream stays incomplete when nothing was saved', () async {
      await ask('두 번째 질문');
      api.chunk('받다 만 답변');
      // 맨 끝이 이전 질문의 답변이다: 이번 질문은 저장되지 않았다
      api.history = [stored('a-0', '이전 답변'), asked('이전 질문')];
      api.fail(ChatStreamIncompleteException());
      await sent;

      expect(answer().text, endsWith('*(응답이 끝까지 전달되지 않았습니다)*'));
      expect(answer().serverId, isNull);
      // 자동으로 다시 보내지 않는다
      expect(api.questions, ['두 번째 질문']);
    });

    test('a rejected request does not look at history', () async {
      await ask('질문');
      api.history = [stored('a-9', '다른 답변'), asked('질문')];
      api.fail(ChatApiException('요청이 많습니다.', statusCode: 429));
      await sent;

      expect(answer().text, '지금은 요청이 많습니다. 잠시 후 다시 시도해주세요.');
      expect(answer().serverId, isNull);
    });

    test('a failed regeneration shows the result the server saved', () async {
      await ask('질문');
      api.history = [stored('a-1', '처음 답변'), asked('질문')];
      api.finish('처음 답변');
      await sent;

      final regenerated = controller.submitFeedback(
        answer(),
        FeedbackRating.bad,
      );
      await pumpEventQueue();
      api.history = [
        stored(
          'a-2',
          '다시 만든 답변',
          metadata: {
            'regeneratedFromMessageId': 'a-1',
            'regeneratedFromFeedback': 'BAD',
          },
        ),
        ...api.history,
      ];
      api.fail(ChatStreamIncompleteException());
      await regenerated;

      expect(answer().text, '다시 만든 답변');
      expect(answer().serverId, 'a-2');
      expect(answer().regeneratedAnswer, isTrue);
      expect(controller.messages.where((m) => m.text == '처음 답변'), isEmpty);
    });
  });
}
