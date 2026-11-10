/// 앱용 세션 발급 요청 (clientType=app, appId 필수)
class CreateSessionRequest {
  const CreateSessionRequest({
    required this.widgetKey,
    this.clientType = 'app',
    required this.appId,
  });

  final String widgetKey;
  final String clientType;
  final String appId;

  Map<String, dynamic> toJson() => {
    'widgetKey': widgetKey,
    'clientType': clientType,
    'appId': appId,
  };
}

/// 세션 발급 응답
class CreateSessionResponse {
  const CreateSessionResponse({
    required this.sessionToken,
    required this.expiresIn,
  });

  factory CreateSessionResponse.fromJson(Map<String, dynamic> json) {
    return CreateSessionResponse(
      sessionToken: json['sessionToken'] as String,
      expiresIn: (json['expiresIn'] as num).toInt(),
    );
  }

  final String sessionToken;
  final int expiresIn;
}

/// 답변 피드백 값 (문제 해결 여부)
enum FeedbackRating { good, bad }

extension FeedbackRatingApi on FeedbackRating {
  String get apiValue => this == FeedbackRating.good ? 'GOOD' : 'BAD';

  static FeedbackRating? tryParse(String? value) {
    switch (value) {
      case 'GOOD':
        return FeedbackRating.good;
      case 'BAD':
        return FeedbackRating.bad;
    }
    return null;
  }
}

/// 서버 메시지 DTO
class ChatMessageDto {
  const ChatMessageDto({
    required this.id,
    required this.role,
    required this.content,
    this.feedback,
    this.createdAt,
    this.metadata,
  });

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    final feedback = json['feedback'];
    final createdAt = json['createdAt'];
    final metadata = json['metadata'];
    return ChatMessageDto(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      feedback: FeedbackRatingApi.tryParse(
        feedback is String ? feedback : null,
      ),
      createdAt: createdAt is String ? createdAt : null,
      metadata: metadata is Map<String, dynamic>
          ? ChatMessageMetadata.fromJson(metadata)
          : null,
    );
  }

  final String id;
  final String role;
  final String content;
  final FeedbackRating? feedback;
  final String? createdAt;

  /// 저장된 조사 단계·출처. 오래된 메시지나 사용자 메시지에는 없을 수 있다.
  final ChatMessageMetadata? metadata;

  bool get isAssistant => role == 'assistant';
}

/// 히스토리 메시지의 metadata 중 화면에 쓰는 부분.
///
/// 실시간 이벤트와 같은 내용이 저장되지만 키가 다르다:
/// `step` → `steps`, `resources` → `resources`, `sources` → `sources`,
/// `web_sources` → `webSources`. 각 목록은 비어 있으면 키 자체가 없으므로
/// "없음"(null)과 "빈 목록"을 구분해 둔다.
/// model·usage·evaluation 같은 진단용 필드는 읽지 않는다.
class ChatMessageMetadata {
  const ChatMessageMetadata({
    this.steps,
    this.resources,
    this.notices,
    this.webSources,
    this.regeneratedFromMessageId,
  });

  factory ChatMessageMetadata.fromJson(Map<String, dynamic> json) {
    final steps = json['steps'];
    final resources = json['resources'];
    final regeneratedFrom = json['regeneratedFromMessageId'];
    return ChatMessageMetadata(
      steps: steps is List
          ? [
              for (final step in steps)
                if (step is Map<String, dynamic>) ?ResearchStep.tryParse(step),
            ]
          : null,
      resources: resources is List ? parseResources(resources) : null,
      notices: json['sources'] is List
          ? parseExternalSources(json['sources'], ChatSourceKind.notice)
          : null,
      webSources: json['webSources'] is List
          ? parseExternalSources(json['webSources'], ChatSourceKind.web)
          : null,
      regeneratedFromMessageId:
          regeneratedFrom is String && regeneratedFrom.isNotEmpty
          ? regeneratedFrom
          : null,
    );
  }

  /// 조사 단계의 최종 상태 (step 이벤트의 `type` 필드 없이 저장된다)
  final List<ResearchStep>? steps;
  final List<RawResource>? resources;
  final List<ChatSource>? notices;
  final List<ChatSource>? webSources;

  /// 재생성으로 만들어진 답변이면 원본 assistant 메시지 ID
  final String? regeneratedFromMessageId;

  /// 출처 목록이 하나라도 저장돼 있는지
  bool get hasSources =>
      resources != null || notices != null || webSources != null;

  /// 화면에 쓰는 순서(내부 문서 → 공지 → 웹)로 합친 출처
  List<ChatSource> resolveSources({String? resourceCenterUrl}) =>
      combineSources(
        resources: resources ?? const [],
        notices: notices ?? const [],
        webSources: webSources ?? const [],
        resourceCenterUrl: resourceCenterUrl,
      );
}

