import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../config/gist_chatbot_config.dart';
import '../state/chat_message.dart';
import 'external_link.dart';
import 'loading_shimmer.dart';
import 'pressable.dart';
import 'research_steps.dart';

/// 메시지 말풍선 (웹 위젯과 동일: user는 primary 10%/25%, assistant는 흰 배경+테두리)
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.colors,
    this.isLoadingPlaceholder = false,
    this.loadingMessage = '',
  });

  final ChatMessage message;
  final GistChatbotColors colors;

  /// 스트리밍 텍스트가 아직 없을 때 로딩 문구를 표시.
  /// 조사 단계가 있으면 [loadingMessage] 대신 단계 목록을 보여 준다.
  final bool isLoadingPlaceholder;
  final String loadingMessage;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final waitingForText = message.text.isEmpty && isLoadingPlaceholder;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? colors.userMessageBg.withValues(alpha: 0.10)
              : colors.assistantMessageBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUser
                ? colors.userMessageBg.withValues(alpha: 0.25)
                : colors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUser)
              Text(
                message.text,
                style: TextStyle(color: colors.text, fontSize: 14, height: 1.4),
              )
            else ...[
              // 조사 단계: 본문 전에는 펼쳐서, 본문이 오면 한 줄 요약으로
              if (message.steps.isNotEmpty)
                ResearchSteps(
                  steps: message.steps,
                  colors: colors,
                  live: waitingForText,
                )
              else if (waitingForText)
                LoadingIndicatorRow(
                  message: loadingMessage,
                  color: colors.textSecondary,
                ),
              if (!waitingForText &&
                  (message.text.isNotEmpty || message.steps.isEmpty))
                _AssistantMarkdown(text: message.text, colors: colors),
            ],
            if (message.sources.isNotEmpty)
              _SourcesSection(sources: message.sources, colors: colors),
          ],
        ),
      ),
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  const _AssistantMarkdown({required this.text, required this.colors});

  final String text;
  final GistChatbotColors colors;

  @override
  Widget build(BuildContext context) {
    // 헤딩 위계: 웹 위젯(Streamdown)과 동일
    // h1 text-3xl ~ h6 text-sm, 모두 font-semibold
    TextStyle heading(double size) => TextStyle(
      color: colors.text,
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    return GptMarkdownTheme(
      gptThemeData: GptMarkdownThemeData(
        brightness: Brightness.light,
        h1: heading(30),
        h2: heading(24),
        h3: heading(20),
        h4: heading(18),
        h5: heading(16),
        h6: heading(14),
        linkColor: colors.primary,
        linkHoverColor: colors.primary,
        hrLineColor: colors.border,
        autoAddDividerLineAfterH1: false,
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: colors.text, fontSize: 14, height: 1.4),
        child: GptMarkdown(
          text,
          style: TextStyle(color: colors.text, fontSize: 14, height: 1.4),
          linkBuilder: (context, span, url, style) {
            return GestureDetector(
              onTap: () => openExternalLink(url),
              child: Text.rich(
                span,
                style: style.copyWith(
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.primary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 출처 영역: 상단 구분선 + 배지 + 이미지.
/// 배지는 서버가 준 순서(내부 문서 → 공지 → 웹)를 그대로 따른다.
class _SourcesSection extends StatelessWidget {
  const _SourcesSection({required this.sources, required this.colors});

  final List<ChatSource> sources;
  final GistChatbotColors colors;

  @override
  Widget build(BuildContext context) {
    final images = sources.where((s) => s.isImage).toList();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final source in sources.where((s) => !s.isImage))
                _SourceBadge(source: source, colors: colors),
            ],
          ),
          for (final source in images)
            _SourceImage(source: source, colors: colors),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source, required this.colors});

  final ChatSource source;
  final GistChatbotColors colors;

  /// 출처 종류를 아이콘과 스크린리더 문구로 구분한다 (내부 문서 / Ziggle 공지 / 웹)
  (IconData, String) get _kind => switch (source.kind) {
    ChatSourceKind.document => (Icons.description_outlined, '참고 문서'),
    ChatSourceKind.notice => (Icons.campaign_outlined, 'Ziggle 공지'),
    ChatSourceKind.web => (
      Icons.public,
      source.official ? '학교 공식 웹 출처' : '외부 웹 출처',
    ),
  };

  /// 학교 공식 도메인이 아닌 웹 출처. 공식이어도 내용의 정확성을 보증하지는 않으므로
  /// 공식 쪽을 강조하지 않고 외부 쪽에만 표시를 붙인다.
  bool get _isExternalWeb =>
      source.kind == ChatSourceKind.web && !source.official;

  String get _title {
    final title = source.title ?? Uri.tryParse(source.url)?.host ?? source.url;
    // 웹 출처 제목은 보통 호스트명이라 www.는 떼고 보여 준다
    return source.kind == ChatSourceKind.web
        ? title.replaceFirst(RegExp(r'^www\.'), '')
        : title;
  }

  @override
  Widget build(BuildContext context) {
    final (icon, kindLabel) = _kind;
    return Semantics(
      link: true,
      label: '$kindLabel: $_title',
      excludeSemantics: true,
      child: _buildBadge(icon),
    );
  }

  Widget _buildBadge(IconData icon) {
    return Pressable(
      onTap: () => openExternalLink(source.url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: colors.text),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
            if (_isExternalWeb) ...[
              const SizedBox(width: 6),
              Text(
                '외부',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 10,
                  height: 1.2,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.open_in_new, size: 12, color: colors.text),
          ],
        ),
      ),
    );
  }
}

/// 이미지 출처 (16:9 스켈레톤 → 이미지, 탭 시 외부 브라우저)
class _SourceImage extends StatelessWidget {
  const _SourceImage({required this.source, required this.colors});

  final ChatSource source;
  final GistChatbotColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => openExternalLink(source.url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            source.url,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.border.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
