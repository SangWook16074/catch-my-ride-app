/// 딥링크 수신 — app_links 플러그인 래퍼.
/// CLAUDE.md 레이어 규칙: 네이티브 브리지(플러그인)는 platform/에서만 만진다.
///
/// 스킴 등록: iOS Info.plist CFBundleURLTypes / Android manifest intent-filter —
/// `catchmyride://` (푸시 랜딩·외부 실행용). https 유니버설 링크는 푸시 채널 붙일 때 추가.
library;

import 'package:app_links/app_links.dart';

class DeepLinks {
  final AppLinks _appLinks = AppLinks();

  /// 콜드 스타트를 연 링크 — 없으면 null. 브리지 오류는 조용히 무시한다
  Future<Uri?> getInitialLink() async {
    try {
      return await _appLinks.getInitialLink();
    } catch (_) {
      return null;
    }
  }

  /// 실행 중(웜) 딥링크 스트림
  Stream<Uri> get uriStream => _appLinks.uriLinkStream;
}
