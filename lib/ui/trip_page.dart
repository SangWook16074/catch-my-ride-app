import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/trip_store.dart';
import '../domain/journey.dart';
import '../platform/live_activity.dart';
import '../domain/live_view.dart';
import '../domain/models.dart';
import 'design/components/button.dart';
import 'design/tokens.dart';

/// 트립 폴링 주기 — FR-204 준용(15~30초). 하차 판정·푸시는 서버 몫, 화면은 표시만
const Duration _pollInterval = Duration(seconds: 20);

/// 진행 중 트립 화면 (FR-705) — 남은 정거장 카운트다운, 환승 수동 재개(FR-703).
class TripPage extends StatefulWidget {
  const TripPage({
    super.key,
    required this.tripId,
    // 푸시 딥링크 진입은 여정 라벨을 모른다 — 기능명으로 대체
    this.journeyLabel = '하차 알림',
  });

  final String tripId;
  final String journeyLabel;

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  final TripStore _tripStore = TripStore();
  final LiveActivityBridge _liveActivity = LiveActivityBridge();
  TripStatus? _status;
  bool _stale = false;
  bool _gone = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 잠금화면 Live Activity 시작 (FR-705) — iOS 16.1 미만·비활성은 브리지가 조용히 무시
    unawaited(_liveActivity.start(widget.journeyLabel));
    unawaited(_refresh());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    // 종착 상태면 더 묻지 않는다 (mock은 폴링마다 전진하므로 화면 상태 고정에도 필요)
    final phase = _status?.phase;
    if (_gone || phase == TripPhase.done || phase == TripPhase.transfer) {
      return;
    }
    try {
      final status = await api.getTrip(widget.tripId);
      if (!mounted) {
        return;
      }
      unawaited(_liveActivity.update(status)); // 잠금화면 카운트다운 갱신 (FR-705)
      setState(() {
        _status = status;
        _stale = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.status == 404) {
        // 트립이 서버에서 정리됨 — 종료 안내로 강등, 이어보기·잠금화면도 정리
        unawaited(_tripStore.clear());
        unawaited(_liveActivity.end());
        setState(() => _gone = true);
        return;
      }
      setState(() => _stale = true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _stale = true);
    }
  }

  Future<void> _advanceLeg() async {
    // 햅틱: 환승 재개 확정 (CLAUDE.md 적응형 UI 규칙)
    HapticFeedback.mediumImpact();
    try {
      final status = await api.advanceTripLeg(widget.tripId);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _stale = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _stale = true);
    }
  }

  Future<void> _end() async {
    unawaited(_tripStore.clear());
    unawaited(_liveActivity.end());
    try {
      await api.endTrip(widget.tripId);
    } catch (_) {
      // 종료 실패해도 화면은 닫는다 — 서버가 자동 정리한다 (§9-3)
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(widget.journeyLabel, style: AppTypo.heading),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            children: [
              Expanded(child: Center(child: _body())),
              if (!_gone && _status?.phase != TripPhase.done)
                AppButton(
                  label: '트립 종료',
                  variant: AppButtonVariant.tonal,
                  block: true,
                  onPressed: () => unawaited(_end()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_gone) {
      return _message(
        title: '트립이 종료됐어요',
        subtitle: '이미 끝났거나 서버에서 정리된 트립이에요',
        button: AppButton(label: '돌아가기', onPressed: () => Navigator.of(context).pop()),
      );
    }
    final status = _status;
    if (status == null) {
      return Text(
        '트립 정보를 불러오고 있어요…',
        style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
      );
    }
    switch (status.phase) {
      case TripPhase.tracking:
      case TripPhase.arriving:
        final arriving = status.phase == TripPhase.arriving;
        final remaining = status.remainingStops;
        // TRACKING + remaining null = 열차 특정 전 "위치 확인 중" — 숫자를 지어내지 않는다 (API.md §9-3)
        final identifying = !arriving && remaining == null;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${status.eventStop}에서 내려요',
              textAlign: TextAlign.center,
              style: AppTypo.title,
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              arriving
                  ? '다음 역이에요!'
                  : identifying
                  ? '위치 확인 중이에요…'
                  : '$remaining정거장 남았어요',
              textAlign: TextAlign.center,
              style: AppTypo.title.copyWith(
                color: arriving
                    ? context.colors.cautionStrong
                    : identifying
                    ? context.colors.inkSubtle
                    : context.colors.primaryStrong,
              ),
            ),
            if (arriving) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '내릴 준비를 해주세요',
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            _footer(status),
          ],
        );
      case TripPhase.transfer:
        return _message(
          title: '${status.eventStop} 도착 — 갈아탈 시간이에요',
          subtitle: '다음 구간 차량에 탑승하면 아래를 눌러주세요',
          button: AppButton(
            label: '다음 구간 탔어요',
            block: true,
            onPressed: () => unawaited(_advanceLeg()),
          ),
        );
      case TripPhase.done:
        return _message(
          title: '목적지에 도착했어요',
          subtitle: '오늘도 놓치지 않았어요 — 수고했어요!',
          button: AppButton(label: '완료', block: true, onPressed: () => unawaited(_end())),
        );
      case TripPhase.lost:
        return _message(
          title: '추적할 수 없어요',
          subtitle: '실시간 정보가 끊겼어요 — 역 안내방송을 확인해주세요',
          button: null,
        );
    }
  }

  Widget _message({
    required String title,
    required String subtitle,
    required Widget? button,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, textAlign: TextAlign.center, style: AppTypo.title),
        const SizedBox(height: AppSpace.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
        ),
        if (button != null) ...[const SizedBox(height: AppSpace.lg), button],
      ],
    );
  }

  Widget _footer(TripStatus status) {
    return Text(
      _stale
          ? '갱신 지연 — 마지막 정보를 표시하고 있어요'
          : '${formatFetchedAt(status.fetchedAt)} 기준'
                '${status.realtimeAvailable ? '' : ' · 실시간 정보 없음'}',
      style: AppTypo.caption.copyWith(
        color: _stale ? context.colors.cautionStrong : context.colors.inkFaint,
      ),
    );
  }
}
