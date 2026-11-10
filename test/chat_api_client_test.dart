import 'dart:async';
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
      await expectLater(
        send([
          '{"type":"step","id":"research","kind":"research","label":"찾는 중","status":"running"}',
          '{"error":"답변 생성 중 오류가 발생했습니다."}',
        ]),
        throwsA(
          isA<ChatStreamErrorException>()
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having((e) => e.message, 'message', '답변 생성 중 오류가 발생했습니다.'),
        ),
      );
    });

    test('nothing after an error event is applied', () async {
      final chunks = <String>[];
      await expectLater(
        streamClient([
          '{"content":"받다 만 "}',
          '{"error":"Failed to save message"}',
          '{"content":"늦은 조각"}',
          '[DONE]',
        ]).sendChatMessage(
          const SendChatRequest(question: 'q'),
          onChunk: chunks.add,
        ),
        throwsA(isA<ChatStreamErrorException>()),
      );
      expect(chunks, ['받다 만 ']);
    });

    test('each source event replaces the list of its own kind', () async {
      final response = await send([
        '{"type":"web_sources","sources":[{"kind":"web","id":"a","title":"a.example.com","url":"https://a.example.com/"}]}',
        '{"type":"web_sources","sources":[{"kind":"web","id":"b","title":"b.example.com","url":"https://b.example.com/"}]}',
        '[DONE]',
      ]);

      expect(response.sources.map((s) => s.url), ['https://b.example.com/']);
    });

    test('an encoded resource path is not encoded again', () async {
      final response = await send([
        '{"type":"resources","resources":[{"path":"학사 안내.pdf","formats":["pdf"],"url":"%ED%95%99%EC%82%AC%20%EC%95%88%EB%82%B4.pdf"},{"path":"no-url.pdf","formats":["pdf"]}]}',
        '[DONE]',
      ]);

      expect(response.sources, hasLength(1));
      expect(response.sources.single.title, '학사 안내.pdf');
      expect(
        response.sources.single.url,
        'https://rc.example.com/resource/%ED%95%99%EC%82%AC%20%EC%95%88%EB%82%B4.pdf',
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

    test('frames survive arbitrary network chunk boundaries', () async {
      final bytes = utf8.encode(
        'data: {"type":"step","id":"research","kind":"research","label":"자료를 찾고 있어요","status":"done"}\n\n'
        'data: {"content":"장학금 [공지 원문](https://ziggle.gistory.me/notice/42)을 "}\n\n'
        'data: {"content":"참고해 주세요."}\n\n'
        'data: [DONE]\n\n',
      );
      // 한글 한 글자(3바이트)·JSON·Markdown 링크가 모두 중간에서 잘리도록 2바이트씩 보낸다
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        client: _StreamClient(
          (_) => Stream.fromIterable([
            for (var i = 0; i < bytes.length; i += 2)
              bytes.sublist(i, i + 2 > bytes.length ? bytes.length : i + 2),
          ]),
        ),
      );

      final response = await send(client);

      expect(
        response.answer,
        '장학금 [공지 원문](https://ziggle.gistory.me/notice/42)을 참고해 주세요.',
      );
      expect(response.steps.single.label, '자료를 찾고 있어요');
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

  group('ChatApiClient cancellation', () {
    test(
      'stopping while waiting for the response aborts the request',
      () async {
        final sent = Completer<http.BaseRequest>();
        final client = ChatApiClient(
          baseUrl: 'https://api.example.com',
          // 첫 이벤트가 늦는 상황: 응답 헤더가 끝내 오지 않는다
          client: _StreamClient.pending(sent.complete),
        );
        final token = StreamCancelToken();

        final result = client.sendChatMessage(
          const SendChatRequest(question: 'q'),
          cancelToken: token,
        );
        final request = await sent.future;
        expect(request, isA<http.Abortable>());

        token.cancel();

        await expectLater(result, throwsA(isA<StreamCancelledException>()));
        // 실제 HTTP 클라이언트가 연결을 끊을 수 있도록 abort 신호가 요청에 실려 있다
        await expectLater((request as http.Abortable).abortTrigger, completes);
      },
    );

    test('a token cancelled before sending never sends', () async {
      var requests = 0;
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        client: _StreamClient((_) {
          requests++;
          return const Stream.empty();
        }),
      );
      final token = StreamCancelToken()..cancel();

      await expectLater(
        client.sendChatMessage(
          const SendChatRequest(question: 'q'),
          cancelToken: token,
        ),
        throwsA(isA<StreamCancelledException>()),
      );
      expect(requests, 0);
    });

    test('events after stopping are not applied', () async {
      final body = StreamController<List<int>>();
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        client: _StreamClient((_) => body.stream),
      );
      final token = StreamCancelToken();
      final chunks = <String>[];

      final result = client.sendChatMessage(
        const SendChatRequest(question: 'q'),
        onChunk: chunks.add,
        cancelToken: token,
      );
      body.add(utf8.encode('data: {"content":"받은 본문"}\n\n'));
      await pumpEventQueue();
      expect(chunks, ['받은 본문']);

      token.cancel();
      await expectLater(result, throwsA(isA<StreamCancelledException>()));

      // 구독이 끊겨 뒤따르는 이벤트는 전달되지 않는다
      expect(body.hasListener, isFalse);
      expect(chunks, ['받은 본문']);
    });
  });

  group('history', () {
    test('metadata restores steps and all three source kinds', () async {
      Uri? requested;
      final client = ChatApiClient(
        baseUrl: 'https://api.example.com',
        sessionToken: 'tok',
        client: _MockClient((request) async {
          requested = request.url;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'messages': [
                  {
                    'id': 'a-1',
                    'role': 'assistant',
                    'content': '저장된 답변 본문',
                    'metadata': {
                      'steps': [
                        {
                          'id': 'research',
                          'kind': 'research',
                          'label': '자료 2개를 모았어요',
                          'status': 'done',
                          'resultCount': 2,
                        },
                      ],
                      'resources': [
                        {
                          'path': 'guide.pdf',
                          'formats': ['pdf'],
                          'url': 'guide.pdf',
                        },
                      ],
                      'sources': [
                        {
                          'kind': 'notice',
                          'id': '42',
                          'title': '장학금 신청 안내',
                          'url': 'https://ziggle.gistory.me/notice/42',
                          'opened': true,
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
                      'regeneratedFromMessageId': 'a-0',
                      'model': 'some-model',
                      'evaluation': {'outcome': 'answered'},
                    },
                    'feedback': 'BAD',
                    'createdAt': '2026-11-03T00:00:00.000Z',
                  },
                  {'id': 'u-1', 'role': 'user', 'content': '질문'},
                ],
                'nextCursor': null,
              }),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final history = await client.getMessages(limit: 2);

      expect(requested!.path, '/v1/widget/messages');
      expect(requested!.queryParameters, {'limit': '2'});

      final answer = history.messages.first;
      expect(answer.isAssistant, isTrue);
      expect(answer.feedback, FeedbackRating.bad);
      final metadata = answer.metadata!;
      expect(metadata.steps!.single.status, ResearchStepStatus.done);
      expect(metadata.steps!.single.resultCount, 2);
      expect(metadata.regeneratedFromMessageId, 'a-0');

      final sources = metadata.resolveSources(
        resourceCenterUrl: 'https://rc.example.com',
      );
      expect(sources.map((s) => s.kind), [
        ChatSourceKind.document,
        ChatSourceKind.notice,
        ChatSourceKind.web,
      ]);
      expect(sources[0].url, 'https://rc.example.com/resource/guide.pdf');
      expect(sources[1].url, 'https://ziggle.gistory.me/notice/42');
      expect(sources[2].official, isTrue);

      // 사용자 메시지처럼 metadata가 없어도 본문은 읽힌다
      expect(history.messages[1].metadata, isNull);
      expect(history.messages[1].content, '질문');
    });

    test('missing metadata lists stay distinguishable from empty ones', () {
      final dto = ChatMessageDto.fromJson({
        'id': 'a-1',
        'role': 'assistant',
        'content': '본문',
        'metadata': {'model': 'm', 'webSources': <Object>[]},
      });

      expect(dto.metadata!.steps, isNull);
      expect(dto.metadata!.resources, isNull);
      expect(dto.metadata!.notices, isNull);
      expect(dto.metadata!.webSources, isEmpty);
      expect(dto.metadata!.hasSources, isTrue);
      expect(dto.metadata!.resolveSources(), isEmpty);
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

/// 응답 본문을 조각 단위 스트림으로 직접 주는 클라이언트
class _StreamClient extends http.BaseClient {
  _StreamClient(Stream<List<int>> Function(http.BaseRequest) body)
    : _body = body,
      _onSend = null;

  /// 응답 헤더가 오지 않는 클라이언트 (abort를 지원하지 않는 클라이언트처럼 동작)
  _StreamClient.pending(void Function(http.BaseRequest) onSend)
    : _body = null,
      _onSend = onSend;

  final Stream<List<int>> Function(http.BaseRequest)? _body;
  final void Function(http.BaseRequest)? _onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final body = _body;
    if (body == null) {
      _onSend!(request);
      return Completer<http.StreamedResponse>().future;
    }
    return Future.value(
      http.StreamedResponse(body(request), 200, headers: _sse),
    );
  }
}
