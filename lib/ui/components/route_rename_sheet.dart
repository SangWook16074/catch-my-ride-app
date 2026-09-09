import 'package:flutter/material.dart';

import '../../domain/onboarding.dart' show routeLabelMaxLength;
import '../design/components/button.dart';
import '../design/components/sheet.dart';
import '../design/components/text_field.dart';
import '../design/tokens.dart';

/// 경로 이름 수정 바텀시트 — 미니앱 RouteRenameSheet.tsx 이식.
/// 라이브 뷰에서 선택된 경로 칩을 다시 탭하면 열린다.
/// 다른 경로와 중복이면 저장 전에 막고 안내한다 (서버 400 왕복 절약).
///
/// [onSave]는 trim된 새 이름으로 저장 API 호출 — 성공 시 true를 반환하면 시트가 닫힌다.
/// 기존 이름과 같으면 API 없이 닫는다.
Future<void> showRouteRenameSheet({
  required BuildContext context,
  required String initialLabel,
  required List<String> otherLabels,
  required Future<bool> Function(String label) onSave,
}) {
  return showAppSheet<void>(
    context: context,
    header: '경로 이름을 수정할까요?',
    builder: (context) => _RenameSheetBody(
      initialLabel: initialLabel,
      otherLabels: otherLabels,
      onSave: onSave,
    ),
  );
}

class _RenameSheetBody extends StatefulWidget {
  const _RenameSheetBody({
    required this.initialLabel,
    required this.otherLabels,
    required this.onSave,
  });

  final String initialLabel;
  final List<String> otherLabels;
  final Future<bool> Function(String label) onSave;

  @override
  State<_RenameSheetBody> createState() => _RenameSheetBodyState();
}

class _RenameSheetBodyState extends State<_RenameSheetBody> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialLabel,
  );
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();

  bool get _duplicate =>
      _trimmed != widget.initialLabel && widget.otherLabels.contains(_trimmed);

  bool get _valid =>
      _trimmed.isNotEmpty &&
      _trimmed.length <= routeLabelMaxLength &&
      !_duplicate;

  Future<void> _save() async {
    if (_saving || !_valid) {
      return;
    }
    if (_trimmed == widget.initialLabel) {
      Navigator.of(context).pop(); // 바뀐 게 없으면 API 없이 닫는다
      return;
    }
    setState(() {
      _saving = true;
      _failed = false;
    });
    final ok = await widget.onSave(_trimmed);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _failed = true; // 시트를 유지해 재시도 가능하게 한다
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
          AppTextField(
            placeholder: '예: 출근, 학원, 마을버스',
            controller: _controller,
            maxLength: routeLabelMaxLength,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            _duplicate
                ? '이미 같은 이름의 경로가 있어요'
                : '목록에서 경로를 구분하는 이름이에요 (최대 $routeLabelMaxLength자)',
            style: AppTypo.caption.copyWith(
              color: _duplicate ? context.colors.dangerStrong : context.colors.inkSubtle,
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              '이름을 저장하지 못했어요. 네트워크를 확인하고 다시 시도해주세요',
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
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton(
                  label: '저장',
                  medium: true,
                  block: true,
                  loading: _saving,
                  onPressed: _valid ? _save : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
