import 'package:flutter/material.dart';
import 'package:gist_chatbot_flutter/gist_chatbot_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GIST 챗봇 예시',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFDF3326)),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

/// 위젯 키는 소스에 넣지 않고 빌드 시점에 주입한다:
/// flutter run --dart-define=GIST_CHATBOT_WIDGET_KEY=wk_live_xxx
const _widgetKey = String.fromEnvironment('GIST_CHATBOT_WIDGET_KEY');

/// 스테이징 등 다른 서버로 붙을 때만 지정한다. 비우면 운영 서버를 쓴다:
/// --dart-define=GIST_CHATBOT_API_BASE_URL=https://api.stg.chatbot.gistory.me/api
const _apiBaseUrl = String.fromEnvironment('GIST_CHATBOT_API_BASE_URL');

class _MyHomePageState extends State<MyHomePage> {
  // 패키지는 트리거 UI를 제공하지 않는다.
  // 앱이 GistChatbot 인스턴스를 만들고, 원하는 위젯에서 open()을 호출한다.
  final _chatbot = _widgetKey.isEmpty
      ? null
      : GistChatbot(
          config: const GistChatbotConfig(
            widgetKey: _widgetKey,
            apiBaseUrl: _apiBaseUrl == '' ? kDefaultApiBaseUrl : _apiBaseUrl,
          ),
        );

  @override
  void dispose() {
    _chatbot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GIST 챗봇 예시'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _chatbot == null
                  ? '위젯 키가 설정되지 않았습니다.\n\nflutter run --dart-define=\nGIST_CHATBOT_WIDGET_KEY=wk_live_xxx\n로 실행해주세요.'
                  : '아래 버튼을 눌러 챗봇을 열어보세요',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _chatbot == null ? null : () => _chatbot.open(context),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('챗봇 열기'),
            ),
          ],
        ),
      ),
      floatingActionButton: _chatbot == null
          ? null
          : FloatingActionButton(
              onPressed: () => _chatbot.open(context),
              backgroundColor: const Color(0xFFDF3326),
              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
            ),
    );
  }
}
