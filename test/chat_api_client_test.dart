import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gist_chatbot_flutter/src/api/chat_api_client.dart';
import 'package:gist_chatbot_flutter/src/api/chat_api_types.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ChatApiClient', () {
    test('createSession returns session on success', () async {
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        client: _MockClient(
          (_) async =>
              http.Response('{"sessionToken":"tok","expiresIn":3600}', 200),
        ),
      );

      final response = await client.createSession(
        const CreateSessionRequest(widgetKey: 'wk', appId: 'com.example.app'),
      );

      expect(response.sessionToken, 'tok');
      expect(response.expiresIn, 3600);
    });

    test('createSession surfaces the server message for a bad key', () async {
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        client: _MockClient(
          (_) async => http.Response(
            '{"message":"Widget key not found","error":"Not Found","statusCode":404}',
            404,
          ),
        ),
      );

      try {
        await client.createSession(
          const CreateSessionRequest(widgetKey: 'wk_bad', appId: 'com.a.b'),
        );
        fail('should throw');
      } on ChatApiException catch (e) {
        expect(e.statusCode, 404);
        expect(e.message, 'Widget key not found');
      }
    });

    test('createSession parses array validation messages', () async {
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        client: _MockClient(
          (_) async => http.Response(
            '{"statusCode":400,"message":["widgetKey should not be empty"],"error":"Bad Request"}',
            400,
          ),
        ),
      );

      try {
        await client.createSession(
          const CreateSessionRequest(widgetKey: '', appId: 'com.a.b'),
        );
        fail('should throw');
      } on ChatApiException catch (e) {
        expect(e.statusCode, 400);
        expect(e.message, 'widgetKey should not be empty');
      }
    });

    test('createSession throws on error', () async {
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        client: _MockClient((_) async => http.Response('error', 500)),
      );

      expect(
        () => client.createSession(
          const CreateSessionRequest(widgetKey: 'wk', appId: 'com.example.app'),
        ),
        throwsA(isA<ChatApiException>()),
      );
    });
  });

  group('ChatApiClient stream events', () {
    ChatApiClient streamClient(List<String> frames) => ChatApiClient(
      baseUrl: 'https://api.example.com',
      resourceCenterUrl: 'https://rc.example.com',
      client: _MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(frames.map((f) => 'data: $f\n\n').join()),
          200,
          headers: _sse,
        ),
      ),
    );

    Future<SendChatResponse> send(
      List<String> frames, {
      void Function(List<ResearchStep>)? onSteps,
    }) => streamClient(
      frames,
    ).sendChatMessage(const SendChatRequest(question: 'q'), onSteps: onSteps);

    test('step events update the same id and keep first-seen order', () async {
      final snapshots = <List<ResearchStep>>[];
      final response = await send([
        '{"type":"step","id":"research","kind":"research","label":"자료를 더 찾아보고 있어요","status":"running"}',
        '{"type":"step","id":"r1_call_1","kind":"search_notices","label":"Ziggle 공지를 찾고 있어요","status":"running","thought":"신청 기간을 확인할게요"}',
        '{"type":"step","id":"r1_call_1","kind":"search_notices","label":"Ziggle 공지 3개를 불러왔어요","status":"done","thought":"신청 기간을 확인할게요","resultCount":3}',
        '{"type":"step","id":"research","kind":"research","label":"자료 3개를 모았어요","status":"done","resultCount":3}',
        '{"content":"답변"}',
        '[DONE]',
      ], onSteps: snapshots.add);

      expect(snapshots.map((s) => s.length), [1, 2, 2, 2]);
      expect(response.answer, '답변');
      expect(response.steps.map((s) => s.id), ['research', 'r1_call_1']);

      final research = response.steps[0];
      expect(research.status, ResearchStepStatus.done);
      expect(research.label, '자료 3개를 모았어요');
      expect(research.thought, isNull);

      final call = response.steps[1];
      expect(call.kind, 'search_notices');
      expect(call.status, ResearchStepStatus.done);
      expect(call.thought, '신청 기간을 확인할게요');
      expect(call.resultCount, 3);
    });

    test('malformed steps are skipped; resultCount 0 is kept', () async {
      final response = await send([
        '{"type":"step","id":"","label":"x","status":"running"}',
        '{"type":"step","id":"a","status":"running"}',
        '{"type":"step","id":"b","label":"x","status":"cancelled"}',
        '{"type":"step","id":"c","label":"결과 없음","status":"done","resultCount":0,"thought":"  "}',
        '[DONE]',
      ]);

      expect(response.steps, hasLength(1));
      expect(response.steps.single.id, 'c');
      expect(response.steps.single.kind, '');
      expect(response.steps.single.resultCount, 0);
      expect(response.steps.single.thought, isNull);
    });

    test('sources are ordered document, notice, web with the right URLs', () async {
      final response = await send([
        '{"content":"본문"}',
        '{"type":"resources","resources":[{"path":"guide.pdf","formats":["pdf"],"url":"guide.pdf"}]}',
        '{"type":"sources","sources":[{"kind":"notice","id":"42","title":"장학금 신청 안내","url":"https://ziggle.gistory.me/notice/42"}]}',
        '{"type":"web_sources","sources":[{"kind":"web","id":"w1","title":"www.gist.ac.kr","url":"https://www.gist.ac.kr/example","official":true},{"kind":"web","id":"w2","title":"blog.example.com","url":"https://blog.example.com/a"}]}',
        '[DONE]',
      ]);

      expect(response.sources.map((s) => s.kind), [
        ChatSourceKind.document,
        ChatSourceKind.notice,
        ChatSourceKind.web,
        ChatSourceKind.web,
      ]);
      // 내부 문서만 리소스 센터 경로로 조립하고, 공지·웹은 그대로 연다
      expect(
        response.sources[0].url,
        'https://rc.example.com/resource/guide.pdf',
      );
      expect(response.sources[1].url, 'https://ziggle.gistory.me/notice/42');
      expect(response.sources[1].title, '장학금 신청 안내');
      expect(response.sources[1].official, isFalse);
      expect(response.sources[2].official, isTrue);
      expect(response.sources[3].official, isFalse);
    });

    test('external sources drop unsafe URLs and duplicates', () async {
      final response = await send([
        '{"type":"sources","sources":[{"kind":"notice","id":"1","title":"A","url":"https://ziggle.gistory.me/notice/1"},{"kind":"notice","id":"1","title":"A","url":"https://ziggle.gistory.me/notice/1"},{"kind":"notice","id":"2","title":"B","url":"javascript:alert(1)"},{"kind":"notice","id":"3","title":"C","url":"notice/3"},{"kind":"notice","id":"4","title":"","url":"https://ziggle.gistory.me/notice/4"},"oops"]}',
        '[DONE]',
      ]);

      expect(response.sources.map((s) => s.url), [
        'https://ziggle.gistory.me/notice/1',
        'https://ziggle.gistory.me/notice/4',
      ]);
      // 제목이 비면 URL을 링크 문구로 쓴다
      expect(response.sources[1].title, 'https://ziggle.gistory.me/notice/4');
    });

    test('unknown event types are ignored', () async {
      final response = await send([
        '{"type":"future_event","content":"무시되어야 함","foo":1}',
        '{"content":"답변","extra":true}',
        '[DONE]',
      ]);

      expect(response.answer, '답변');
      expect(response.steps, isEmpty);
      expect(response.sources, isEmpty);
    });

    test('answers without steps or sources still complete', () async {
      final response = await send([
        '{"content":"안녕"}',
        '{"content":"하세요"}',
        '[DONE]',
      ]);

      expect(response.answer, '안녕하세요');
      expect(response.steps, isEmpty);
      expect(response.sources, isEmpty);
    });

    test('error event fails the stream after steps', () async {
      expect(
        () => send([
          '{"type":"step","id":"research","kind":"research","label":"찾는 중","status":"running"}',
          '{"error":"답변 생성 중 오류가 발생했습니다."}',
        ]),
        throwsA(isA<ChatApiException>()),
      );
    });
  });

  group('ChatApiClient stream failures', () {
    ChatApiClient rawClient(
      String body, {
      int status = 200,
      Map<String, String> headers = _sse,
    }) => ChatApiClient(
      baseUrl: 'https://api.example.com',
      client: _MockClient(
        (_) async =>
            http.Response.bytes(utf8.encode(body), status, headers: headers),
      ),
    );

    Future<SendChatResponse> send(ChatApiClient client) =>
        client.sendChatMessage(const SendChatRequest(question: 'q'));

    test('EOF without [DONE] is not a successful completion', () async {
      final chunks = <String>[];
      await expectLater(
        rawClient('data: {"content":"받다 만 답변"}\n\n').sendChatMessage(
          const SendChatRequest(question: 'q'),
          onChunk: chunks.add,
        ),
        throwsA(isA<ChatStreamIncompleteException>()),
      );
      // 받은 본문은 호출자에게 이미 전달되어 부분 답변으로 남길 수 있다
      expect(chunks, ['받다 만 답변']);
    });

    test('[DONE] without a trailing blank line still completes', () async {
      final response = await send(
        rawClient('data: {"content":"답변"}\n\ndata: [DONE]'),
      );
      expect(response.answer, '답변');
    });

    test('CRLF frames and data: without a space are parsed', () async {
      final response = await send(
        rawClient('data:{"content":"안녕"}\r\n\r\ndata: [DONE]\r\n\r\n'),
      );
      expect(response.answer, '안녕');
    });

    test('a malformed frame is a protocol error', () async {
      await expectLater(
        send(rawClient('data: {"content":"답\n\ndata: [DONE]\n\n')),
        throwsA(isA<ChatStreamProtocolException>()),
      );
    });

    test('a 200 response that is not SSE is a protocol error', () async {
      await expectLater(
        send(
          rawClient(
            '<html>gateway</html>',
            headers: {'content-type': 'text/html'},
          ),
        ),
        throwsA(isA<ChatStreamProtocolException>()),
      );
    });

    test('429 with limit is the session question limit', () async {
      try {
        await send(
          rawClient(
            '{"statusCode":429,"message":"이 세션에서는 최대 5개의 질문만 가능합니다.","limit":5}',
            status: 429,
            headers: {'content-type': 'application/json'},
          ),
        );
        fail('should throw');
      } on ChatApiException catch (e) {
        expect(e.statusCode, 429);
        expect(e.limit, 5);
        expect(e.isQuestionLimit, isTrue);
      }
    });

    test('429 without limit is a temporary throttle', () async {
      try {
        await send(
          rawClient(
            '{"statusCode":429,"message":"요청이 많습니다."}',
            status: 429,
            headers: {'content-type': 'application/json'},
          ),
        );
        fail('should throw');
      } on ChatApiException catch (e) {
        expect(e.isRateLimit, isTrue);
        expect(e.limit, isNull);
        expect(e.isQuestionLimit, isFalse);
      }
    });

    test('a non-JSON error body does not break error handling', () async {
      try {
        await send(rawClient('Bad Gateway', status: 502, headers: const {}));
        fail('should throw');
      } on ChatApiException catch (e) {
        expect(e.statusCode, 502);
        expect(e.message, 'Bad Gateway');
      }
    });
  });

  group('step helpers', () {
    const running = ResearchStep(
      id: 'a',
      kind: 'search_web',
      label: '검색 중',
      status: ResearchStepStatus.running,
    );
    const done = ResearchStep(
      id: 'b',
      kind: 'research',
      label: '완료',
      status: ResearchStepStatus.done,
    );

    test('settleRunningSteps closes only running steps', () {
      final settled = settleRunningSteps([
        running,
        done,
      ], ResearchStepStatus.stopped);

      expect(settled[0].status, ResearchStepStatus.stopped);
      expect(settled[0].label, '검색 중');
      expect(settled[1].status, ResearchStepStatus.done);
    });

    test('upsertStep does not mutate the input list', () {
      final original = [running];
      final next = upsertStep(
        original,
        running.withStatus(ResearchStepStatus.done),
      );

      expect(original.single.status, ResearchStepStatus.running);
      expect(next.single.status, ResearchStepStatus.done);
    });
  });
}

const _sse = {'content-type': 'text/event-stream'};

class _MockClient extends http.BaseClient {
  _MockClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
