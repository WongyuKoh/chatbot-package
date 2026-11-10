import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 답변 본문·출처에서 열 수 있는 링크 스킴.
/// 본문 링크는 모델이 만든 Markdown에서 오므로 앱 딥링크·파일 경로 같은
/// 다른 스킴은 열지 않는다.
const _allowedSchemes = {'http', 'https', 'mailto'};

/// 열어도 되는 링크면 [Uri], 아니면 null
Uri? safeExternalUri(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !_allowedSchemes.contains(uri.scheme)) return null;
  // 상대 경로나 호스트 없는 http(s) 링크는 열 곳이 없다
  if (uri.scheme != 'mailto' && uri.host.isEmpty) return null;
  return uri;
}

/// 링크를 외부 브라우저(또는 메일 앱)로 연다. 열 수 없는 링크는 무시한다.
Future<void> openExternalLink(String url) async {
  final uri = safeExternalUri(url);
  if (uri == null) {
    debugPrint('GistChatbot: blocked link - $url');
    return;
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('GistChatbot: failed to open link - $e');
  }
}
