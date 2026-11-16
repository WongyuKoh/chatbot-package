import 'package:flutter_test/flutter_test.dart';
import 'package:gist_chatbot_flutter/src/widgets/external_link.dart';

void main() {
  test('http(s) and mailto links are allowed', () {
    expect(
      safeExternalUri('https://ziggle.gistory.me/notice/42'),
      Uri.parse('https://ziggle.gistory.me/notice/42'),
    );
    expect(safeExternalUri(' http://www.gist.ac.kr/kr/ '), isNotNull);
    expect(safeExternalUri('mailto:help@gist.ac.kr'), isNotNull);
  });

  test('other schemes, relative paths and broken links are blocked', () {
    expect(safeExternalUri('javascript:alert(1)'), isNull);
    expect(safeExternalUri('intent://scan/#Intent;scheme=zxing;end'), isNull);
    expect(safeExternalUri('file:///etc/hosts'), isNull);
    expect(safeExternalUri('guide.pdf'), isNull);
    expect(safeExternalUri('https:///no-host'), isNull);
    expect(safeExternalUri('http://[broken'), isNull);
    expect(safeExternalUri(''), isNull);
  });
}
