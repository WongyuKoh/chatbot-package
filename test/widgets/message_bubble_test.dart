import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gist_chatbot_flutter/src/config/gist_chatbot_config.dart';
import 'package:gist_chatbot_flutter/src/state/chat_message.dart';
import 'package:gist_chatbot_flutter/src/widgets/message_bubble.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

void main() {
  group('MessageBubble', () {
    const colors = GistChatbotColors();

    testWidgets('renders user message as plain text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: '1',
                role: MessageRole.user,
                text: 'Hello',
              ),
              colors: colors,
            ),
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
      expect(find.byType(GptMarkdown), findsNothing);
    });

    testWidgets('renders assistant message with markdown', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: '2',
                role: MessageRole.assistant,
                text: 'Hi there',
              ),
              colors: colors,
            ),
          ),
        ),
      );

      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('shows loading indicator while streaming placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: '3',
                role: MessageRole.assistant,
                text: '',
              ),
              colors: colors,
              isLoadingPlaceholder: true,
              loadingMessage: '자료를 찾아보는 중',
            ),
          ),
        ),
      );

      expect(find.text('자료를 찾아보는 중'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('MessageBubble research steps', () {
    const colors = GistChatbotColors();

    ResearchStep step(
      String id,
      String label,
      ResearchStepStatus status, {
      String kind = 'search_notices',
      String? thought,
      int? resultCount,
    }) => ResearchStep(
      id: id,
      kind: kind,
      label: label,
      status: status,
      thought: thought,
      resultCount: resultCount,
    );

    Future<void> pumpBubble(
      WidgetTester tester, {
      required List<ResearchStep> steps,
      String text = '',
      bool loading = false,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'a',
              role: MessageRole.assistant,
              text: text,
              steps: steps,
            ),
            colors: colors,
            isLoadingPlaceholder: loading,
            loadingMessage: '자료를 찾아보는 중',
          ),
        ),
      ),
    );

    testWidgets('shows live steps instead of the default loading phrase', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        loading: true,
        steps: [
          step(
            'research',
            '자료를 더 찾아보고 있어요',
            ResearchStepStatus.running,
            kind: 'research',
          ),
          step(
            'call_1',
            'Ziggle 공지를 찾고 있어요',
            ResearchStepStatus.running,
            thought: '신청 기간을 확인할게요.',
          ),
        ],
      );

      expect(find.text('자료를 찾아보는 중'), findsNothing);
      expect(find.text('자료를 더 찾아보고 있어요'), findsOneWidget);
      expect(find.text('Ziggle 공지를 찾고 있어요'), findsOneWidget);
      // 보조 문구는 끝 마침표를 떼고 보여 준다
      expect(find.text('신청 기간을 확인할게요'), findsOneWidget);
      expect(find.byType(GptMarkdown), findsNothing);
    });

    testWidgets('says the answer is being written once research is done', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        loading: true,
        steps: [
          step(
            'research',
            '자료 3개를 모았어요',
            ResearchStepStatus.done,
            kind: 'research',
          ),
          step('call_1', 'Ziggle 공지 3개를 불러왔어요', ResearchStepStatus.done),
        ],
      );

      expect(find.text('답변을 정리하고 있어요'), findsOneWidget);
      expect(find.text('Ziggle 공지 3개를 불러왔어요'), findsOneWidget);
    });

    testWidgets('collapses to a summary that expands on tap', (tester) async {
      await pumpBubble(
        tester,
        text: '답변입니다',
        steps: [
          step(
            'research',
            '자료 3개를 모았어요',
            ResearchStepStatus.done,
            kind: 'research',
            resultCount: 3,
          ),
          step('call_1', 'Ziggle 공지 3개를 불러왔어요', ResearchStepStatus.done),
        ],
      );

      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(find.text('자료 3개를 모았어요'), findsOneWidget);
      expect(find.text('Ziggle 공지 3개를 불러왔어요'), findsNothing);

      await tester.tap(find.text('자료 3개를 모았어요'));
      await tester.pumpAndSettle();
      expect(find.text('Ziggle 공지 3개를 불러왔어요'), findsOneWidget);

      await tester.tap(find.text('자료 3개를 모았어요'));
      await tester.pumpAndSettle();
      expect(find.text('Ziggle 공지 3개를 불러왔어요'), findsNothing);
    });

    testWidgets('a stop or incomplete notice renders as italics, not markers', (
      tester,
    ) async {
      // 상위 span의 스타일을 물려받은 결과로 기울임 여부를 본다
      bool hasItalic(InlineSpan span, String text, [TextStyle? inherited]) {
        if (span is! TextSpan) return false;
        final style = inherited?.merge(span.style) ?? span.style;
        if ((span.text ?? '').contains(text) &&
            style?.fontStyle == FontStyle.italic) {
          return true;
        }
        return (span.children ?? const <InlineSpan>[]).any(
          (child) => hasItalic(child, text, style),
        );
      }

      // 컨트롤러가 본문 뒤에 붙이는 형식 그대로
      for (final notice in ['응답이 중지되었습니다', '응답이 끝까지 전달되지 않았습니다']) {
        await pumpBubble(
          tester,
          steps: const [],
          text: '- **신청 기간**: 공지 참고\n\n*($notice)*',
        );

        final rendered = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((r) => r.text)
            .toList();
        // 기울임 표지(*, _)가 글자로 남지 않는다
        expect(
          rendered.map((span) => span.toPlainText()).join('\n'),
          isNot(anyOf(contains('*'), contains('_'))),
        );
        expect(
          rendered.any((span) => hasItalic(span, notice)),
          isTrue,
          reason: '"$notice" 안내가 기울임으로 보여야 한다',
        );
      }
    });

    testWidgets('summarises stopped and failed research in its own words', (
      tester,
    ) async {
      // 서버 label은 진행 중 문구 그대로 남으므로 그대로 쓰지 않는다
      await pumpBubble(
        tester,
        text: '응답이 중지되었습니다.',
        steps: [
          step(
            'research',
            '자료를 더 찾아보고 있어요',
            ResearchStepStatus.stopped,
            kind: 'research',
          ),
        ],
      );
      expect(find.text('자료 찾기를 중단했어요'), findsOneWidget);
      expect(find.text('자료를 더 찾아보고 있어요'), findsNothing);
      expect(find.bySemanticsLabel('중단됨'), findsOneWidget);

      await pumpBubble(
        tester,
        text: '받다 만 답변',
        steps: [
          step(
            'research',
            '자료를 더 찾아보고 있어요',
            ResearchStepStatus.failed,
            kind: 'research',
          ),
        ],
      );
      expect(find.text('자료를 더 찾지 못했어요'), findsOneWidget);
      expect(find.bySemanticsLabel('실패'), findsOneWidget);
    });
  });

  group('MessageBubble sources', () {
    const colors = GistChatbotColors();

    testWidgets('marks each source kind and flags non-official web sources', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: 's',
                role: MessageRole.assistant,
                text: '답변',
                sources: [
                  ChatSource(
                    type: 'url',
                    url: 'https://rc.example.com/resource/guide.pdf',
                    title: '학사 안내',
                  ),
                  ChatSource(
                    type: 'url',
                    url: 'https://ziggle.gistory.me/notice/42',
                    title: '장학금 신청 안내',
                    kind: ChatSourceKind.notice,
                  ),
                  ChatSource(
                    type: 'url',
                    url: 'https://www.gist.ac.kr/example',
                    title: 'www.gist.ac.kr',
                    kind: ChatSourceKind.web,
                    official: true,
                  ),
                  ChatSource(
                    type: 'url',
                    url: 'https://blog.example.com/a',
                    title: 'blog.example.com',
                    kind: ChatSourceKind.web,
                  ),
                ],
              ),
              colors: colors,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
      expect(find.byIcon(Icons.public), findsNWidgets(2));
      expect(find.text('gist.ac.kr'), findsOneWidget);
      // 공식 도메인이 아닌 웹 출처에만 외부 표시
      expect(find.text('외부'), findsOneWidget);

      expect(find.bySemanticsLabel('참고 문서: 학사 안내'), findsOneWidget);
      expect(find.bySemanticsLabel('Ziggle 공지: 장학금 신청 안내'), findsOneWidget);
      expect(find.bySemanticsLabel('학교 공식 웹 출처: gist.ac.kr'), findsOneWidget);
      expect(
        find.bySemanticsLabel('외부 웹 출처: blog.example.com'),
        findsOneWidget,
      );
    });
  });
}
