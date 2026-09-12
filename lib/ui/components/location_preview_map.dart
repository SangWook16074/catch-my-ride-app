import 'package:flutter/material.dart';

import '../../data/api.dart' show mapPreviewUrl;
import '../../domain/models.dart';
import '../design/tokens.dart';

/// 등록된 집 위치 미리보기 — 미니앱 LocationPreviewMap.tsx 이식.
/// 서버(API.md §6) 네이버 Static Map 프록시 이미지를 쓰고, 실패하면 좌표 폴백을 보여준다.
/// (지도는 Platform View 허용 목록이지만 MVP 미리보기는 정적 이미지로 충분해
/// 네이티브 지도 SDK를 아직 쓰지 않는다.)
class LocationPreviewMap extends StatelessWidget {
  const LocationPreviewMap({super.key, required this.point});

  final GeoPoint point;

  /// NCP Static Map은 다크 스타일이 없어 이미지가 항상 라이트다 —
  /// 다크 모드에서 흰 지도가 화면을 때리지 않게 밝기만 낮춘다 (라벨 가독성은 유지).
  static const ColorFilter _dimForDark = ColorFilter.matrix([
    0.72, 0, 0, 0, 0, //
    0, 0.72, 0, 0, 0, //
    0, 0, 0.72, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final url = mapPreviewUrl(point);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget map = Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _fallback(context),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _fallback(context),
    );
    if (isDark) {
      map = ColorFiltered(colorFilter: _dimForDark, child: map);
    }

    return Container(
      // 다크에서 어두워진 지도가 배경에 뭉개지지 않게 테두리로 면을 잡아준다
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.colors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg - 1),
        child: SizedBox(height: 160, width: double.infinity, child: map),
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
