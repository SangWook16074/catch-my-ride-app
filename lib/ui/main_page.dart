import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../domain/live_view.dart';
import '../domain/models.dart';
import 'design/components/button.dart';
import 'design/components/card.dart';
import 'design/tokens.dart';

/// 메인 탭 — 각 섹션의 요약(대시보드). 지금은 놓치지마 요약 섹션 하나.
///
/// 요약 카드는 통째로 탭 가능해서 어디를 눌러도 놓치지마 탭으로 넘어간다
/// (오너 요구: 메인 → 놓치지마 전환이 아주 쉬워야 한다).
/// 폴링은 놓치지마 탭(라이브 뷰)의 몫 — 여기는 탭이 활성화될 때·당겨서 새로고침만 한다.
class MainPage extends StatefulWidget {
  const MainPage({
    super.key,
    required this.active,
    required this.onOpenCatch,
  });

  /// 이 탭이 현재 보이는지 — 보이게 되는 순간 요약을 새로 불러온다
  final bool active;

  /// 놓치지마 탭으로 전환
  final VoidCallback onOpenCatch;

  @override
  State<MainPage> createState() => _MainPageState();
}

enum _SummaryPhase { loading, empty, ready, failed }

class _MainPageState extends State<MainPage> {
  _SummaryPhase _phase = _SummaryPhase.loading;
  CommuteRoute? _route;
  ArrivalsResponse? _response;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 다른 탭에 있다 돌아왔을 때 — 요약이 낡아 있지 않게 조용히 갱신
    if (widget.active && !oldWidget.active) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final routes = await api.listCommuteRoutes();
      if (!mounted) {
        return;
      }
      if (routes.isEmpty) {
        setState(() => _phase = _SummaryPhase.empty);
        return;
      }
      final route = routes.first;
      final response = await api.getArrivals(route.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _route = route;
        _response = response;
        _stale = false;
        _phase = _SummaryPhase.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == ApiException.settingNotFound) {
        setState(() => _phase = _SummaryPhase.empty);
        return;
      }
      _markStale();
    } catch (_) {
      if (!mounted) {
        return;
      }
      _markStale();
    }
  }

  /// 실패 시 마지막 정보를 유지하고 갱신 지연만 표시한다 (NFR-07과 동일한 태도)
  void _markStale() {
    setState(() {
      if (_response != null) {
        _stale = true;
      } else {
        _phase = _SummaryPhase.failed;
      }
    });
  }

  void _openCatch() {
    HapticFeedback.selectionClick();
    widget.onOpenCatch();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppSpace.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(child: Text('놓치지마', style: AppTypo.title)),
                  GestureDetector(
                    onTap: _openCatch,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Text(
                          '전체 보기',
                          style: AppTypo.bodySm.copyWith(
                            color: context.colors.inkMuted,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: context.colors.inkMuted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(onTap: _openCatch, child: _summaryCard()),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    switch (_phase) {
      case _SummaryPhase.loading:
        return AppCard(
          child: Text(
            '도착 정보를 불러오고 있어요…',
            style: AppTypo.bodySm.copyWith(color: context.colors.inkSubtle),
          ),
        );
      case _SummaryPhase.failed:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('요약을 불러오지 못했어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '네트워크를 확인하고 다시 시도해주세요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(
                label: '다시 시도',
                variant: AppButtonVariant.tonal,
                medium: true,
                onPressed: () => unawaited(_load()),
              ),
            ],
          ),
        );
      case _SummaryPhase.empty:
        return AppCard(
          tone: AppCardTone.brand,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('아직 통근 설정이 없어요', style: AppTypo.heading),
              const SizedBox(height: AppSpace.xs),
              Text(
                '경로를 등록하면 다음 도착과 출발 타이밍을\n여기서 바로 볼 수 있어요',
                style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              AppButton(
                label: '설정 시작하기',
                medium: true,
                onPressed: _openCatch,
              ),
            ],
          ),
        );
      case _SummaryPhase.ready:
        return _readyCard();
    }
  }

  Widget _readyCard() {
    final route = _route!;
    final response = _response!;
    final best = pickBestBoardable(response.arrivals);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: context.colors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  route.label,
                  style: AppTypo.caption.copyWith(
                    color: context.colors.primaryStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.colors.inkSubtle,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (best == null) ...[
            const Text('지금 탈 수 있는 차가 없어요', style: AppTypo.heading),
            const SizedBox(height: AppSpace.xs),
            Text(
              '눌러서 전체 도착 정보를 확인하세요',
              style: AppTypo.caption.copyWith(color: context.colors.inkSubtle),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    best.routeName,
                    style: AppTypo.heading,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Text(
                  formatRemaining(best.secondsToArrival),
                  style: AppTypo.title.copyWith(
                    color: context.colors.primaryStrong,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${best.stopDisplayName} · ${statusLabel(best.status)}',
              style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
            ),
          ],
          const SizedBox(height: AppSpace.md),
          Text(
            _stale
                ? '갱신 지연 — 마지막 정보를 표시하고 있어요'
                : '도보 ${response.walkMinutes}분 · ${formatFetchedAt(response.fetchedAt)} 기준',
            style: AppTypo.caption.copyWith(
              color: _stale
                  ? context.colors.cautionStrong
                  : context.colors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
