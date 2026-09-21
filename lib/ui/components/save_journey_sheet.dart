/// 1회성 길을 여정으로 저장하는 시트 (FR-708 → FR-702 전환) — 라벨만 받는다(구간은 이미
/// 있고, 요일 반복은 나중에 수정). 트립 화면·하차 알림 탭 "최근 간 길"이 공용으로 쓴다.
/// 성공하면 저장된 라벨을 돌려주고 최근 간 길에서 지운다. 실패(중복·10개 초과·네트워크)는
/// 시트 안에서 안내한다
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/recent_routes_store.dart';
import '../../domain/journey.dart';
import '../../domain/models.dart';
import '../design/components/button.dart';
import '../design/components/sheet.dart';
import '../design/components/text_field.dart';
import '../design/tokens.dart';

Future<String?> showSaveJourneySheet(
  BuildContext context,
  List<JourneyLeg> legs,
) async {
  final label = await showAppSheet<String>(
    context: context,
    header: '경로를 저장할까요?',
    builder: (_) => _SaveJourneySheet(legs: legs),
  );
  if (label != null) {
    // 햅틱: 여정 저장 확정 (CLAUDE.md 적응형 UI 규칙)
    unawaited(HapticFeedback.mediumImpact());
    // 호출자가 돌아오자마자 목록을 다시 읽는다 — 지우기를 끝내고 돌려준다
    await RecentRoutesStore().remove(legs);
  }
  return label;
}

class _SaveJourneySheet extends StatefulWidget {
  const _SaveJourneySheet({required this.legs});

  final List<JourneyLeg> legs;

  @override
  State<_SaveJourneySheet> createState() => _SaveJourneySheetState();
}

class _SaveJourneySheetState extends State<_SaveJourneySheet> {
  final TextEditingController _label = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final request = JourneyRequest(
      label: _label.text,
      repeatDays: const [],
      legs: widget.legs,
    );
    final message = validateJourneyRequest(request);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final journey = await api.createJourney(request);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(journey.label);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = '저장하지 못했어요. 네트워크를 확인해주세요';
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            journeyPathSummary(widget.legs),
            style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          AppTextField(
            placeholder: '이름 (예: 병원, 본가)',
            controller: _label,
            maxLength: journeyLabelMaxLength,
            onSubmitted: (_) => unawaited(_save()),
            textInputAction: TextInputAction.done,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _error!,
              style: AppTypo.bodySm.copyWith(
                color: context.colors.dangerStrong,
              ),
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          AppButton(
            label: '저장',
            block: true,
            loading: _saving,
            onPressed: _saving ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
