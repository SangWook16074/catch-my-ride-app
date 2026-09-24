import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../data/active_trip.dart';
import '../data/api.dart';
import '../domain/journey.dart';
import '../domain/live_view.dart';
import '../domain/models.dart';
import '../data/recent_routes_store.dart';
import '../data/trip_start.dart';
import 'components/ad_banner.dart';
import 'components/route_strip.dart';
import 'components/save_journey_sheet.dart';
import 'design/components/button.dart';
import 'design/components/sheet.dart';
import 'design/tokens.dart';

/// 진행 중 트립 화면 (FR-705) — 남은 정거장 카운트다운, 환승 수동 재개(FR-703).
class TripPage extends StatefulWidget {
  const TripPage({
    super.key,
    required this.tripId,
    // 푸시 딥링크 진입은 여정 라벨을 모른다 — 기능명으로 대체
    this.journeyLabel = '하차 알림',
    this.journeyId,
    this.legs,
  });

  final String tripId;
  final String journeyLabel;

  /// 이 트립의 여정 — 있으면 LOST 화면에서 "처음부터 다시 추적"(같은 여정 재시작)을 제공한다.
  /// 푸시 딥링크 진입 등 모르는 경우 null — 버튼을 숨긴다
  final String? journeyId;

  /// 1회성 트립(FR-708)의 구간 스냅숏 — 여정 없이 시작했으므로 LOST 재시작·구간 표시·
  /// DONE 화면 "이 경로 저장하기"가 이 값을 쓴다. 저장 여정 트립은 null(여정에서 가져온다)
  final List<JourneyLeg>? legs;

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  /// 상태·폴링·잠금화면 표면은 전역 `activeTrip`이 들고 있다 — 이 화면은 구독만 한다.
  /// (오너 피드백 2026-09-22: 화면마다 따로 폴링해서 탭 카드가 낡은 값에 묶였다)
  bool _restarting = false;

  /// 1회성 트립을 완료 후 여정으로 저장했으면 그 라벨 — 저장 버튼을 안내로 바꾼다 (FR-708)
  String? _savedLabel;

  /// 단계 전환 햅틱을 1회만 울리기 위한 직전 단계
  TripPhase? _lastPhase;

  TripStatus? get _status => activeTrip.status;
  List<JourneyLeg>? get _legs => activeTrip.legs;
  bool get _stale => activeTrip.stale;
  bool get _gone => activeTrip.gone;

  /// 구독 중인 전역 트립 컨트롤러 — 구독과 해제가 같은 인스턴스를 향하게 붙잡아 둔다
  late final ActiveTripController _trip;

  @override
  void initState() {
    super.initState();
    _trip = activeTrip;
    _trip.addListener(_onTripChanged);
    _lastPhase = activeTrip.status?.phase;
    // 이어보기·푸시 딥링크로 들어왔을 수도 있다 — 컨트롤러가 이 트립을 추적하게 한다
    unawaited(
      activeTrip.adopt(
        tripId: widget.tripId,
        label: widget.journeyLabel,
        journeyId: widget.journeyId,
        legs: widget.legs,
      ),
    );
  }

  @override
  void dispose() {
    // 폴링은 멈추지 않는다 — 화면을 닫아도 탭 카드·잠금화면은 계속 갱신돼야 한다
    _trip.removeListener(_onTripChanged);
    super.dispose();
  }

  void _onTripChanged() {
    if (!mounted) {
      return;
    }
    // 화면을 보는 중에도 내릴 타이밍을 몸으로 알린다 — 도착 직전·환승·완료로
    // 넘어가는 순간 1회 (2026-09-19 실주행: 푸시만으로는 환승을 놓치기 쉽다)
    final phase = activeTrip.status?.phase;
    final previous = _lastPhase;
    if (phase != null &&
        previous != null &&
        previous != phase &&
        (phase == TripPhase.arriving ||
            phase == TripPhase.transfer ||
            phase == TripPhase.done)) {
      HapticFeedback.heavyImpact();
    }
    _lastPhase = phase;
    setState(() {});
  }

  Future<void> _advanceLeg() async {
    // 햅틱: 환승 재개 확정 (CLAUDE.md 적응형 UI 규칙)
    HapticFeedback.mediumImpact();
    try {
      final status = await advanceTrip(widget.tripId);
      activeTrip.apply(status);
    } catch (_) {
      unawaited(activeTrip.refresh());
    }
  }

