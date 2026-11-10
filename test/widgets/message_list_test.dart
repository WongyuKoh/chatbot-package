import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gist_chatbot_flutter/src/api/chat_api_client.dart';
import 'package:gist_chatbot_flutter/src/api/chat_api_types.dart';
import 'package:gist_chatbot_flutter/src/config/gist_chatbot_config.dart';
import 'package:gist_chatbot_flutter/src/session/session_manager.dart';
import 'package:gist_chatbot_flutter/src/state/chat_controller.dart';
import 'package:gist_chatbot_flutter/src/widgets/chat_screen.dart';

/// 스트리밍 청크와 완료 시점을 테스트에서 직접 흘려보내는 API 클라이언트
class _FakeApiClient extends Fake implements ChatApiClient {
  void Function(String text)? _onChunk;
  void Function(List<ResearchStep> steps)? _onSteps;
  Completer<SendChatResponse>? _response;

  @override
  void setSessionToken(String? value) {}

  @override
  Future<SendChatResponse> sendChatMessage(
    SendChatRequest request, {
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? cancelToken,
  }) {
    _onChunk = onChunk;
    _onSteps = onSteps;
    _response = Completer();
    return _response!.future;
  }

  @override
  Future<ChatMessageDto?> getLatestAssistantMessage() async => latest;

  /// 답변 완료 뒤 붙는 서버 메시지 (있으면 피드백 줄이 나타남)
  ChatMessageDto? latest;

  void chunk(String text) => _onChunk!(text);

  void steps(List<ResearchStep> steps) => _onSteps!(steps);

  void finish(String answer) =>
      _response!.complete(SendChatResponse(answer: answer));
}

class _FakeSessionManager extends Fake implements SessionManager {
  @override
  Future<String?> loadSession() async => 'session-token';
}

const _config = GistChatbotConfig(widgetKey: 'wk_test');
const _tooltip = '맨 아래로 이동';
const _generatingLabel = '답변 작성 중';

/// 패널을 여러 화면 넘게 채우는 답변
String _longAnswer(int paragraphs) =>
    List.generate(paragraphs, (i) => '$i번째 문단입니다.').join('\n\n');

