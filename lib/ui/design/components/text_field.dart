import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';

/// 연한 채움 배경의 라운드 입력 필드
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.placeholder,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.maxLength,
    this.numberOnly = false,
    this.textInputAction,
  });

  final String placeholder;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool numberOnly;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: numberOnly ? TextInputType.number : keyboardType,
      inputFormatters: numberOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      maxLength: maxLength,
      textInputAction: textInputAction,
      style: AppTypo.body,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: AppTypo.body.copyWith(color: context.colors.inkSubtle),
        filled: true,
        fillColor: context.colors.fill,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.colors.primary),
        ),
      ),
    );
  }
}
