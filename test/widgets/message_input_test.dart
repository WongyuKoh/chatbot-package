import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gist_chatbot_flutter/src/config/gist_chatbot_config.dart';
import 'package:gist_chatbot_flutter/src/widgets/message_input.dart';

void main() {
  Future<List<String>> pumpInput(WidgetTester tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageInput(
            onSend: sent.add,
            onStop: () {},
            colors: const GistChatbotColors(),
          ),
        ),
      ),
    );
    return sent;
  }

  testWidgets('caps the question at the server limit', (tester) async {
    final sent = await pumpInput(tester);

    await tester.enterText(find.byType(TextField), 'a' * 4100);
    await tester.pump();
    expect(find.text('4000 / 4000'), findsOneWidget);

    await tester.tap(find.byTooltip('전송'));
    expect(sent.single.length, 4000);
  });

  testWidgets('hides the counter for ordinary questions', (tester) async {
    await pumpInput(tester);

    await tester.enterText(find.byType(TextField), '장학금 신청 기간 알려줘');
    await tester.pump();
    expect(find.textContaining('/ 4000'), findsNothing);
  });
}
