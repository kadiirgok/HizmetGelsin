import 'package:flutter/material.dart';

/// BerberGelsin'in açık tema tasarım tokenları — siyah-beyaz minimalist.
abstract final class AppColors {
  static const primary = Color(0xFF111111);
  static const primaryContainer = Color(0xFFF0F0F0);
  static const secondary = Color(0xFF444444);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF5F5F5);
  static const background = Color(0xFFFAFAFA);
  static const error = Color(0xFFBA1A1A);
  static const success = Color(0xFF267A45);
  static const warning = Color(0xFF9A5B00);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF6B6B6B);
  static const border = Color(0xFFE0E0E0);
  static const disabled = Color(0xFFB8B8B8);
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 200);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 300);
}

abstract final class AppBreakpoints {
  static const compact = 360.0;
  static const medium = 600.0;
  static const expanded = 840.0;
}

abstract final class AppIcons {
  static const home = Icons.home_outlined;
  static const explore = Icons.explore_outlined;
  static const appointments = Icons.calendar_month_outlined;
  static const favorites = Icons.favorite_border;
  static const profile = Icons.person_outline;
  static const location = Icons.location_on_outlined;
  static const search = Icons.search;
}

abstract final class AppTypography {
  static const display = TextStyle(
    fontSize: 36,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );
  static const headline = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );
  static const titleLarge = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );
  static const titleMedium = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );
  static const bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
  static const bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );
  static const bodySmall = TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );
  static const labelLarge = TextStyle(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );
  static const labelMedium = TextStyle(
    fontSize: 14,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );

  static const textTheme = TextTheme(
    displayLarge: display,
    headlineMedium: headline,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
  );
}

class AppTheme {
  // Backward-compatible aliases while legacy screens are migrated incrementally.
  static const primary = AppColors.primary;
  static const accent = AppColors.secondary;
  static const surface = AppColors.surface;
  static const fieldFill = AppColors.surfaceVariant;
  static const textSecondary = AppColors.textSecondary;

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.textPrimary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceVariant,
      error: AppColors.error,
      onSurface: AppColors.textPrimary,
      outline: AppColors.border,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.titleMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: AppTypography.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