/// 대화 내역 조회 응답
class GetMessagesResponse {
  const GetMessagesResponse({required this.messages, this.nextCursor});

  factory GetMessagesResponse.fromJson(Map<String, dynamic> json) {
    final list = json['messages'];
    final nextCursor = json['nextCursor'];
    return GetMessagesResponse(
      messages: [
        if (list is List)
          for (final item in list)
            if (item is Map<String, dynamic>) ChatMessageDto.fromJson(item),
      ],
      nextCursor: nextCursor is String ? nextCursor : null,
    );
  }

  /// 최신순 (가장 최근 메시지가 맨 앞)
  final List<ChatMessageDto> messages;
  final String? nextCursor;
}

/// 채팅 메시지 전송 요청
class SendChatRequest {
  const SendChatRequest({required this.question});

  /// 서버가 받는 질문 최대 길이. 넘으면 400으로 거절된다.
  static const maxQuestionLength = 4000;

  final String question;

  Map<String, dynamic> toJson() => {'question': question};
}

/// 출처 종류. URL 조립 규칙이 서로 다르므로 구분한다.
/// - document: 내부 참고 문서 (resources 이벤트, 리소스 센터 경로)
/// - notice: Ziggle 공지 (sources 이벤트, 절대 URL 그대로)
/// - web: 웹 검색 출처 (web_sources 이벤트, 절대 URL 그대로)
enum ChatSourceKind { document, notice, web }

/// 참고 자료
class ChatSource {
  const ChatSource({
    required this.type,
    required this.url,
    this.title,
    this.kind = ChatSourceKind.document,
    this.official = false,
  });

  /// 'url' | 'image'
  final String type;
  final String url;
  final String? title;
  final ChatSourceKind kind;

  /// 웹 출처가 서버에 설정된 학교 공식 도메인인지. 내용의 정확성을 보증하지 않는다.
  final bool official;

  bool get isImage => type == 'image';
}

/// 조사 단계 상태. stopped는 서버가 보내지 않는 클라이언트 전용 상태
/// (오류·중지 시 running으로 남은 단계를 닫을 때 사용).
enum ResearchStepStatus { running, done, failed, stopped }

/// 에이전트 조사 진행 단계 (SSE step 이벤트)
class ResearchStep {
  const ResearchStep({
    required this.id,
    required this.kind,
    required this.label,
    required this.status,
    this.thought,
    this.resultCount,
  });

  /// 형식이 맞지 않으면 null (알 수 없는 status 포함)
  static ResearchStep? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final label = json['label'];
    if (id is! String || id.isEmpty || label is! String) return null;

    final ResearchStepStatus status;
    switch (json['status']) {
      case 'running':
        status = ResearchStepStatus.running;
      case 'done':
        status = ResearchStepStatus.done;
      case 'failed':
        status = ResearchStepStatus.failed;
      default:
        return null;
    }

    final kind = json['kind'];
    final thought = json['thought'];
    final resultCount = json['resultCount'];
    return ResearchStep(
      id: id,
      kind: kind is String ? kind : '',
      label: label,
      status: status,
      thought: thought is String && thought.trim().isNotEmpty ? thought : null,
      resultCount: resultCount is num ? resultCount.toInt() : null,
    );
  }

  /// 요청 내 단계 키. 같은 id는 같은 단계다.
  final String id;

  /// research | search_documents | search_notices | get_notice | search_web | 이후 추가될 값
  final String kind;

  /// 서버가 만든 진행 문구
  final String label;
  final ResearchStepStatus status;

  /// 선택적 행동 설명 (보조 문구). 답변 본문에 합치지 않는다.
  final String? thought;

  /// 선택적 결과 수. 0도 유효하다.
  final int? resultCount;

  ResearchStep withStatus(ResearchStepStatus status) => ResearchStep(
    id: id,
    kind: kind,
    label: label,
    status: status,
    thought: thought,
    resultCount: resultCount,
  );
}

/// 같은 id의 단계는 덮어쓰고, 새 단계는 처음 본 순서대로 뒤에 붙인다.
List<ResearchStep> upsertStep(List<ResearchStep> steps, ResearchStep step) {
  final index = steps.indexWhere((s) => s.id == step.id);
  if (index < 0) return [...steps, step];
  return [...steps]..[index] = step;
}

/// 아직 running인 단계를 주어진 상태로 닫는다 (오류·중지 시 로딩이 남지 않도록).
List<ResearchStep> settleRunningSteps(
  List<ResearchStep> steps,
  ResearchStepStatus status,
) {
  if (!steps.any((s) => s.status == ResearchStepStatus.running)) return steps;
  return [
    for (final s in steps)
      s.status == ResearchStepStatus.running ? s.withStatus(status) : s,
  ];
}

