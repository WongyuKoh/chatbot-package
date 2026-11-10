import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'chat_api_endpoints.dart';
import 'chat_api_types.dart';

/// API 호출 예외
class ChatApiException implements Exception {
  ChatApiException(this.message, {this.statusCode, this.limit});

  final String message;
  final int? statusCode;

  /// 429 응답 본문의 `limit` (세션 질문 한도). 일시적 과부하 429에는 없다.
  final int? limit;

  bool get isRateLimit => statusCode == 429;

  /// 세션 질문 횟수를 다 쓴 429. `limit` 없는 429(동시 요청·빈도 제한)와 구분한다.
  bool get isQuestionLimit => isRateLimit && limit != null;

  @override
  String toString() => 'ChatApiException: $message (status: $statusCode)';
}

/// 스트리밍 중지용 토큰. 요청 하나에 하나씩 만들며, cancel()을 호출하면
/// 그 요청을 abort한다 (응답 헤더를 기다리는 중이든 스트림을 읽는 중이든).
class StreamCancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// cancel()이 호출되면 완료된다. 오류로 완료되지 않는다.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// 스트림이 계약대로 오지 않았을 때 (SSE가 아닌 200 응답, 깨진 프레임).
/// 정상 완료로 취급하지 않는다.
class ChatStreamProtocolException extends ChatApiException {
  ChatStreamProtocolException(super.message);
}

/// `[DONE]` 없이 스트림이 끝났을 때. 서버 저장 여부를 알 수 없는 비정상 중단이다.
class ChatStreamIncompleteException extends ChatApiException {
  ChatStreamIncompleteException() : super('Stream ended before [DONE]');
}

/// 스트림 도중 서버가 보낸 `error` 이벤트. 이 뒤로 `[DONE]`은 오지 않는다.
/// [message]는 코드가 아닌 진단용 문자열이므로 내용으로 분기하지 않는다.
class ChatStreamErrorException extends ChatApiException {
  ChatStreamErrorException(super.message);
}

/// HTTP 오류 응답을 예외로 바꾼다. 프록시 오류처럼 JSON이 아닌 본문도 올 수 있다.
ChatApiException _errorFromResponse(String body, int statusCode) {
  if (body.isEmpty) {
    return ChatApiException(
      'Request failed ($statusCode)',
      statusCode: statusCode,
    );
  }
  var message = body;
  int? limit;
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic>) {
      final msg = json['message'];
      // NestJS 검증 에러는 message가 문자열 배열로 온다
      if (msg is List) {
        message = msg.join(', ');
      } else if (msg is String && msg.isNotEmpty) {
        message = msg;
      }
      final rawLimit = json['limit'];
      if (rawLimit is num) limit = rawLimit.toInt();
    }
  } catch (_) {}
  return ChatApiException(message, statusCode: statusCode, limit: limit);
}

/// 처리하는 SSE 이벤트 type. 이 밖의 type은 무시한다.
const _knownEventTypes = {'step', 'resources', 'sources', 'web_sources'};

