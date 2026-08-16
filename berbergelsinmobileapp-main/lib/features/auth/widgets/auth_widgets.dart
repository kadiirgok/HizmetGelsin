import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';

import '../../../core/theme/app_theme.dart';

String normalizeTurkishMobile(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('90') && digits.length > 10) {
    digits = digits.substring(2);
  }
  if (digits.startsWith('0') && digits.length > 10) {
    digits = digits.substring(1);
  }
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

bool isValidTurkishMobile(String value) =>
    RegExp(r'^5[0-9]{9}$').hasMatch(normalizeTurkishMobile(value));

String formatTurkishMobile(String value) {
  final digits = normalizeTurkishMobile(value);
  final groups = <String>[];
  var offset = 0;
  for (final length in const [3, 3, 2, 2]) {
    if (offset >= digits.length) break;
    final end = math.min(offset + length, digits.length);
    groups.add(digits.substring(offset, end));
    offset = end;
  }
  return groups.join(' ');
}

String maskTurkishMobile(String value) {
  final digits = normalizeTurkishMobile(value);
  if (digits.length != 10) return formatTurkishMobile(value);
  return '${digits.substring(0, 1)}** *** ** ${digits.substring(8)}';
}

class TurkishMobilePhoneFormatter extends TextInputFormatter {
  const TurkishMobilePhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatTurkishMobile(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AuthPageBody extends StatelessWidget {
  const AuthPageBody({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.xl,
      AppSpacing.xl,
    ),
    this.maxWidth = 480,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              minHeight: math.max(0, constraints.maxHeight - 40),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({
    super.key,
    this.showName = true,
    this.logoSize = 84,
    this.alignment = CrossAxisAlignment.start,
  });

  final bool showName;
  final double logoSize;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Image.asset(
            'assets/logo.png',
            width: logoSize,
            height: logoSize,
            semanticLabel: 'HizmetGelsin logosu',
          ),
        ),
        if (showName) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            'HizmetGelsin',
            style: AppTypography.display.copyWith(
              letterSpacing: -1,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

class AuthPhoneField extends StatelessWidget {
  const AuthPhoneField({
    required this.controller,
    super.key,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('auth_phone_field'),
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: const [TurkishMobilePhoneFormatter()],
      style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: 'Telefon numarası',
        hintText: '5XX XXX XX XX',
        errorText: errorText,
        counterText: '',
        prefixIcon: const SizedBox(
          width: 64,
          child: Center(
            child: Text('+90', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

class ResponsiveOtpField extends StatelessWidget {
  const ResponsiveOtpField({
    required this.controller,
    required this.onCompleted,
    super.key,
    this.enabled = true,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = ((constraints.maxWidth - (gap * 5)) / 6)
            .clamp(36.0, 52.0)
            .toDouble();
        final baseTheme = PinTheme(
          width: width,
          height: width.clamp(44.0, 54.0).toDouble(),
          textStyle: AppTypography.titleLarge,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );
        PinTheme borderedTheme(Color color, {double borderWidth = 1}) =>
            PinTheme(
              width: width,
              height: width.clamp(44.0, 54.0).toDouble(),
              textStyle: AppTypography.titleLarge,
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: color, width: borderWidth),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            );
        return Semantics(
          label: '6 haneli doğrulama kodu',
          textField: true,
          child: Pinput(
            key: const Key('auth_otp_field'),
            length: 6,
            controller: controller,
            enabled: enabled,
            autofocus: autofocus,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            defaultPinTheme: baseTheme,
            focusedPinTheme: borderedTheme(AppColors.primary, borderWidth: 1.5),
            errorPinTheme: borderedTheme(AppColors.error),
            separatorBuilder: (_) => const SizedBox(width: gap),
            onCompleted: onCompleted,
          ),
        );
      },
    );
  }
}

class LoadingPrimaryButton extends StatelessWidget {
  const LoadingPrimaryButton({
    required this.label,
    required this.onPressed,
    required this.loading,
    super.key,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.25,
                ),
              )
            : Text(label),
      ),
    );
  }
}
