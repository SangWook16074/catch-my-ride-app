import 'package:catch_my_ride/ui/design/components/button.dart';
import 'package:catch_my_ride/ui/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 로딩 전환 시 버튼 제약이 변하지 않아야 한다 —
// 스피너로 교체되며 크기가 줄면 옆 위젯이 움직여 이질적이다 (2026-09-09 오너 피드백).

void main() {
  testWidgets('로딩 중에도 버튼 크기가 변하지 않는다', (tester) async {
    Future<Size> sizeOf({required bool loading}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: AppButton(label: '검색', loading: loading, onPressed: () {}),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(FilledButton));
    }

    final normal = await sizeOf(loading: false);
    final loading = await sizeOf(loading: true);
    expect(loading, normal);
  });
}