  /// 같은 구간으로 재시작할 수 있는가 — 저장 여정이거나 1회성 스냅숏이 있으면
  bool get _canRestart => widget.journeyId != null || widget.legs != null;

  /// 1회성 트립인가 — 여정 없이 스냅숏으로 시작한 트립 (완료 후 저장 제안 대상)
  bool get _isOneOff => widget.journeyId == null && widget.legs != null;

  /// LOST에서 같은 여정(또는 1회성 구간 스냅숏)으로 처음부터 다시 시작 — 기존 트립
  /// 종료(멱등, §9-3) 후 새 트립. 서버가 재목격 복구를 계속 시도하므로(§9-3) 이 버튼은
  /// "기다리기 싫을 때"의 출구다
  Future<void> _restart() async {
    final journeyId = widget.journeyId;
    final legs = widget.legs;
    if (!_canRestart || _restarting) {
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
      final TripStart start;
      if (journeyId != null) {
        start = await startJourneyTrip(journeyId);
      } else {
        start = await startQuickTrip(legs!);
        unawaited(RecentRoutesStore().push(legs));
      }
      // 새 트립으로 갈아탄다 — 보관·잠금화면 표면·폴링을 컨트롤러가 다시 건다
      unawaited(
        activeTrip.begin(
          tripId: start.tripId,
          label: widget.journeyLabel,
          journeyId: journeyId,
          legs: journeyId == null ? legs : null,
        ),
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TripPage(
            tripId: start.tripId,
            journeyLabel: widget.journeyLabel,
            journeyId: journeyId,
            legs: legs,
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

  /// 1회성 트립의 "경로 저장하기" (FR-708 → FR-702) — 트립 중·환승 대기·도착 어디서든.
  /// 라벨만 입력, 10개 초과·중복 라벨은 서버 400 메시지를 그대로 보여준다
  Future<void> _saveAsJourney() async {
    final legs = widget.legs;
    if (legs == null) {
      return;
    }
    final label = await showSaveJourneySheet(context, legs);
    if (label == null || !mounted) {
      return;
    }
    setState(() => _savedLabel = label);
  }

  /// 1회성 트립에만 붙는 저장 행 — 저장 전엔 버튼, 저장 후엔 안내 (오너 화면 재구성 2026-09-21:
  /// 도착 화면에서만 제안하면 앱을 먼저 닫은 사람은 저장 기회를 놓친다)
  Widget? _saveRow() {
    if (!_isOneOff) {
      return null;
    }
    final savedLabel = _savedLabel;
    if (savedLabel != null) {
      return Text(
        '"$savedLabel" 여정으로 저장했어요',
        textAlign: TextAlign.center,
        style: AppTypo.bodySm.copyWith(color: context.colors.primaryStrong),
      );
    }
    // 하단 묶음의 종료 버튼과 같은 크기(block, 기본 높이) — 나란히 둘 때 레이아웃 통일 (오너 피드백 2026-09-21)
    return AppButton(
      label: '경로 저장하기',
      variant: AppButtonVariant.tonal,
      block: true,
      onPressed: () => unawaited(_saveAsJourney()),
    );
  }

  Future<void> _end() async {
    // 종료는 멱등(§9-3) — 실패해도 로컬·표면은 정리되고 화면은 닫는다
    unawaited(activeTrip.finish());
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveRow = _saveRow();
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(widget.journeyLabel, style: AppTypo.heading),
      ),
      // 본문·광고·종료 버튼을 하단에 한 묶음으로 붙인다 — 남는 여백은 요소 사이에
      // 끼우지 않고 위쪽으로만 몬다 (오너 피드백 2026-09-19 2차). 작은 화면에서
      // 묶음이 화면보다 길어지면 넘치는 대신 스크롤로 강등한다
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _body(),
                    // 트립 진행 중에도 광고 노출 (오너 결정 2026-09-16 2차: 트립 화면
                    // 금지 폐기 — 화면을 오래 보는 구간이라 내정보 대신 여기에 둔다).
                    // 종료 버튼 위 MREC(300×250, 동영상 크리에이티브 가능).
                    // reserveSpace: 로드 전에도 300×250 자리를 잡아둔다 — 광고가 늦게
                    // 뜰 때 카운트다운·버튼이 밀리는 것 방지 (오너 피드백 2026-09-19 3차)
                    const AdBanner(size: AdSize.mediumRectangle, reserveSpace: true),
                    // 하단 액션 묶음 — 1회성 저장 행과 종료/완료를 붙여 둔다. 광고가 둘 사이를
                    // 가르지 않게 (오너 피드백 2026-09-21)
                    if (!_gone) ...[
                      if (saveRow != null) ...[saveRow, const SizedBox(height: AppSpace.sm)],
                      if (_status?.phase == TripPhase.done)
                        AppButton(label: '완료', block: true, onPressed: () => unawaited(_end()))
                      else
                        AppButton(
                          label: '경로 종료',
                          variant: AppButtonVariant.danger,
                          block: true,
                          onPressed: () => unawaited(_end()),
                        ),
                    ],
                  ],
                ),
              ),
            ),
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
        button: AppButton(
          label: '돌아가기',
          onPressed: () {
            activeTrip.clearGone();
            Navigator.of(context).pop();
          },
        ),
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
        // 특정 전이라도 서버가 노선 전체 위치로 후보를 목격하면 currentStop을 준다
        // (§9-3 2026-09-16 개정) — 카운트는 몰라도 위치는 보여준다
        final locatedStop = status.currentStop;
        final legs = _legs;
        final leg = legs != null && status.legIndex >= 0 && status.legIndex < legs.length
            ? legs[status.legIndex]
            : null;
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
                  ? (locatedStop != null ? '현재 $locatedStop 부근' : '위치 확인 중이에요…')
                  : '$remaining정거장 남았어요',
              textAlign: TextAlign.center,
              style: AppTypo.title.copyWith(
                color: arriving
                    ? context.colors.cautionStrong
                    : identifying && locatedStop == null
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
            // 특정 후 카운트다운 중 — 열차 현재 위치 역명 (§9-3 currentStop, 모르면 생략)
            if (!arriving && !identifying && locatedStop != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '현재 $locatedStop 부근',
                textAlign: TextAlign.center,
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ],
            if (identifying) ...[
              if (leg != null) ...[
                const SizedBox(height: AppSpace.xl),
                RouteStrip(
                  boardStop: leg.boardStop,
                  eventStop: status.eventStop,
                  line: leg.line,
                ),
              ],
              const SizedBox(height: AppSpace.md),
              Text(
                locatedStop != null
                    ? '하차역에 가까워지면 남은 정거장을 알려드려요'
                    : '탑승한 열차를 찾고 있어요. 곧 남은 정거장을 알려드려요',
                textAlign: TextAlign.center,
                style: AppTypo.bodySm.copyWith(color: context.colors.inkMuted),
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            _footer(status),
          ],
        );
      case TripPhase.transfer:
        return _message(
          title: '${status.eventStop} 도착, 갈아탈 시간이에요',
          subtitle: '다음 구간 차량에 탑승하면 아래를 눌러주세요',
          button: AppButton(
            label: '다음 구간 탔어요',
            block: true,
            onPressed: () => unawaited(_advanceLeg()),
          ),
        );
      case TripPhase.done:
        // 완료 버튼은 하단 액션 묶음(저장 행 옆)에 있다
        return _message(
          title: '목적지에 도착했어요',
          subtitle: '오늘도 놓치지 않았어요. 수고했어요!',
          button: null,
        );
      case TripPhase.lost:
        // 서버가 재목격·재특정을 계속 시도한다 (§9-3) — 신호가 돌아오면 이 화면은 저절로 풀린다
        return _message(
          title: '추적이 잠시 끊겼어요',
          subtitle: '신호가 다시 잡히면 자동으로 이어가요.\n그동안 역 안내방송을 확인해주세요',
          button: !_canRestart
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
          ? '갱신이 늦어져 마지막 정보를 보여드리고 있어요'
          : '${formatFetchedAt(status.fetchedAt)} 기준'
                '${status.realtimeAvailable ? '' : ' · 실시간 정보 없음'}',
      style: AppTypo.caption.copyWith(
        color: _stale ? context.colors.cautionStrong : context.colors.inkFaint,
      ),
    );
  }
}
