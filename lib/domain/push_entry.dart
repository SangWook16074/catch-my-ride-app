/// 푸시(딥링크)로 앱에 진입했는지 판별한다 — 미니앱 src/domain/pushEntry.ts 이식.
///
/// 스토어판 딥링크: `catchmyride://open?from=push&notifiedDate=YYYY-MM-DD`.
/// (미니앱은 `intoss://catch-my-ride?...` — 스킴만 다르고 쿼리 계약은 동일하게 유지해
/// 서버 푸시 랜딩 링크를 한 규칙으로 만든다.)
library;

class PushEntry {
  const PushEntry({required this.fromPush, required this.notifiedDate});

  final bool fromPush;

  /// 푸시가 안내한 날짜 — 탑승 피드백 기록에 쓴다. 없거나 형식이 어긋나면 null
  final String? notifiedDate;
}

const PushEntry notFromPush = PushEntry(fromPush: false, notifiedDate: null);

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

PushEntry parsePushEntry(Uri? uri) {
  if (uri == null) {
    return notFromPush;
  }
  final params = uri.queryParameters;
  if (params['from'] != 'push') {
    return notFromPush;
  }
  final date = params['notifiedDate'] ?? '';
  return PushEntry(
    fromPush: true,
    notifiedDate: _datePattern.hasMatch(date) ? date : null,
  );
}
