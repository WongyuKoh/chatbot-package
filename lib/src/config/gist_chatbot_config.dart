import 'package:flutter/material.dart';

/// 챗봇 색상 설정 (웹 위젯 CSS 변수와 동일한 팔레트)
class GistChatbotColors {
  const GistChatbotColors({
    this.primary = const Color(0xFFDF3326),
    this.button = const Color(0xFFDF3326),
    this.background = Colors.white,
    this.text = const Color(0xFF1E293B),
    this.textSecondary = const Color(0xFF64748B),
    this.border = const Color(0xFFE2E8F0),
    this.userMessageBg = const Color(0xFFDF3326),
    this.assistantMessageBg = Colors.white,
  });

  final Color primary;
  final Color button;

  /// 헤더/메시지 영역/입력창 공통 배경
  final Color background;
  final Color text;
  final Color textSecondary;
  final Color border;

  /// 사용자 말풍선 기준색 (10% 배경 / 25% 테두리로 적용)
  final Color userMessageBg;
  final Color assistantMessageBg;

  GistChatbotColors copyWith({
    Color? primary,
    Color? button,
    Color? background,
    Color? text,
    Color? textSecondary,
    Color? border,
    Color? userMessageBg,
    Color? assistantMessageBg,
  }) {
    return GistChatbotColors(
      primary: primary ?? this.primary,
      button: button ?? this.button,
      background: background ?? this.background,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      userMessageBg: userMessageBg ?? this.userMessageBg,
      assistantMessageBg: assistantMessageBg ?? this.assistantMessageBg,
    );
  }
}

/// GIST 챗봇 운영 API 베이스 URL
const String kDefaultApiBaseUrl = 'https://api.chatbot.gistory.me/api';

/// GIST 챗봇 운영 리소스 센터 URL
const String kDefaultResourceCenterUrl =
    'https://resource-center-573707418062.asia-northeast3.run.app';

/// GIST 챗봇 위젯 설정
class GistChatbotConfig {
  const GistChatbotConfig({
    required this.widgetKey,
    this.apiBaseUrl = kDefaultApiBaseUrl,
    this.resourceCenterUrl = kDefaultResourceCenterUrl,
    this.appId,
    this.accessToken,
    this.clientId,
    this.reportUrl = 'https://cs.gistory.me?service=chatbot',
    this.colors = const GistChatbotColors(),
  });

  final String widgetKey;

  /// 백엔드 API 베이스 URL. 기본값은 운영 서버이며,
  /// dev/스테이징 환경을 쓸 때만 지정한다.
  final String apiBaseUrl;

  /// 출처 리소스(PDF/이미지) 베이스 URL. `{url}/resource/{path}` 로 열림.
  /// 기본값은 운영 리소스 센터. null이면 출처의 원본 url을 그대로 사용한다.
  final String? resourceCenterUrl;

  /// 앱 식별자. null이면 package_info_plus로 자동 획득.
  final String? appId;
  final String? accessToken;

  /// 사용자를 구분하는 ID (1~128자). 지정하면 세션 발급 때 서버로 보내고,
  /// 같은 값으로 발급한 세션끼리 질문 한도를 함께 센다. null이면 보내지 않고
  /// 서버는 세션마다 따로 센다.
  ///
  /// 남이 알 수 없는 값을 써야 한다. 학번·이메일처럼 알려진 값을 쓰면 다른 사람이
  /// 같은 값을 보내 그 사용자의 한도를 소진시킬 수 있다.
  final String? clientId;

  /// 헤더 신고 버튼이 여는 URL.
  final String reportUrl;
  final GistChatbotColors colors;
}
