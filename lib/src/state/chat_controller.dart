import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/chat_api_client.dart';
import '../api/chat_api_types.dart' as api;
import '../app_id_resolver.dart';
import '../config/gist_chatbot_config.dart';
import '../session/session_manager.dart';
import 'chat_message.dart';

/// 조사 단계(step)가 오기 전까지 보여 주는 기본 로딩 문구.
/// 서버가 단계를 보내면 그 단계의 label로 대체된다.
const _loadingMessageInitial = '자료를 찾아보는 중';
const _loadingMessageReading = '파일을 읽어보는 중';
const _loadingMessageThinking = '조금 더 생각 중';
const _loadingMessageRegenerating = '답변을 다시 생성하는 중';

/// 받은 본문 뒤에 상태 안내(중지·미완료)를 기울임 문단으로 덧붙인다.
/// 기울임은 `*…*`로 쓴다. gpt_markdown은 1.3.3부터 `_…_`도 기울임으로 처리하지만
/// 이 패키지가 허용하는 그 이전 버전(1.1.8~)에서는 밑줄 문자가 그대로 보인다.
String _withNotice(String text, String notice) => '$text\n\n*($notice)*';

int _uidSeq = 0;

String _uid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_uidSeq++}';

/// 채팅 컨트롤러 (ChangeNotifier)
///
/// 웹 위젯(ChatWidget.tsx)과 동일한 대화 흐름을 제공한다:
/// 웰컴 메시지로 시작하고, 첫 전송 시 세션을 발급하며,
/// 스트리밍 중지/피드백/재생성/질문 한도 카운트다운을 지원한다.
class ChatController extends ChangeNotifier {
  ChatController({
    required GistChatbotConfig config,
    ChatApiClient? apiClient,
    SessionManager? sessionManager,
  }) : _config = config,
       _apiClient =
           apiClient ??
           ChatApiClient(
             baseUrl: config.apiBaseUrl,
             resourceCenterUrl: config.resourceCenterUrl,
             accessToken: config.accessToken,
           ),
       _sessionManager = sessionManager ?? SessionManager() {
    _messages.add(
      ChatMessage(id: _uid(), role: MessageRole.assistant, text: '무엇을 도와드릴까요?'),
    );
  }

  final GistChatbotConfig _config;
  final ChatApiClient _apiClient;
  final SessionManager _sessionManager;

  final List<ChatMessage> _messages = [];
  bool _loading = false;
  String _loadingMessage = _loadingMessageInitial;
  Timer? _loadingPhaseTimer1;
  Timer? _loadingPhaseTimer2;

  /// 진행 중인 요청의 중지 토큰. 요청마다 새로 만들어 요청 키로도 쓴다:
  /// 중지된 이전 요청의 늦은 콜백이 새 요청의 상태를 건드리지 않게 구분한다.
  StreamCancelToken? _cancelToken;
  String? _streamingMessageId;
  bool _disposed = false;

  /// 세션 질문 한도 소진(429 + limit) 시 재시도 가능 시각(ms). null이면 경고 없음
  int? _rateLimitRetryAt;

  /// 서버가 알려 준 세션 질문 한도 (배너 문구용)
  int? _questionLimit;

  /// 피드백 전송 중인 메시지 ID (중복 클릭 방지)
  String? _feedbackBusyId;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  String get loadingMessage => _loadingMessage;
  int? get rateLimitRetryAt => _rateLimitRetryAt;
  int? get questionLimit => _questionLimit;
  String? get feedbackBusyId => _feedbackBusyId;

  /// 자주 묻는 질문 표시 여부: 사용자가 한 번이라도 보내면 숨김 (웹과 동일)
  bool get showFrequentQuestions =>
      _messages.every((m) => m.role == MessageRole.assistant);

  /// 피드백 BAD 시 재생성 대상이 되는 최신 assistant 메시지 ID
  String? get latestFeedbackMessageId {
    if (_messages.isEmpty) return null;
    final last = _messages.last;
    return last.role == MessageRole.assistant ? last.id : null;
  }

  bool get canSend => !_loading;

