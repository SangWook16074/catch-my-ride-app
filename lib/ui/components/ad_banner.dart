/// 애드몹 배너 한 칸 — 각 탭 스크롤의 "콘텐츠 끝" 자연 경계에만 둔다 (오너 결정
/// 2026-09-15: 수익과 무해함의 균형 — 핵심 정보(도착 목록·트립 진행)를 밀어내거나
/// 가리지 않는다. 트립 진행·온보딩 화면에는 광고를 두지 않는다).
///
/// 로드 실패·플러그인 부재(테스트 환경)면 자리 자체를 접는다 — 빈 회색 칸을 남기지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../platform/ads.dart';
import '../design/tokens.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ad = BannerAd(
      adUnitId: Ads.bannerUnitId,
      size: AdSize.banner,
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
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      child: Center(
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
