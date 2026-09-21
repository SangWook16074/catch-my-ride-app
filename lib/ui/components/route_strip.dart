/// 구간 스트립 — 탑승역→하차역 사이를 이동 중이라는 맥락을 채워준다. 트립 화면("위치 확인 중")과
/// 메인 하차 알림 카드가 공용 (오너 요청 2026-09-21: 메인에도 같은 애니메이션).
/// 열차 위치는 표현하지 않는다 — 점이 진행 방향으로 흘렀다 사라지는 불확정 애니메이션까지만,
/// 특정 위치를 아는 척하지 않는다 (NFR-03)
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';

class RouteStrip extends StatefulWidget {
  const RouteStrip({
    super.key,
    required this.boardStop,
    required this.eventStop,
    required this.line,
  });

  final String boardStop;
  final String eventStop;
  final String line;

  @override
  State<RouteStrip> createState() => RouteStripState();
}

class RouteStripState extends State<RouteStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Row(
          children: [
            Text(widget.boardStop, style: AppTypo.heading),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  size: const Size(double.infinity, 20),
                  painter: _RouteStripPainter(
                    t: _controller.value,
                    track: colors.line,
                    brand: colors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Text(widget.eventStop, style: AppTypo.heading),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          widget.line,
          style: AppTypo.caption.copyWith(color: colors.inkSubtle),
        ),
      ],
    );
  }
}

class _RouteStripPainter extends CustomPainter {
  _RouteStripPainter({
    required this.t,
    required this.track,
    required this.brand,
  });

  /// 애니메이션 진행(0~1) — 점 위치·양끝 페이드에 함께 쓴다
  final double t;
  final Color track;
  final Color brand;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const endRadius = 4.0;
    final start = Offset(endRadius, y);
    final end = Offset(size.width - endRadius, y);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = track
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    // 탑승역(지나온 곳)은 채운 점, 하차역(갈 곳)은 링
    canvas.drawCircle(start, endRadius, Paint()..color = brand);
    canvas.drawCircle(
      end,
      endRadius,
      Paint()
        ..color = brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final progress = Curves.easeInOut.transform(t);
    final opacity = t < 0.15
        ? t / 0.15
        : t > 0.85
        ? (1 - t) / 0.15
        : 1.0;
    final x = start.dx + (end.dx - start.dx) * progress;
    canvas.drawCircle(
      Offset(x, y),
      9,
      Paint()..color = brand.withValues(alpha: 0.25 * opacity),
    );
    canvas.drawCircle(
      Offset(x, y),
      5,
      Paint()..color = brand.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_RouteStripPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.track != track ||
      oldDelegate.brand != brand;
}
