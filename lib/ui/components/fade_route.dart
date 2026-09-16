/// 페이드 페이지 전환 — "여정 만들기"처럼 새 흐름으로 부드럽게 넘어가는 진입에 쓴다
/// (오너 결정 2026-09-16). 기본 push 전환(iOS 스와이프 백 포함)을 대체하므로
/// 목록↔상세 같은 일반 내비게이션에는 쓰지 않는다.
library;

import 'package:flutter/material.dart';

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 180),
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: CurveTween(curve: Curves.easeOut).animate(animation),
        child: child,
      ),
);
