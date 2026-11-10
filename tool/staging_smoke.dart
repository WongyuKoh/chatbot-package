// 스테이징 서버에 실제로 질문을 보내 SSE 계약(조사 단계·출처·[DONE])을 확인한다.
//
//   dart run tool/staging_smoke.dart ["질문"]
//
// 위젯 키는 example/dart_defines.json 또는 환경 변수 GIST_CHATBOT_WIDGET_KEY에서 읽는다.
// 세션당 질문 한도를 1회 쓴다.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:gist_chatbot_flutter/src/api/chat_api_client.dart';
import 'package:gist_chatbot_flutter/src/api/chat_api_types.dart';

const _defaultBaseUrl = 'https://api.stg.chatbot.gistory.me/api';
const _defaultAppId = 'com.example.gistChatbotFlutterExample';

String? _define(String name) {
  final env = Platform.environment[name];
  if (env != null && env.isNotEmpty) return env;
  final file = File('example/dart_defines.json');
  if (!file.existsSync()) return null;
  final value = (jsonDecode(file.readAsStringSync()) as Map)[name];
  return value is String && value.isNotEmpty ? value : null;
}

Future<void> main(List<String> args) async {
  final widgetKey = _define('GIST_CHATBOT_WIDGET_KEY');
  if (widgetKey == null) {
    stderr.writeln('GIST_CHATBOT_WIDGET_KEY가 없습니다.');
    exit(64);
  }
  final baseUrl =
      Platform.environment['GIST_CHATBOT_API_BASE_URL'] ?? _defaultBaseUrl;
  final appId = _define('GIST_CHATBOT_APP_ID') ?? _defaultAppId;
  final question = args.isNotEmpty ? args.join(' ') : '이번 학기 장학금 신청 공지 알려줘';

  final client = ChatApiClient(baseUrl: baseUrl);
  print('서버: $baseUrl');

  final session = await client.createSession(
    CreateSessionRequest(widgetKey: widgetKey, appId: appId),
  );
  client.setSessionToken(session.sessionToken);
  print('세션 발급: expiresIn=${session.expiresIn}s');

  // 한도를 넘는 질문은 스트림을 열기 전에 400으로 거절되어야 한다 (질문 횟수 미소모)
  try {
    await client.sendChatMessage(
      SendChatRequest(question: 'a' * (SendChatRequest.maxQuestionLength + 1)),
    );
    print('!! 4,001자 질문이 거절되지 않았습니다');
    exitCode = 1;
  } on ChatApiException catch (e) {
    print('4,001자 질문 → ${e.statusCode} ${e.message}');
    if (e.statusCode != 400) exitCode = 1;
  }

  print('\n질문: $question');
  final watch = Stopwatch()..start();
  String stamp() => (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
  var chunks = 0;
  var lastSteps = '';
  try {
    final response = await client.sendChatMessage(
      SendChatRequest(question: question),
      onChunk: (text) {
        if (chunks++ == 0) print('[${stamp()}s] 본문 시작');
      },
      onSteps: (steps) {
        final line = steps
            .map(
              (s) =>
                  '${s.id}/${s.kind}:${s.status.name}'
                  '${s.resultCount == null ? '' : '(${s.resultCount})'}',
            )
            .join(' ');
        if (line == lastSteps) return;
        lastSteps = line;
        final latest = steps.last;
        print('[${stamp()}s] 단계 $line');
        print(
          '         └ "${latest.label}"'
          '${latest.thought == null ? '' : ' / thought: "${latest.thought}"'}',
        );
      },
    );
    print('[${stamp()}s] [DONE] 본문 조각 $chunks개, ${response.answer.length}자');
    print('\n--- 답변 ---\n${response.answer}\n');
    print('--- 단계 ${response.steps.length}개 ---');
    for (final s in response.steps) {
      print('  ${s.status.name.padRight(7)} ${s.kind.padRight(16)} ${s.label}');
    }
    print('--- 출처 ${response.sources.length}개 ---');
    for (final s in response.sources) {
      print('  ${s.kind.name}${s.official ? '(공식)' : ''} ${s.title} ${s.url}');
    }
  } on ChatApiException catch (e) {
    print(
      '[${stamp()}s] 실패: ${e.runtimeType} ${e.statusCode} ${e.message} '
      '(limit=${e.limit})',
    );
    exitCode = 1;
  }

  final latest = await client.getLatestAssistantMessage();
  print('\n저장된 최신 답변: id=${latest?.id} (${latest?.content.length}자)');
  exit(exitCode);
}