  void _setLoading(bool value, {bool regenerating = false}) {
    _loading = value;
    _loadingPhaseTimer1?.cancel();
    _loadingPhaseTimer2?.cancel();
    if (value) {
      _loadingMessage = regenerating
          ? _loadingMessageRegenerating
          : _loadingMessageInitial;
      // 단계가 오지 않는 동안에만 시간에 따라 문구 변경 (3초/6초)
      _loadingPhaseTimer1 = Timer(const Duration(seconds: 3), () {
        _loadingMessage = _loadingMessageReading;
        notifyListeners();
      });
      _loadingPhaseTimer2 = Timer(const Duration(seconds: 6), () {
        _loadingMessage = _loadingMessageThinking;
        notifyListeners();
      });
    }
  }

  /// 닫힌 뒤 도착하는 응답(히스토리 조회 등)이 알림을 보내지 않게 한다
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// 요청이 끝났을 때 공유 상태를 정리한다. 이미 다른 요청이 시작됐다면 건드리지 않는다.
  void _endRequest(StreamCancelToken token) {
    if (!identical(_cancelToken, token)) return;
    _cancelToken = null;
    _streamingMessageId = null;
    _setLoading(false);
  }

  int _indexOf(String id) => _messages.indexWhere((m) => m.id == id);

  void _updateMessage(String id, ChatMessage Function(ChatMessage) update) {
    final idx = _indexOf(id);
    if (idx >= 0) {
      _messages[idx] = update(_messages[idx]);
      notifyListeners();
    }
  }

  /// 스트림이 보낸 조사 단계 스냅샷을 해당 답변에 반영한다.
  /// 실제 단계가 오면 타이머 기반 기본 문구를 멈추고 진행 중인 단계의 label을 쓴다.
  void _applySteps(String messageId, List<ResearchStep> steps) {
    if (steps.isEmpty || _streamingMessageId != messageId) return;
    _loadingPhaseTimer1?.cancel();
    _loadingPhaseTimer2?.cancel();
    final current = steps.lastWhere(
      (s) => s.status == ResearchStepStatus.running,
      orElse: () => steps.last,
    );
    _loadingMessage = current.label;
    _updateMessage(messageId, (m) => m.copyWith(steps: steps));
  }

  /// 아직 running으로 남은 단계를 닫는다 (완료·중지·오류 뒤에 로딩이 남지 않도록)
  void _settleSteps(String messageId, ResearchStepStatus status) {
    final idx = _indexOf(messageId);
    if (idx < 0) return;
    final message = _messages[idx];
    _messages[idx] = message.copyWith(
      steps: api.settleRunningSteps(message.steps, status),
    );
  }

  String? _resolvedAppId;

  Future<String> _ensureSession() async {
    var token = await _sessionManager.loadSession();
    if (token != null) {
      _apiClient.setSessionToken(token);
      return token;
    }
    final appId = await resolveAppId(_config.appId);
    _resolvedAppId = appId;
    final response = await _apiClient.createSession(
      api.CreateSessionRequest(widgetKey: _config.widgetKey, appId: appId),
    );
    _apiClient.setSessionToken(response.sessionToken);
    await _sessionManager.saveSession(
      response.sessionToken,
      response.expiresIn,
    );
    return response.sessionToken;
  }

  /// 다른 로컬 답변에 이미 연결된 서버 메시지인지
  bool _isAttachedElsewhere(String serverId, String localId) =>
      _messages.any((m) => m.serverId == serverId && m.id != localId);

  /// 저장된 답변의 ID·피드백·metadata(조사 단계, 출처)를 로컬 답변에 반영한다.
  /// [replaceText]는 스트림이 끊겨 본문을 끝까지 받지 못했을 때만 쓴다.
  void _adoptStored(
    String localId,
    api.ChatMessageDto stored, {
    bool replaceText = false,
    bool regenerated = false,
  }) {
    _updateMessage(localId, (m) {
      var next = m.copyWith(serverId: stored.id);
      if (stored.feedback != null) {
        next = next.copyWith(feedback: stored.feedback);
      }
      if (replaceText) next = next.copyWith(text: stored.content);
      final metadata = stored.metadata;
      if (metadata != null) {
        // 저장된 목록이 기준이다. 오래된 메시지처럼 키가 없으면 받은 값을 그대로 둔다
        if (metadata.hasSources) {
          next = next.copyWith(
            sources: metadata.resolveSources(
              resourceCenterUrl: _config.resourceCenterUrl,
            ),
          );
        }
        final steps = metadata.steps;
        if (steps != null) {
          next = next.copyWith(
            steps: api.settleRunningSteps(steps, ResearchStepStatus.stopped),
          );
        }
      }
      if (regenerated) next = next.copyWith(regeneratedAnswer: true);
      return next;
    });
  }

