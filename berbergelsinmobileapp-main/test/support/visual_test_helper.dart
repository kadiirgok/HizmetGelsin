import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:berbergelsin/core/theme/app_theme.dart';

/// Loads Roboto and MaterialIcons fonts safely across local SDK caches,
/// environment variables, and worktree execution contexts.
Future<void> loadTestFonts() async {
  final robotoCandidates = <String>[];
  if (Platform.environment.containsKey('FLUTTER_ROOT')) {
    final root = Platform.environment['FLUTTER_ROOT']!;
    robotoCandidates.add('$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
  }
  robotoCandidates.addAll([
    r'.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
    r'..\berbergelsinmobileapp-main\.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
    r'C:\tmp\flutter-sdk\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
    r'D:\berbergelsin\berbergelsinmobileapp-main\berbergelsinmobileapp-main\.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\Roboto-Regular.ttf',
  ]);

  for (final path in robotoCandidates) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      final fontData = ByteData.view(Uint8List.fromList(bytes).buffer);
      await (FontLoader('Roboto')..addFont(Future.value(fontData))).load();
      await (FontLoader('Ahem')..addFont(Future.value(fontData))).load();
      break;
    }
  }

  final iconCandidates = <String>[];
  if (Platform.environment.containsKey('FLUTTER_ROOT')) {
    final root = Platform.environment['FLUTTER_ROOT']!;
    iconCandidates.add('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    iconCandidates.add('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  }
  iconCandidates.addAll([
    r'.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    r'.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'..\berbergelsinmobileapp-main\.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    r'C:\tmp\flutter-sdk\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    r'D:\berbergelsin\berbergelsinmobileapp-main\berbergelsinmobileapp-main\.flutter-sdk-fast\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
  ]);

  for (final path in iconCandidates) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      final fontData = ByteData.view(Uint8List.fromList(bytes).buffer);
      await (FontLoader('MaterialIcons')..addFont(Future.value(fontData))).load();
      break;
    }
  }
}

/// Returns a deterministic ThemeData with Roboto applied to all text and button styles.
ThemeData getVisualTestTheme() {
  final base = AppTheme.light;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStateProperty.all(
          (base.filledButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
              .copyWith(fontFamily: 'Roboto'),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStateProperty.all(
          (base.outlinedButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
              .copyWith(fontFamily: 'Roboto'),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: WidgetStateProperty.all(
          (base.textButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
              .copyWith(fontFamily: 'Roboto'),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base.elevatedButtonTheme.style?.copyWith(
        textStyle: WidgetStateProperty.all(
          (base.elevatedButtonTheme.style?.textStyle?.resolve({}) ?? AppTypography.labelLarge)
              .copyWith(fontFamily: 'Roboto'),
        ),
      ),
    ),
  );
}

/// Configures deterministic viewport dimensions on a [WidgetTester].
void configureVisualTestViewport(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double devicePixelRatio = 1.0,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = devicePixelRatio;
}

/// Wraps a target widget in a deterministic MaterialApp test harness.
Widget buildVisualTestHarness({
  required Widget child,
  ThemeData? theme,
  Locale locale = const Locale('tr', 'TR'),
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    theme: theme ?? getVisualTestTheme(),
    home: child,
  );
}
