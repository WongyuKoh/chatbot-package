/// 외부 브라우저로 열 수 있는 웹 주소(호스트가 있는 http/https 절대 URL)인지.
/// 출처 목록과 본문 링크가 같은 기준을 쓰도록 한곳에 둔다.
bool isWebUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