  /// [DONE] 뒤 히스토리를 조회해 저장된 메시지 ID와 metadata를 동기화한다.
  /// 스트림에는 메시지 ID가 없어서, ID를 얻기 전에는 피드백·재생성을 쓸 수 없다.
  Future<void> _syncWithHistory(
    String localId, {
    String? regeneratedFrom,
  }) async {
    try {
      final latest = await _apiClient.getLatestAssistantMessage();
      if (latest == null || latest.id.isEmpty) return;
      // 본문 없이 끝난 요청은 저장되지 않아 이전 답변이 최신으로 조회된다.
      // 그 답변의 ID를 이 답변에 붙이면 피드백이 엉뚱한 메시지로 간다
      if (latest.id == regeneratedFrom) return;
      if (_isAttachedElsewhere(latest.id, localId)) return;
      _adoptStored(localId, latest, regenerated: regeneratedFrom != null);
    } catch (e) {
      // 실패 시 해당 답변의 피드백 버튼만 표시되지 않음 (채팅에는 영향 없음)
      debugPrint('Failed to sync the answer with history: $e');
    }
  }

  /// HTTP 오류로 거절된 요청이 아니라면(스트림 오류, [DONE] 없는 종료, 연결 끊김)
  /// 서버가 질문·답변을 이미 저장했을 수 있다.
  bool _mayBeStored(Object e) =>
      !(e is ChatApiException && e.statusCode != null);

  /// 실패한 질문의 답변이 서버에 저장돼 있으면 그 답변으로 바꾼다.
  /// 저장 여부를 단정할 수 없으므로, 재전송(새 질문·횟수 소모) 전에 히스토리를 확인한다.
  /// 스트림에 메시지 ID가 없어 "맨 끝이 이 질문과 그 답변인가"로만 판단한다.
  Future<void> _recoverAnswer(String localId, String question) async {
    try {
      final messages = (await _apiClient.getMessages(limit: 2)).messages;
      if (messages.length < 2) return;
      final answer = messages[0];
      final asked = messages[1];
      if (!answer.isAssistant || answer.id.isEmpty) return;
      if (asked.role != 'user' || asked.content.trim() != question) return;
      if (_isAttachedElsewhere(answer.id, localId)) return;
      _adoptStored(localId, answer, replaceText: true);
    } catch (e) {
      debugPrint('Failed to check history after a stream failure: $e');
    }
  }

  /// 실패한 재생성의 결과가 서버에 저장돼 있으면 그 답변을 보여 준다.
  /// 재생성 기회는 스트림 시작 전에 선점되므로 같은 요청을 다시 보내지 않고 히스토리만 확인한다.
  Future<void> _recoverRegeneration({
    required String originalId,
    required String regenId,
    required String originalServerId,
  }) async {
    try {
      final latest = await _apiClient.getLatestAssistantMessage();
      if (latest == null || latest.id.isEmpty) return;
      if (latest.metadata?.regeneratedFromMessageId != originalServerId) return;
      var idx = _indexOf(regenId);
      if (idx < 0) idx = _indexOf(originalId);
      if (idx < 0) return;
      _messages[idx] = ChatMessage(
        id: regenId,
        role: MessageRole.assistant,
        text: latest.content,
        regeneratedAnswer: true,
      );
      _adoptStored(regenId, latest, replaceText: true, regenerated: true);
    } catch (e) {
      debugPrint('Failed to check history after a failed regeneration: $e');
    }
  }