/// sources / web_sources 이벤트 항목을 출처로 변환한다.
/// 외부에서 그대로 여는 링크이므로 http(s) 절대 URL만 허용하고, URL 기준으로 중복을 제거한다.
List<ChatSource> parseExternalSources(Object? raw, ChatSourceKind kind) {
  if (raw is! List) return const [];
  final byUrl = <String, ChatSource>{};
  for (final item in raw) {
    if (item is! Map<String, dynamic>) continue;
    final url = item['url'];
    if (url is! String) continue;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;

    final title = item['title'];
    byUrl[url] = ChatSource(
      type: 'url',
      url: url,
      title: title is String && title.trim().isNotEmpty ? title : url,
      kind: kind,
      // official이 없거나 잘못 오면 비공식으로 취급 (공식으로 잘못 표시하지 않도록)
      official: kind == ChatSourceKind.web && item['official'] == true,
    );
  }
  return byUrl.values.toList();
}

/// resources 이벤트(또는 metadata.resources) 항목을 원본 리소스로 변환한다.
/// 경로(url)가 없는 항목은 열 수 없으므로 버린다.
List<RawResource> parseResources(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map<String, dynamic>)
        if (item['url'] case final String url when url.isNotEmpty)
          RawResource.fromJson(item),
  ];
}

/// 세 종류의 출처를 화면 순서(내부 문서 → 공지 → 웹)로 합친다.
/// 내부 문서만 리소스 센터 경로로 조립하고, 공지·웹은 받은 URL을 그대로 쓴다.
List<ChatSource> combineSources({
  List<RawResource> resources = const [],
  List<ChatSource> notices = const [],
  List<ChatSource> webSources = const [],
  String? resourceCenterUrl,
}) => [
  for (final resource in resources)
    resolveSource(resource, resourceCenterUrl: resourceCenterUrl),
  ...notices,
  ...webSources,
];

/// 스트림 완료 후 최종 응답
class SendChatResponse {
  const SendChatResponse({
    required this.answer,
    this.sources = const [],
    this.steps = const [],
  });

  final String answer;

  /// 내부 문서 → 공지 → 웹 순서
  final List<ChatSource> sources;

  /// 조사 단계의 최종 상태 (조사 없이 답한 경우 비어 있음)
  final List<ResearchStep> steps;
}

/// SSE 스트림의 resources 이벤트 원본 항목
class RawResource {
  const RawResource({required this.url, this.path, this.formats = const []});

  factory RawResource.fromJson(Map<String, dynamic> json) {
    final url = json['url'];
    final path = json['path'];
    final formats = json['formats'];
    return RawResource(
      url: url is String ? url : '',
      path: path is String ? path : null,
      formats: [
        if (formats is List)
          for (final format in formats) format.toString().toLowerCase(),
      ],
    );
  }

  /// 이미 URL 인코딩된 리소스 경로. 다시 인코딩하지 않는다.
  final String url;
  final String? path;
  final List<String> formats;
}

/// 웹 위젯과 동일한 규칙으로 리소스를 출처로 변환한다.
/// resourceCenterUrl이 있으면 `{base}/resource/{cleanPath}` 형태의 URL을 조립하고,
/// 없으면 원본 url을 그대로 사용한다.
ChatSource resolveSource(RawResource resource, {String? resourceCenterUrl}) {
  final url = resource.url;

  var path = url;
  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasAuthority) {
    path = parsed.path;
  }
  var cleanPath = path.startsWith('/') ? path.substring(1) : path;

  final lower = cleanPath.toLowerCase();
  final hasExt = lower.endsWith('.pdf') || lower.endsWith('.png');
  if (!hasExt) {
    if (resource.formats.contains('png')) {
      cleanPath = '$cleanPath.png';
    } else {
      cleanPath = '$cleanPath.pdf';
    }
  }

  final finalUrl = resourceCenterUrl != null && resourceCenterUrl.isNotEmpty
      ? '${resourceCenterUrl.endsWith('/') ? resourceCenterUrl.substring(0, resourceCenterUrl.length - 1) : resourceCenterUrl}/resource/$cleanPath'
      : url;
  final isImage = cleanPath.toLowerCase().endsWith('.png');

  var title = resource.path;
  if (title == null || title.isEmpty) {
    final parts = cleanPath.split('/');
    var fileName = parts.isNotEmpty ? parts.last : '참고자료';
    if (fileName.isEmpty) fileName = '참고자료';
    fileName = Uri.decodeComponent(
      fileName,
    ).replaceAll(RegExp(r'\.(pdf|png|jpg|jpeg)$', caseSensitive: false), '');
    title = fileName.length > 20 ? '${fileName.substring(0, 20)}...' : fileName;
  }

  return ChatSource(
    type: isImage ? 'image' : 'url',
    url: finalUrl,
    title: title,
    kind: ChatSourceKind.document,
  );
}
