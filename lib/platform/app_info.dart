/// 앱 메타데이터 브리지 — package_info_plus 플러그인 래퍼.
/// CLAUDE.md 레이어 규칙: 네이티브 브리지(플러그인)는 platform/에서만 만진다.
library;

import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  /// "1.0.0 (1)" 형태. 실패(테스트 등 채널 없음)면 null — 호출부가 대체 표기를 정한다
  Future<String?> version() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return null;
    }
  }
}