  /// 메시지 전송
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loading) return;

    _rateLimitRetryAt = null;
    _questionLimit = null;
    _messages.add(
      ChatMessage(id: _uid(), role: MessageRole.user, text: trimmed),
    );
    _setLoading(true);
    notifyListeners();

    final assistantId = _uid();
    _messages.add(
      ChatMessage(id: assistantId, role: MessageRole.assistant, text: ''),
    );
    _streamingMessageId = assistantId;
    notifyListeners();

    // 세션 발급을 기다리는 동안에도 중지할 수 있도록 토큰을 먼저 만든다
    final cancelToken = StreamCancelToken();
    _cancelToken = cancelToken;

    // 세션 발급 단계의 400/403/404는 위젯 설정 오류, 그 뒤는 질문 요청의 오류다
    var sessionReady = false;
    try {
      await _ensureSession();
      sessionReady = true;
      // 그 사이 중지했다면 질문을 보내지 않는다 (보내면 저장되고 횟수도 쓴다)
      if (cancelToken.isCancelled) throw StreamCancelledException();

      final response = await _apiClient.sendChatMessage(
        api.SendChatRequest(question: trimmed),
        onChunk: (streamedText) {
          if (cancelToken.isCancelled) return;
          _updateMessage(assistantId, (m) => m.copyWith(text: streamedText));
        },
        onSteps: (steps) {
          if (cancelToken.isCancelled) return;
          _applySteps(assistantId, steps);
        },
        cancelToken: cancelToken,
      );
      if (cancelToken.isCancelled) return;

      _endRequest(cancelToken);
      _updateMessage(
        assistantId,
        (m) => m.copyWith(
          text: response.answer,
          sources: response.sources,
          steps: api.settleRunningSteps(
            response.steps,
            ResearchStepStatus.stopped,
          ),
        ),
      );
      notifyListeners();

      await _syncWithHistory(assistantId);
    } catch (e) {
      // 사용자가 중지한 요청: stopStreaming()이 화면을 이미 정리했고 그 사이
      // 새 요청이 시작됐을 수 있으므로 여기서는 아무 상태도 건드리지 않는다
      if (cancelToken.isCancelled) return;

      _endRequest(cancelToken);
      _settleSteps(assistantId, ResearchStepStatus.failed);
      _handleStreamError(e, assistantId, duringSessionSetup: !sessionReady);
      notifyListeners();

      if (sessionReady && _mayBeStored(e)) {
        await _recoverAnswer(assistantId, trimmed);
      }
    }
  }

  /// BAD 피드백 답변 1회 재생성 (웹과 동일: 원본 답변 자리에서 스트리밍)
  Future<void> _regenerateAnswer(ChatMessage originalMsg) async {
    final serverId = originalMsg.serverId;
    if (serverId == null || _loading) return;

    final regenId = _uid();
    final idx = _indexOf(originalMsg.id);
    if (idx < 0) return;
    _messages[idx] = ChatMessage(
      id: regenId,
      role: MessageRole.assistant,
      text: '',
      regeneratedAnswer: true,
    );
    _streamingMessageId = regenId;
    _setLoading(true, regenerating: true);
    notifyListeners();

    final cancelToken = StreamCancelToken();
    _cancelToken = cancelToken;
    try {
      final response = await _apiClient.regenerateAnswer(
        serverId,
        onChunk: (streamedText) {
          if (cancelToken.isCancelled) return;
          _updateMessage(regenId, (m) => m.copyWith(text: streamedText));
        },
        onSteps: (steps) {
          if (cancelToken.isCancelled) return;
          _applySteps(regenId, steps);
        },
        cancelToken: cancelToken,
      );
      if (cancelToken.isCancelled) return;

      _endRequest(cancelToken);
      _updateMessage(
        regenId,
        (m) => m.copyWith(
          text: response.answer,
          sources: response.sources,
          steps: api.settleRunningSteps(
            response.steps,
            ResearchStepStatus.stopped,
          ),
        ),
      );
      notifyListeners();

      // 재생성 답변은 원본을 덮어쓰지 않고 새 메시지로 저장된다
      await _syncWithHistory(regenId, regeneratedFrom: serverId);
    } catch (e) {
      // 사용자가 중지한 요청은 stopStreaming()이 이미 정리했다
      if (cancelToken.isCancelled) return;

      _endRequest(cancelToken);
      _settleSteps(regenId, ResearchStepStatus.failed);
      debugPrint('Failed to regenerate answer: $e');
      final sessionExpired = e is ChatApiException && e.statusCode == 401;
      if (sessionExpired) _dropSession();
      // 이미 받은 텍스트가 있으면 미완료로 표시해 유지, 없으면 원본 답변 복원.
      // 서버는 재생성 기회를 스트림 시작 전에 선점하고 실패해도 돌려주지 않을 수 있으므로
      // 복원한 원본에서 같은 재생성을 다시 시도하지 않게 막는다.
      final regenIdx = _indexOf(regenId);
      if (regenIdx >= 0) {
        final partial = _messages[regenIdx];
        _messages[regenIdx] = partial.text.isEmpty
            ? originalMsg.copyWith(regenerationUsed: true)
            : partial.copyWith(text: _markIncomplete(partial.text));
      }
      notifyListeners();

      // 자동으로 다시 요청하지 않고, 저장된 결과가 있는지 히스토리만 확인한다
      if (!sessionExpired) {
        await _recoverRegeneration(
          originalId: originalMsg.id,
          regenId: regenId,
          originalServerId: serverId,
        );
      }
    }
  }

  /// 답변 피드백 처리 (GOOD: 해결됨 / BAD: 해결 안 됨 + 1회 재생성)
  Future<void> submitFeedback(ChatMessage msg, FeedbackRating rating) async {
    if (msg.serverId == null || _loading || _feedbackBusyId != null) return;

    final canRegenerate =
        msg.id == latestFeedbackMessageId &&
        rating == FeedbackRating.bad &&
        !msg.regeneratedAnswer &&
        !msg.regenerationUsed;
    // 같은 피드백 재클릭: 재생성이 남아있는 BAD가 아니면 무시
    if (msg.feedback == rating && !canRegenerate) return;

    _feedbackBusyId = msg.id;
    notifyListeners();
    try {
      if (msg.feedback != rating) {
        await _apiClient.submitFeedback(msg.serverId!, rating);
        _updateMessage(msg.id, (m) => m.copyWith(feedback: rating));
      }
      if (canRegenerate) {
        final current = _messages[_indexOf(msg.id)];
        _feedbackBusyId = null;
        await _regenerateAnswer(current);
        return;
      }
    } catch (e) {
      debugPrint('Failed to submit feedback: $e');
    } finally {
      _feedbackBusyId = null;
      notifyListeners();
    }
  }

  /// 스트리밍 중지: 받은 텍스트는 유지하고 중지 안내를 덧붙인다 (웹과 동일).
  /// 요청을 abort하며, 그 뒤 도착하는 이벤트는 이 답변에 적용하지 않는다.
  /// 서버가 이미 저장한 질문·횟수는 되돌려지지 않는다.
  void stopStreaming() {
    final msgId = _streamingMessageId;
    _setLoading(false);
    if (msgId != null) {
      _updateMessage(msgId, (m) {
        final text = m.text.trim().isNotEmpty
            ? _withNotice(m.text, '응답이 중지되었습니다')
            : '응답이 중지되었습니다.';
        return m.copyWith(
          text: text,
          steps: api.settleRunningSteps(m.steps, ResearchStepStatus.stopped),
        );
      });
      _streamingMessageId = null;
    }
    _cancelToken?.cancel();
    _cancelToken = null;
    notifyListeners();
  }

  /// 서버에서 무효화된 세션 토큰을 버려 다음 전송에서 재발급받게 한다
  void _dropSession() {
    _apiClient.setSessionToken(null);
    _sessionManager.clearSession();
  }

  /// 끝까지 받지 못한 본문에 붙이는 안내 (중지 안내와 같은 형식)
  String _markIncomplete(String text) =>
      _withNotice(text, '응답이 끝까지 전달되지 않았습니다');

  void _handleStreamError(
    Object e,
    String assistantId, {
    required bool duringSessionSetup,
  }) {
    if (e is StreamCancelledException) return;

    // 위젯 키/앱 등록 설정 오류: 재시도해도 해결되지 않으므로 명확히 안내
    if (e is ChatApiException && duringSessionSetup && _isConfigError(e)) {
      _replaceWithError(assistantId, _configErrorMessage(e));
      debugPrint(
        'GistChatbot: session rejected (status ${e.statusCode}) - '
        '${e.message} (widgetKey: ${_config.widgetKey}, '
        'appId: ${_resolvedAppId ?? _config.appId ?? 'auto'})',
      );
      return;
    }

    // 세션이 서버에서 무효화된 경우: 저장된 토큰을 버려 다음 전송에서 재발급
    if (e is ChatApiException && e.statusCode == 401) {
      _dropSession();
      _replaceWithError(assistantId, '세션이 만료되었습니다. 다시 시도해주세요.');
      return;
    }

    if (e is ChatApiException && e.isQuestionLimit) {
      // 세션 질문 한도 소진: placeholder 제거 + 배너 카운트다운
      // (새 세션을 받을 수 있는 시각 = 현재 세션 만료)
      _messages.removeWhere((m) => m.id == assistantId);
      _questionLimit = e.limit;
      _sessionManager.expiresAt().then((retryAt) {
        if (retryAt != null) {
          _rateLimitRetryAt = retryAt;
          notifyListeners();
        }
      });
      return;
    }

    if (e is ChatApiException && e.isRateLimit) {
      // limit 없는 429: 동시 요청·빈도 제한. 재시도 시각을 알 수 없어 배너 없이 안내만 한다
      _replaceWithError(assistantId, '지금은 요청이 많습니다. 잠시 후 다시 시도해주세요.');
      return;
    }

    if (e is ChatApiException && e.statusCode == 400) {
      // 질문 요청 자체가 거절됨 (길이 초과 등). 같은 요청을 반복해도 해결되지 않는다
      _replaceWithError(assistantId, '질문을 처리할 수 없습니다. 입력 내용을 확인해주세요.');
      debugPrint('GistChatbot: question rejected - ${e.message}');
      return;
    }

    // 이미 일부 텍스트를 받았다면 미완료로 표시해 유지, 없으면 에러 문구로 교체.
    // 서버가 보낸 오류 문자열은 진단용으로만 쓴다.
    final idx = _indexOf(assistantId);
    if (idx >= 0) {
      final received = _messages[idx].text;
      _messages[idx] = _messages[idx].copyWith(
        text: received.isEmpty
            ? '죄송합니다. 응답을 받는 중 오류가 발생했습니다.'
            : _markIncomplete(received),
      );
    } else {
      _messages.add(
        ChatMessage(
          id: _uid(),
          role: MessageRole.assistant,
          text: '죄송합니다. 메시지를 전송하는 중 오류가 발생했습니다. 다시 시도해주세요.',
        ),
      );
    }
    debugPrint('Failed to send chat message: $e');
  }

  bool _isConfigError(ChatApiException e) =>
      e.statusCode == 400 || e.statusCode == 403 || e.statusCode == 404;

  String _configErrorMessage(ChatApiException e) {
    switch (e.statusCode) {
      case 404:
        return '위젯 키가 유효하지 않습니다. 앱 설정을 확인해주세요.';
      case 403:
        return '이 앱은 챗봇 서비스에 등록되어 있지 않습니다. 관리자에게 문의해주세요.';
      default:
        return '챗봇 설정이 올바르지 않습니다. 앱 설정을 확인해주세요.';
    }
  }

  /// placeholder 답변을 에러 안내 문구로 교체
  void _replaceWithError(String assistantId, String message) {
    final idx = _indexOf(assistantId);
    if (idx >= 0) {
      _messages[idx] = _messages[idx].copyWith(text: message);
    } else {
      _messages.add(
        ChatMessage(id: _uid(), role: MessageRole.assistant, text: message),
      );
    }
  }

  /// 429 카운트다운 종료 시 배너 해제
  void clearRateLimitWarning() {
    if (_rateLimitRetryAt == null) return;
    _rateLimitRetryAt = null;
    _questionLimit = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadingPhaseTimer1?.cancel();
    _loadingPhaseTimer2?.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }
}
