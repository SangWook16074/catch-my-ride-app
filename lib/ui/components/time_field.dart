import 'package:flutter/material.dart';

import '../../domain/time_format.dart';
import '../design/components/button.dart';
import '../design/components/chip.dart';
import '../design/components/sheet.dart';
import '../design/tokens.dart';

/// HH:MM 시각 입력 필드 — 미니앱 TimeField.tsx 이식.
/// 필드를 누르면 바텀시트가 열리고 오전/오후·시·분(5분 단위)을 골라 입력한다.
/// 값 포맷은 API.md와 동일한 24시간 "HH:MM".
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.placeholder,
    required this.value,
    required this.onChanged,
  });

  /// 바텀시트 헤더이자 필드 접근성 라벨 (예: "출발 시각")
  final String label;

  /// 값이 없을 때 필드에 보여줄 예시 시각 (예: "07:40")
  final String placeholder;

  /// "HH:MM" 24시간 포맷, 미입력이면 null
  final String? value;
  final ValueChanged<String> onChanged;

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showAppSheet<String>(
      context: context,
      header: label,
      builder: (context) => _TimeSheetBody(initialValue: value),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    final radius = BorderRadius.circular(AppRadius.md);
    // 마진은 탭 영역 밖, 잉크는 Material 위 — 하이라이트가 필드 면과 정확히 일치한다
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: context.colors.fill,
          borderRadius: radius,
          child: InkWell(
            onTap: () => _openSheet(context),
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.md,
              ),
              child: Text(
                current != null ? formatKoreanTime(current) : placeholder,
                style: AppTypo.body.copyWith(
                  color: current != null
                      ? context.colors.ink
                      : context.colors.inkSubtle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<int> _hours12 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
final List<int> _minutes = List.generate(12, (i) => i * 5);

class _TimeSheetBody extends StatefulWidget {
  const _TimeSheetBody({required this.initialValue});

  final String? initialValue;

  @override
  State<_TimeSheetBody> createState() => _TimeSheetBodyState();
}

class _TimeSheetBodyState extends State<_TimeSheetBody> {
  Meridiem? _meridiem;
  int? _hour12;
  int? _minute;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialValue != null
        ? parseHHMM(widget.initialValue!)
        : null;
    // 기존 값이 있으면 그대로 복원, 없으면 통근 기본인 오전·00분만 미리 골라두고 시는 직접 고르게 한다
    _meridiem = parts?.meridiem ?? Meridiem.am;
    _hour12 = parts?.hour12;
    _minute = parts?.minute ?? 0;
  }

  bool get _complete => _meridiem != null && _hour12 != null && _minute != null;

  @override
  Widget build(BuildContext context) {
    String pad(int n) => n.toString().padLeft(2, '0');
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
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              AppChip(
                label: '오전',
                selected: _meridiem == Meridiem.am,
                onPressed: () => setState(() => _meridiem = Meridiem.am),
              ),
              AppChip(
                label: '오후',
                selected: _meridiem == Meridiem.pm,
                onPressed: () => setState(() => _meridiem = Meridiem.pm),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text('시', style: AppTypo.caption.copyWith(color: context.colors.inkSubtle)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final hour in _hours12)
                AppChip(
                  label: '$hour시',
                  selected: _hour12 == hour,
                  onPressed: () => setState(() => _hour12 = hour),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text('분', style: AppTypo.caption.copyWith(color: context.colors.inkSubtle)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final minute in _minutes)
                AppChip(
                  label: '${pad(minute)}분',
                  selected: _minute == minute,
                  onPressed: () => setState(() => _minute = minute),
                ),
            ],
          ),
          const SizedBox(height: 20),
          AppButton(
            label: '확인',
            block: true,
            onPressed: _complete
                ? () => Navigator.of(
                    context,
                  ).pop(toHHMM(_meridiem!, _hour12!, _minute!))
                : null,
          ),
        ],
      ),
    );
  }
}
