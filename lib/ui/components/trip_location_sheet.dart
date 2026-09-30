import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/trip_start.dart';
import '../../platform/location.dart';
import '../design/components/button.dart';
import '../design/components/sheet.dart';
import '../design/tokens.dart';

/// 하차 알림 시작 전 위치 권한 확보 — 없으면 **허용하도록 유도**한다 (오너 결정 2026-09-30).
/// `true`면 지금 시작해도 된다. 시작 액션은 전부 이걸 먼저 통과한 뒤에 서버를 부른다
/// (되돌릴 수 없는 일을 먼저 하지 않도록 — 예: 여정 생성 후 저장·시작).
Future<bool> ensureTripLocationOrGuide(BuildContext context) async {
  final permission = await tripLocationGate();
  if (permission == TripLocationPermission.granted) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  return await showTripLocationRequiredSheet(context, permission) ?? false;
}

/// 위치 권한이 없어 하차 알림을 시작할 수 없을 때 (오너 결정 2026-09-30 — 권한 허용 유저만 사용).
///
/// 왜 필요한지를 먼저 말하고 **바로 허용할 길**을 준다: 좌표가 없으면 서버는 탑승역 전광판에 있는
/// **유저 뒤에 오는 열차**를 잡을 수밖에 없고, 그러면 하차 알림이 내릴 역을 지난 뒤에 온다.
/// 되는 척하는 기능보다 못 쓴다고 말하는 쪽이 낫다 (NFR-01·FR-706과 같은 태도).
///
/// 반환값: 시트 안에서 권한이 허용됐으면 `true` — 호출부는 그대로 시작을 이어간다.
/// 설정 앱으로 나간 경우는 `false`(돌아와서 다시 누르면 된다).
Future<bool?> showTripLocationRequiredSheet(
  BuildContext context,
  TripLocationPermission permission,
) {
  return showAppSheet<bool>(
    context: context,
    header: switch (permission) {
      TripLocationPermission.serviceOff => '기기 위치가 꺼져 있어요',
      _ => '위치 권한이 필요해요',
    },
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        0,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _body(permission),
            style: AppTypo.bodySm.copyWith(color: sheetContext.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          AppButton(
            label: switch (permission) {
              TripLocationPermission.serviceOff => '위치 설정 열기',
              TripLocationPermission.blocked => '설정에서 허용하기',
              _ => '권한 허용하기',
            },
            medium: true,
            block: true,
            onPressed: () async {
              final navigator = Navigator.of(sheetContext);
              switch (permission) {
                // 다시 물어볼 수 있는 상태 — 시트에서 바로 동의창을 띄워 준다
                case TripLocationPermission.denied:
                case TripLocationPermission.granted:
                  final retried = await tripLocationGate();
                  navigator.pop(retried == TripLocationPermission.granted);
                // 앱에서 풀 수 없는 상태 — 기기 위치 꺼짐은 시스템 위치 설정, 굳은 거부는 앱 설정
                case TripLocationPermission.serviceOff:
                  navigator.pop(false);
                  unawaited(openDeviceLocationSettings());
                case TripLocationPermission.blocked:
                  navigator.pop(false);
                  unawaited(openAppLocationSettings());
              }
            },
          ),
        ],
      ),
    ),
  );
}

String _body(TripLocationPermission permission) => switch (permission) {
  TripLocationPermission.serviceOff =>
    '하차 알림은 지금 어느 역을 지나는지 확인해서 타고 있는 열차를 찾아요.\n'
        '설정 앱에서 위치 기능을 켜주시면 시작할 수 있어요.',
  TripLocationPermission.blocked =>
    '하차 알림은 지금 어느 역을 지나는지 확인해서 타고 있는 열차를 찾아요.\n'
        '설정 앱 > 놓치지마 > 위치에서 허용해주시면 시작할 수 있어요.',
  // 다시 물어볼 수 있는 상태 — 시작을 다시 누르면 동의창이 뜬다
  _ =>
    '하차 알림은 지금 어느 역을 지나는지 확인해서 타고 있는 열차를 찾아요.\n'
        '위치 권한이 없으면 뒤에 오는 열차를 잡아 알림이 늦게 가서, 시작할 수 없어요.',
};
