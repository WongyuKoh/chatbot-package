import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gist_chatbot_flutter/src/widgets/rate_limit_banner.dart';

void main() {
  testWidgets('clears an already expired banner after the frame', (
    tester,
  ) async {
    // 대기 시간이 지난 뒤 패널을 다시 열면 배너가 만료된 채로 생성됨
    var showBanner = true;
    late StateSetter setParentState;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setParentState = setState;
              return Column(
                children: [
                  if (showBanner)
                    RateLimitBanner(
                      retryAt: DateTime.now().millisecondsSinceEpoch - 1000,
                      onExpired: () => setParentState(() => showBanner = false),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(RateLimitBanner), findsNothing);
  });
}
