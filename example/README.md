# gist_chatbot_flutter_example

GIST 챗봇 Flutter 패키지 예시 앱입니다.

## 실행

위젯 키를 빌드 시점에 주입해 실행합니다:

```bash
flutter run --dart-define=GIST_CHATBOT_WIDGET_KEY=wk_live_xxx
```

키 없이 실행하면 안내 문구가 표시됩니다.

## 스테이징 서버로 실행

API 주소를 함께 주입하면 운영 대신 스테이징 서버에 붙습니다:

```bash
flutter run --dart-define-from-file=dart_defines.json --dart-define=GIST_CHATBOT_API_BASE_URL=https://api.stg.chatbot.gistory.me/api
```

화면 없이 SSE 응답만 확인하려면 패키지 루트에서 실행합니다 (질문 1회 소모):

```bash
dart run tool/staging_smoke.dart "질문"
```