/// 채팅 API 클라이언트
class ChatApiClient {
  ChatApiClient({
    required String baseUrl,
    String? resourceCenterUrl,
    String? sessionToken,
    String? accessToken,
    http.Client? client,
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _resourceCenterUrl = resourceCenterUrl,
       _sessionToken = sessionToken,
       _accessToken = accessToken,
       _client = client ?? http.Client();

  final String _baseUrl;
  final String? _resourceCenterUrl;
  String? _sessionToken;
  final String? _accessToken;
  final http.Client _client;

  void setSessionToken(String? value) {
    _sessionToken = value;
  }

  String? get sessionToken => _sessionToken;

  Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{};
    // 본문 없이 Content-Type: application/json을 보내면 Fastify가 400을 반환함
    if (json) h['Content-Type'] = 'application/json';
    final token = _sessionToken ?? _accessToken;
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_baseUrl/$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  /// 세션 생성 (앱: clientType=app, appId)
  Future<CreateSessionResponse> createSession(
    CreateSessionRequest request,
  ) async {
    final response = await _client.post(
      _uri(ChatApiEndpoints.createSession),
      headers: _headers(),
      body: jsonEncode(request.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _errorFromResponse(response.body, response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CreateSessionResponse.fromJson(data);
  }

  /// 대화 내역 조회
  Future<GetMessagesResponse> getMessages({
    String? cursor,
    int limit = 20,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final response = await _client.get(
      _uri(ChatApiEndpoints.getMessages, query),
      headers: _headers(json: false),
    );

    if (response.statusCode != 200) {
      throw _errorFromResponse(response.body, response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return GetMessagesResponse.fromJson(data);
  }

  /// 가장 최근에 저장된 assistant 메시지 조회 (맨 끝 메시지가 답변일 때만).
  /// 스트리밍 응답에는 메시지 ID가 없으므로, 스트림 완료 직후 이 API로
  /// 서버 메시지 ID와 metadata를 얻어 피드백/재생성에 사용한다.
  Future<ChatMessageDto?> getLatestAssistantMessage() async {
    final res = await getMessages(limit: 1);
    final latest = res.messages.isNotEmpty ? res.messages.first : null;
    return latest != null && latest.isAssistant ? latest : null;
  }

  /// assistant 답변 피드백 등록/변경
  Future<void> submitFeedback(String messageId, FeedbackRating rating) async {
    final response = await _client.put(
      _uri(ChatApiEndpoints.feedback(messageId)),
      headers: _headers(),
      body: jsonEncode({'rating': rating.apiValue}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _errorFromResponse(response.body, response.statusCode);
    }
  }

  /// 채팅 메시지 전송 (스트리밍)
  Future<SendChatResponse> sendChatMessage(
    SendChatRequest request, {
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? cancelToken,
  }) {
    return _streamChatResponse(
      ChatApiEndpoints.sendChatStream,
      body: jsonEncode(request.toJson()),
      onChunk: onChunk,
      onSteps: onSteps,
      cancelToken: cancelToken,
    );
  }

  /// BAD 피드백 답변 1회 재생성 (스트리밍, 본문 없음)
  Future<SendChatResponse> regenerateAnswer(
    String messageId, {
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? cancelToken,
  }) {
    return _streamChatResponse(
      ChatApiEndpoints.regenerateStream(messageId),
      body: null,
      onChunk: onChunk,
      onSteps: onSteps,
      cancelToken: cancelToken,
    );
  }

  /// SSE 채팅 스트림 공통 처리 (웹 위젯의 streamWidgetChatResponse와 동일 규칙)
  ///
  /// HTTP 200은 스트리밍 시작일 뿐이고 `[DONE]`을 받아야 정상 완료다.
  /// 자동 재접속·재전송은 하지 않는다 (재전송은 새 질문으로 처리될 수 있다).
  Future<SendChatResponse> _streamChatResponse(
    String path, {
    String? body,
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled ?? false) throw StreamCancelledException();

    final req =
        http.AbortableRequest(
            'POST',
            _uri(path),
            abortTrigger: cancelToken?.whenCancelled,
          )
          ..headers.addAll(_headers(json: body != null))
          ..headers['Accept'] = 'text/event-stream';
    if (body != null) req.body = body;

    final streamedResponse = await _sendCancellable(req, cancelToken);

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw _errorFromResponse(errorBody, streamedResponse.statusCode);
    }

    // 200인데 SSE가 아니면 프록시 등이 끼어든 응답이라 파서에 넣지 않는다.
    // 헤더가 아예 없으면 그대로 읽되, [DONE]이 없으면 아래에서 미완료로 끝난다.
    final contentType = streamedResponse.headers['content-type'];
    if (contentType != null &&
        !contentType.toLowerCase().contains('text/event-stream')) {
      _discard(streamedResponse);
      throw ChatStreamProtocolException(
        'Expected text/event-stream but got $contentType',
      );
    }

    final completer = Completer<SendChatResponse>();
    var fullText = '';
    var resources = const <RawResource>[];
    var notices = const <ChatSource>[];
    var webSources = const <ChatSource>[];
    var steps = const <ResearchStep>[];

    void completeWith() {
      if (!completer.isCompleted) {
        completer.complete(
          SendChatResponse(
            answer: fullText,
            sources: combineSources(
              resources: resources,
              notices: notices,
              webSources: webSources,
              resourceCenterUrl: _resourceCenterUrl,
            ),
            steps: steps,
          ),
        );
      }
    }

    void failWith(Object error, [StackTrace? st]) {
      if (!completer.isCompleted) {
        completer.completeError(error, st);
      }
    }

    late final StreamSubscription<String> subscription;

    // 프레임은 빈 줄로 끝난다. 그때까지 온 data: 줄을 모아 한 번에 해석한다.
    final frame = <String>[];

    void handleFrame(String data) {
      // 완료·오류·중지로 요청이 끝난 뒤의 프레임은 적용하지 않는다
      if (completer.isCompleted) return;

      // [DONE]은 JSON이 아니므로 파싱보다 먼저 비교한다
      if (data == '[DONE]') {
        completeWith();
        subscription.cancel();
        return;
      }

      final Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        // 완성된 프레임의 JSON이 깨졌으면 정상 완료로 볼 수 없다
        failWith(ChatStreamProtocolException('Malformed SSE frame'));
        subscription.cancel();
        return;
      }

      // 아직 모르는 type의 이벤트는 통째로 무시한다
      final type = parsed['type'];
      if (type != null && !_knownEventTypes.contains(type)) return;

      // error에는 type이 없다. 받으면 실패로 끝내고 [DONE]을 기다리지 않는다
      final error = parsed['error'];
      if (error != null) {
        failWith(ChatStreamErrorException(error.toString()));
        subscription.cancel();
        return;
      }

      // content에도 type이 없다. 받은 순서대로 그대로 이어 붙인다
      final content = parsed['content'];
      if (content is String) {
        fullText += content;
        onChunk?.call(fullText);
      }

      switch (type) {
        case 'step':
          final step = ResearchStep.tryParse(parsed);
          if (step != null) {
            steps = upsertStep(steps, step);
            onSteps?.call(steps);
          }
        // 출처 이벤트는 올 때마다 해당 종류의 목록을 통째로 바꾼다
        case 'resources':
          resources = parseResources(parsed['resources']);
        case 'sources':
          notices = parseExternalSources(
            parsed['sources'],
            ChatSourceKind.notice,
          );
        case 'web_sources':
          webSources = parseExternalSources(
            parsed['sources'],
            ChatSourceKind.web,
          );
      }
    }

    // 네트워크 조각과 프레임 경계는 무관하다. 스트리밍 UTF-8 디코더로 한글 경계를
    // 보존하고, 줄 단위(LF/CRLF)로 다시 나눈 뒤 빈 줄에서 프레임을 닫는다.
    subscription = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.isEmpty) {
              if (frame.isEmpty) return;
              final data = frame.join('\n').trim();
              frame.clear();
              handleFrame(data);
            } else if (line.startsWith('data:')) {
              final value = line.substring(5);
              frame.add(value.startsWith(' ') ? value.substring(1) : value);
            }
            // event:, id:, retry:, 주석(:) 줄은 쓰지 않는다
          },
          onDone: () {
            // 마지막 빈 줄 없이 끝난 [DONE]만 완료로 인정하고,
            // 그 밖에 [DONE] 없이 끝난 스트림은 미완료로 처리한다
            if (frame.join('\n').trim() == '[DONE]') {
              completeWith();
            } else {
              failWith(ChatStreamIncompleteException());
            }
          },
          onError: (Object error, StackTrace st) {
            failWith(
              error is http.RequestAbortedException
                  ? StreamCancelledException()
                  : error,
              st,
            );
          },
          cancelOnError: true,
        );

    // 사용자 중지: 구독을 끊어 뒤따르는 이벤트가 이 요청에 적용되지 않게 한다
    if (cancelToken != null) {
      unawaited(
        cancelToken.whenCancelled.then((_) {
          if (completer.isCompleted) return;
          failWith(StreamCancelledException());
          subscription.cancel();
        }),
      );
    }

    return completer.future;
  }

  /// 요청을 보내고 응답 헤더를 기다린다. 첫 응답까지 오래 걸릴 수 있으므로
  /// 시간 제한은 두지 않고, 기다리는 동안에도 [cancelToken]으로 중지할 수 있게 한다.
  Future<http.StreamedResponse> _sendCancellable(
    http.BaseRequest request,
    StreamCancelToken? cancelToken,
  ) async {
    final pending = _client.send(request);
    if (cancelToken == null) return pending;

    // abort를 지원하지 않는 클라이언트라도 중지 즉시 호출자에게 돌려준다
    final response = await Future.any<http.StreamedResponse?>([
      pending,
      cancelToken.whenCancelled.then((_) => null),
    ]).onError<http.RequestAbortedException>((_, _) => null);

    if (response == null || cancelToken.isCancelled) {
      // 늦게 도착하는 응답이 연결을 붙잡지 않도록 버린다
      unawaited(pending.then(_discard, onError: (_) {}));
      throw StreamCancelledException();
    }
    return response;
  }

  /// 읽지 않을 응답 본문을 닫는다
  void _discard(http.StreamedResponse response) {
    unawaited(
      response.stream.listen(null, onError: (_) {}).cancel().catchError((_) {}),
    );
  }
}

/// 사용자가 스트리밍을 중지했을 때 발생
class StreamCancelledException implements Exception {}
