/// 스토어판 유저 식별 — API.md §8-3 익명 키.
///
/// 미니앱은 앱인토스 SDK의 getAnonymousKey()를 썼지만 스토어판에는 그 SDK가 없다.
/// 서버 계약은 키를 불투명하게 취급(형식 검사만: 8~100자, 영숫자와 `-_.=+/`)하므로
/// 기기에서 고엔트로피 키를 1회 생성해 로컬에 영구 보관한다 — 재설치 전까지 같은 유저.
/// (재설치 시 유저가 바뀌는 한계는 §8-3의 수용된 MVP 리스크와 동일 성격.
///  토스 로그인 전환 시 이관은 API.md 미확정 4 참조.)
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AnonymousKeyStore {
  static const String _prefsKey = 'catch-my-ride/anon-key';

  String? _cached;

  /// `Authorization: Bearer anon:{key}`에 들어갈 key. 최초 호출 시 생성·저장한다.
  Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }
    final key = _generate();
    await prefs.setString(_prefsKey, key);
    _cached = key;
    return key;
  }

  /// 32바이트 난수 → base64url(패딩 제거) = 43자, 허용 문자셋(A-Za-z0-9-_) 안
  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