void main() {
  late _FakeApiClient api;
  late ChatController controller;

  setUp(() {
    api = _FakeApiClient();
    controller = ChatController(
      config: _config,
      apiClient: api,
      sessionManager: _FakeSessionManager(),
    );
  });

  tearDown(() => controller.dispose());

  Future<void> pumpChat(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatScreen(controller: controller, config: _config),
      ),
    ),
  );

  /// 질문을 보내고 답변 앞부분이 스트리밍된 상태로 만든다 (아직 생성 중)
  Future<void> askAndStream(WidgetTester tester) async {
    unawaited(controller.sendMessage('질문'));
    await tester.pump();
    api.chunk(_longAnswer(40));
    await tester.pumpAndSettle();
  }

  /// 위로 스크롤 (손가락을 아래로 끌기)
  Future<void> scrollUp(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
  }

  ScrollPosition listPosition(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!.position;

  group('ScrollToBottomButton in MessageList', () {
    testWidgets('appears after scrolling up and returns to the bottom on tap', (
      tester,
    ) async {
      await pumpChat(tester);
      await askAndStream(tester);
      api.finish(_longAnswer(40));
      await tester.pumpAndSettle();

      // 답변을 따라 바닥에 있는 동안은 숨김
      expect(find.byTooltip(_tooltip), findsNothing);

      await scrollUp(tester);
      expect(find.byTooltip(_tooltip), findsOneWidget);
      expect(find.text(_generatingLabel), findsNothing);

      await tester.tap(find.byTooltip(_tooltip));
      await tester.pumpAndSettle();
      final position = listPosition(tester);
      expect(position.pixels, position.maxScrollExtent);
      expect(find.byTooltip(_tooltip), findsNothing);
    });

    testWidgets('shows the generating label while the answer streams below', (
      tester,
    ) async {
      await pumpChat(tester);
      await askAndStream(tester);

      await scrollUp(tester);
      expect(find.text(_generatingLabel), findsOneWidget);

      // 위에서 읽는 동안 답변이 길어져도 화면을 끌어내리지 않음
      final position = listPosition(tester);
      final pixels = position.pixels;
      api.chunk(_longAnswer(60));
      await tester.pumpAndSettle();
      expect(position.pixels, pixels);
      expect(find.text(_generatingLabel), findsOneWidget);

      // 답변이 끝나면 평소의 원형 버튼으로 돌아감
      api.finish(_longAnswer(60));
      await tester.pumpAndSettle();
      expect(find.text(_generatingLabel), findsNothing);
      expect(find.byTooltip(_tooltip), findsOneWidget);
    });

    testWidgets('stays hidden while following a streaming answer', (
      tester,
    ) async {
      await pumpChat(tester);
      await askAndStream(tester);

      for (var paragraphs = 50; paragraphs <= 80; paragraphs += 10) {
        api.chunk(_longAnswer(paragraphs));
        await tester.pump();
        expect(find.byTooltip(_tooltip), findsNothing);
      }
      final position = listPosition(tester);
      expect(position.pixels, position.maxScrollExtent);

      api.finish(_longAnswer(80));
      await tester.pumpAndSettle();
    });

    testWidgets('follows research steps as they are added before the answer', (
      tester,
    ) async {
      List<ResearchStep> steps(int count) => [
        for (var i = 0; i < count; i++)
          ResearchStep(
            id: 'call_$i',
            kind: 'search_notices',
            label: 'Ziggle 공지 $i개를 불러왔어요',
            status: ResearchStepStatus.done,
            thought: '$i번째 검색입니다',
          ),
      ];

      await pumpChat(tester);
      unawaited(controller.sendMessage('질문'));
      await tester.pump();

      // 본문 없이 단계만 늘어나도 말풍선이 길어지므로 바닥을 따라가야 함
      for (final count in [10, 20, 30]) {
        api.steps(steps(count));
        // 로딩 표시가 계속 움직여 pumpAndSettle이 끝나지 않으므로 정해진 프레임만 돌린다
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final position = listPosition(tester);
        expect(position.maxScrollExtent, greaterThan(0));
        expect(position.pixels, position.maxScrollExtent);
      }

      api.finish('답변');
      await tester.pumpAndSettle();
    });

    testWidgets('follows the feedback row that appears after the answer', (
      tester,
    ) async {
      api.latest = const ChatMessageDto(
        id: 'server-1',
        role: 'assistant',
        content: '답변',
      );
      await pumpChat(tester);
      await askAndStream(tester);
      api.finish(_longAnswer(40));
      await tester.pumpAndSettle();

      // 본문은 그대로인데 피드백 줄만큼 길어져도 바닥에 붙어 있어야 함
      expect(find.text('답변이 도움이 되었나요?'), findsOneWidget);
      final position = listPosition(tester);
      expect(position.pixels, position.maxScrollExtent);
      expect(find.byTooltip(_tooltip), findsNothing);
    });

    testWidgets('keeps the reading position when late content is added above '
        'the bottom', (tester) async {
      api.latest = const ChatMessageDto(
        id: 'server-1',
        role: 'assistant',
        content: '답변',
      );
      await pumpChat(tester);
      await askAndStream(tester);
      await scrollUp(tester);
      final position = listPosition(tester);
      final pixels = position.pixels;

      // 위에서 읽는 중이면 피드백 줄이 붙어도 끌어내리지 않음
      api.finish(_longAnswer(40));
      await tester.pumpAndSettle();
      expect(find.text('답변이 도움이 되었나요?'), findsOneWidget);
      expect(position.pixels, pixels);
    });

    testWidgets('stops following when a code block is scrolled sideways', (
      tester,
    ) async {
      // 답변 끝에 화면보다 넓은 코드 블록을 둬서 바닥에서 가로로 밀 수 있게 함
      final withCode = '${_longAnswer(40)}\n\n```\n${'a' * 300}\n```';
      await pumpChat(tester);
      unawaited(controller.sendMessage('질문'));
      await tester.pump();
      api.chunk(withCode);
      await tester.pumpAndSettle();
      final position = listPosition(tester);
      expect(position.pixels, position.maxScrollExtent);

      final codeScroll = find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(codeScroll, findsOneWidget);
      await tester.drag(codeScroll, const Offset(-200, 0));
      await tester.pumpAndSettle();
      final codePosition = tester
          .state<ScrollableState>(
            find.descendant(of: codeScroll, matching: find.byType(Scrollable)),
          )
          .position;
      expect(codePosition.pixels, greaterThan(0));

      // 코드 블록을 보는 동안 답변이 길어져도 화면을 끌어내리지 않음
      final pixels = position.pixels;
      api.chunk('$withCode\n\n${_longAnswer(20)}');
      await tester.pumpAndSettle();
      expect(position.pixels, pixels);
      expect(find.text(_generatingLabel), findsOneWidget);

      api.finish('$withCode\n\n${_longAnswer(20)}');
      await tester.pumpAndSettle();
    });

    testWidgets('hides when the user sends another question', (tester) async {
      await pumpChat(tester);
      await askAndStream(tester);
      api.finish(_longAnswer(40));
      await tester.pumpAndSettle();

      await scrollUp(tester);
      expect(find.byTooltip(_tooltip), findsOneWidget);

      await askAndStream(tester);
      expect(find.byTooltip(_tooltip), findsNothing);
      final position = listPosition(tester);
      expect(position.pixels, position.maxScrollExtent);

      api.finish(_longAnswer(40));
      await tester.pumpAndSettle();
    });
  });
}
