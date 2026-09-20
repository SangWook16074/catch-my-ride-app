/// 애드몹 배너 한 칸 — 각 탭 스크롤 콘텐츠의 정해진 자리(내정보 탭 제외)에 깔리고,
/// 트립 진행 화면은 종료 버튼 위 MREC(300×250, 동영상 크리에이티브 가능).
/// 셸 하단 플로팅은 폐기(오너 결정 2026-09-19) — 배너는 화면에 고정하지 않는다.
/// 온보딩 금지는 유지. 무해함 원칙: 핵심 정보를 가리지도, 밀어내지도 않는다.
///
/// [size]로 칸 크기를 고른다 — 기본 320×50([AdSize.banner]),
/// 트립 화면은 [AdSize.mediumRectangle](300×250).
///
/// 로드 실패·플러그인 부재(테스트 환경)면 자리 자체를 접는다 — 빈 회색 칸을 남기지 않는다.
/// 예외: [reserveSpace]가 켜지면 로드 전·실패에도 칸 크기를 그대로 잡아둔다 —
/// 스크롤 없는 고정 레이아웃(트립 화면)에서 로드 순간 UI가 밀리는 것 방지
/// (오너 피드백 2026-09-19 3차).
///
/// 배너는 어떤 경우에도 요청한 칸 밖을 그리면 안 된다 (2026-09-19 실기 관측:
/// 트립 시작 라우트 전환 중에 네이티브 광고 뷰가 화면 전체를 덮음) —
/// 라우트 전환이 끝난 뒤에만 AdWidget을 붙이고, ClipRect로 칸 밖 페인트를 자른다.
library;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../platform/ads.dart';
import '../design/tokens.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key, this.size = AdSize.banner, this.reserveSpace = false});

  /// 광고 칸 크기 — 기본 320×50, 트립 화면은 [AdSize.mediumRectangle]
  final AdSize size;

  /// 로드 전·실패에도 [size]만큼 자리를 잡아둔다 — 고정 레이아웃에서 UI 밀림 방지.
  /// 스크롤 콘텐츠에서는 기본값(false = 접기) 유지
  final bool reserveSpace;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  /// 진입 라우트 전환이 끝났는가 — 끝나기 전에는 AdWidget(플랫폼 뷰)을 붙이지 않는다.
  /// 전환 애니메이션 중에 붙은 네이티브 뷰가 변환을 무시하고 전체 화면을 덮는 사고 방지
  bool _routeSettled = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    if (Ads.disabled) {
      return; // DISABLE_ADS — 자리 자체를 접는다 (로드 실패와 동일한 강등)
    }
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSettled || _routeAnimation != null) {
      return;
    }
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _routeSettled = true;
      return;
    }
    _routeAnimation = animation;
    animation.addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    if (mounted) {
      setState(() => _routeSettled = true);
    }
  }

  Future<void> _load() async {
    final ad = BannerAd(
      adUnitId: Ads.bannerUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _loaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    try {
      await ad.load();
    } catch (_) {
      // 플러그인 부재(위젯 테스트)·초기화 전 호출 — 광고 없이 조용히 접는다
      if (mounted) {
        setState(() {
          _ad = null;
          _loaded = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final ready = ad != null && _loaded && _routeSettled;
    if (!ready && !widget.reserveSpace) {
      return const SizedBox.shrink();
    }
    if (!ready) {
      // 자리만 확보 — 로드되면 같은 칸에 광고가 채워져 주변 UI가 움직이지 않는다
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xl,
          vertical: AppSpace.md,
        ),
        child: SizedBox(
          width: widget.size.width.toDouble(),
          height: widget.size.height.toDouble(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      // Center 금지 — bottomNavigationBar처럼 최대 높이가 화면 전체인 슬롯에서
      // Center는 세로로 끝까지 펴져 body를 0으로 짜부라뜨린다 (2026-09-19 트립 화면
      // "광고가 전체를 덮음"의 실제 원인). heightFactor: 1로 자기 높이는 광고만큼만.
      child: Align(
        heightFactor: 1,
        child: ClipRect(
          child: SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
        ),
      ),
    );
  }
}
