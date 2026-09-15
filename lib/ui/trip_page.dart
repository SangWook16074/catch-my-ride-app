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
import 'design/components/sheet.dart';
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
    this.journeyId,
  });

  final String tripId;
  final String journeyLabel;

  /// 이 트립의 여정 — 있으면 LOST 화면에서 "처음부터 다시 추적"(같은 여정 재시작)을 제공한다.
  /// 푸시 딥링크 진입 등 모르는 경우 null — 버튼을 숨긴다
  final String? journeyId;

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> with WidgetsBindingObserver {
  final TripStore _tripStore = TripStore();
  final LiveActivityBridge _liveActivity = LiveActivityBridge();
  TripStatus? _status;
  bool _stale = false;
  bool _gone = false;
  bool _restarting = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 잠금화면 표면 시작 (FR-705) — iOS Live Activity / Android 지속 알림, 미지원은 조용히 무시
    unawaited(_liveActivity.start(widget.journeyLabel, tripId: widget.tripId));
    unawaited(_refresh());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 잠금·백그라운드 동안 타이머가 멈춘다 — 돌아오면 다음 틱을 기다리지 않고 즉시 갱신
    // (2026-09-15 실주행 피드백: 지하철에서 폰을 껐다 켜면 화면이 낡아 보였다)
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
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

  /// LOST에서 같은 여정으로 처음부터 다시 시작 — 기존 트립 종료(멱등, §9-3) 후 새 트립.
  /// 서버가 재목격 복구를 계속 시도하므로(§9-3) 이 버튼은 "기다리기 싫을 때"의 출구다
  Future<void> _restart() async {
    final journeyId = widget.journeyId;
    if (journeyId == null || _restarting) {
      return;
    }
    setState(() => _restarting = true);
    HapticFeedback.mediumImpact();
    try {
      await api.endTrip(widget.tripId);
    } catch (_) {
      // 종료 실패해도 진행 — startTrip이 막히면 아래에서 안내한다
    }
    try {
      final start = await api.startTrip(journeyId);
      unawaited(_tripStore.write(start.tripId, journeyId: journeyId));
      unawaited(_liveActivity.end());
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TripPage(
            tripId: start.tripId,
            journeyLabel: widget.journeyLabel,
            journeyId: journeyId,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _restarting = false);
      _showMessage('다시 시작할 수 없어요', error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _restarting = false);
      _showMessage('다시 시작할 수 없어요', '네트워크를 확인하고 다시 시도해주세요');
    }
  }

  void _showMessage(String header, String body) {
    unawaited(
      showAppSheet<void>(
        context: context,
        header: header,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: Text(
            body,
            style: AppTypo.bodySm.copyWith(color: sheetContext.colors.inkMuted),
          ),
        ),
      ),
    );
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
        // 서버가 재목격·재특정을 계속 시도한다 (§9-3) — 신호가 돌아오면 이 화면은 저절로 풀린다
        return _message(
          title: '추적이 잠시 끊겼어요',
          subtitle: '신호가 다시 잡히면 자동으로 이어가요.\n그동안 역 안내방송을 확인해주세요',
          button: widget.journeyId == null
              ? null
              : AppButton(
                  label: _restarting ? '다시 시작하는 중…' : '처음부터 다시 추적',
                  variant: AppButtonVariant.tonal,
                  block: true,
                  onPressed: _restarting ? null : () => unawaited(_restart()),
                ),
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
