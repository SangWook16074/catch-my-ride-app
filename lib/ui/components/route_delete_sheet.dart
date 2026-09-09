import 'package:flutter/material.dart';

import '../design/components/button.dart';
import '../design/components/sheet.dart';
import '../design/tokens.dart';

/// 경로 삭제 확인 바텀시트 — 미니앱 RouteDeleteSheet.tsx 이식.
/// 삭제 중에는 닫히지 않아 중복 호출·유령 이탈을 막고,
/// 실패하면 시트를 유지한 채 에러 문구를 보여줘 재시도 가능하게 한다.
///
/// [onConfirm]은 삭제 API 호출 — 성공 시 true를 반환하면 시트가 닫힌다.
/// 반환값: 삭제 완료 여부.
Future<bool> showRouteDeleteSheet({
  required BuildContext context,
  required String routeLabel,
  required bool isLastRoute,
  required Future<bool> Function() onConfirm,
}) async {
  final deleted = await showAppSheet<bool>(
    context: context,
    header: "'$routeLabel' 경로를 삭제할까요?",
    builder: (context) => _DeleteSheetBody(
      isLastRoute: isLastRoute,
      onConfirm: onConfirm,
    ),
  );
  return deleted ?? false;
}

class _DeleteSheetBody extends StatefulWidget {
  const _DeleteSheetBody({required this.isLastRoute, required this.onConfirm});

  final bool isLastRoute;
  final Future<bool> Function() onConfirm;

  @override
  State<_DeleteSheetBody> createState() => _DeleteSheetBodyState();
}

class _DeleteSheetBodyState extends State<_DeleteSheetBody> {
  bool _deleting = false;
  bool _failed = false;

  Future<void> _confirm() async {
    if (_deleting) {
      return;
    }
    setState(() {
      _deleting = true;
      _failed = false;
    });
    final ok = await widget.onConfirm();
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _deleting = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            widget.isLastRoute
                ? '마지막 경로예요. 삭제하면 알림이 모두 중지되고 처음부터 다시 설정해야 해요'
                : '삭제하면 이 경로의 출발 알림이 더 이상 오지 않아요',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
          if (_failed) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              '삭제하지 못했어요. 네트워크를 확인하고 다시 시도해주세요',
              style: AppTypo.bodySm.copyWith(color: context.colors.dangerStrong),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '취소',
                  variant: AppButtonVariant.neutral,
                  medium: true,
                  block: true,
                  onPressed: _deleting
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton(
                  label: '삭제',
                  variant: AppButtonVariant.danger,
                  medium: true,
                  block: true,
                  loading: _deleting,
                  onPressed: _confirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
