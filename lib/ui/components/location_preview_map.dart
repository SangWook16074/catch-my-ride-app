import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../design/tokens.dart';

/// 등록된 집 위치 미리보기 — 미니앱 LocationPreviewMap.tsx 이식.
/// 서버(API.md §6) 네이버 Static Map 프록시 이미지를 쓰고, 실패하면 좌표 폴백을 보여준다.
/// (실서버 미연동 mock 모드에서는 항상 폴백이 보인다 — 지도는 Platform View 허용 목록이지만
/// MVP 미리보기는 정적 이미지로 충분해 네이티브 지도 SDK를 아직 쓰지 않는다.)
class LocationPreviewMap extends StatelessWidget {
  const LocationPreviewMap({super.key, required this.point});

  final GeoPoint point;

  static const String _baseUrl = 'https://catchmyride.hansw.dev';

  @override
  Widget build(BuildContext context) {
    final url =
        '$_baseUrl/api/v1/map-preview?lat=${point.latitude}&lng=${point.longitude}&w=600&h=320&level=16';
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(context),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _fallback(context),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      color: context.colors.fill,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.place_outlined, color: context.colors.inkSubtle),
          const SizedBox(height: AppSpace.xs),
          Text(
            '위도 ${point.latitude.toStringAsFixed(5)} · '
            '경도 ${point.longitude.toStringAsFixed(5)}',
            style: AppTypo.caption.copyWith(color: context.colors.inkMuted),
          ),
        ],
      ),
    );
  }
}
