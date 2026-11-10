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

/// 스트리밍 중지용 토큰. cancel() 호출 시 진행 중인 스트림 구독을 끊는다.
class StreamCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
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
      if (rawLimit is int) limit = rawLimit;
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

  /// 가장 최근에 저장된 assistant 메시지 조회.
  /// 스트리밍 응답에는 메시지 ID가 없으므로, 스트림 완료 직후 이 API로
  /// 서버 메시지 ID를 얻어 피드백/재생성에 사용한다.
  Future<ChatMessageDto?> getLatestAssistantMessage() async {
    final res = await getMessages(limit: 1);
    final latest = res.messages.isNotEmpty ? res.messages.first : null;
    return latest != null && latest.role == 'assistant' ? latest : null;
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
  Future<SendChatResponse> _streamChatResponse(
    String path, {
    String? body,
    void Function(String text)? onChunk,
    void Function(List<ResearchStep> steps)? onSteps,
    StreamCancelToken? cancelToken,
  }) async {
    final req = http.Request('POST', _uri(path))
      ..headers.addAll(_headers(json: body != null))
      ..headers['Accept'] = 'text/event-stream';
    if (body != null) req.body = body;

    final streamedResponse = await _client.send(req);

    if (streamedResponse.statusCode != 200) {
      final errorBody = await streamedResponse.stream.bytesToString();
      throw _errorFromResponse(errorBody, streamedResponse.statusCode);
    }

    // 200인데 SSE가 아니면 프록시 등이 끼어든 응답이라 파서에 넣지 않는다.
    // 헤더가 아예 없으면 그대로 읽되, [DONE]이 없으면 아래에서 미완료로 끝난다.
    final contentType = streamedResponse.headers['content-type'];
    if (contentType != null &&
        !contentType.toLowerCase().contains('text/event-stream')) {
      // 구독하지 않은 응답 스트림이 연결을 붙잡지 않도록 버린다
      unawaited(streamedResponse.stream.drain<void>().catchError((_) {}));
      throw ChatStreamProtocolException(
        'Expected text/event-stream but got $contentType',
      );
    }

    final completer = Completer<SendChatResponse>();
    var fullText = '';
    var resources = <RawResource>[];
    var notices = const <ChatSource>[];
    var webSources = const <ChatSource>[];
    var steps = const <ResearchStep>[];

    void completeWith() {
      if (!completer.isCompleted) {
        completer.complete(
          SendChatResponse(
            answer: fullText,
            sources: [
              for (final r in resources)
                resolveSource(r, resourceCenterUrl: _resourceCenterUrl),
              ...notices,
              ...webSources,
            ],
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

      final error = parsed['error'];
      if (error != null) {
        failWith(ChatApiException(error.toString()));
        subscription.cancel();
        return;
      }

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
        case 'resources':
          final raw = parsed['resources'];
          resources = raw is List
              ? raw
                    .whereType<Map<String, dynamic>>()
                    .map(RawResource.fromJson)
                    .toList()
              : [];
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
          onError: failWith,
          cancelOnError: true,
        );

    cancelToken?._onCancel = () {
      subscription.cancel();
      failWith(StreamCancelledException());
    };
    if (cancelToken?.isCancelled ?? false) {
      subscription.cancel();
      failWith(StreamCancelledException());
    }

    return completer.future;
  }
}

/// 사용자가 스트리밍을 중지했을 때 발생
class StreamCancelledException implements Exception {}
