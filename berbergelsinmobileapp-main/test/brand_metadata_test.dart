import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('releasetest uses required release signing without debug fallback', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('check(keystorePropertiesFile.exists())'));
    final flavor = gradle.substring(gradle.indexOf('create("releasetest")'));
    expect(
      flavor,
      contains('signingConfig = signingConfigs.getByName("release")'),
    );
    expect(
      gradle,
      contains(
        'variant.signingConfig?.setConfig(android.signingConfigs.getByName("release"))',
      ),
    );
    expect(flavor, contains('applicationIdSuffix = ".releasetest"'));
  });

  test('DeepLinkCoordinator uses ChangeNotifierProvider at app root', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('ChangeNotifierProvider<DeepLinkCoordinator>.value'));
    expect(
      main,
      isNot(contains('RepositoryProvider.value(value: _deepLinks)')),
    );
  });
  String read(String path) => File(path).readAsStringSync();

  test('root app title is HizmetGelsin', () {
    expect(read('lib/main.dart'), contains("title: 'HizmetGelsin'"));
  });

  test('active Flutter UI contains accepted brand HizmetGelsin in splash and auth components', () {
    final splashSource = read('lib/features/auth/screens/splash_screen.dart');
    final authWidgetSource = read('lib/features/auth/widgets/auth_widgets.dart');
    expect(splashSource, contains('HizmetGelsin'));
    expect(authWidgetSource, contains('HizmetGelsin'));
  });

  test('active user-facing Flutter UI does not contain legacy brand BerberGelsin', () {
    final splashSource = read('lib/features/auth/screens/splash_screen.dart');
    final authWidgetSource = read('lib/features/auth/widgets/auth_widgets.dart');
    final mainSource = read('lib/main.dart');

    expect(splashSource, isNot(contains("Text('BerberGelsin'")));
    expect(authWidgetSource, isNot(contains("Text('BerberGelsin'")));
    expect(authWidgetSource, isNot(contains("semanticLabel: 'BerberGelsin")));
    expect(mainSource, isNot(contains("title: 'BerberGelsin'")));
  });

  test('Android app name, manifest label and iOS display name use HizmetGelsin', () {
    expect(
      read('android/app/src/main/res/values/strings.xml'),
      contains('<string name="app_name">HizmetGelsin</string>'),
    );
    expect(
      read('android/app/src/main/AndroidManifest.xml'),
      contains('android:label="@string/app_name"'),
    );
    expect(
      read('ios/Runner/Info.plist'),
      contains('<key>CFBundleDisplayName</key>\n\t<string>HizmetGelsin</string>'),
    );
  });

  test('splash background is white in light and dark mode', () {
    expect(
      read('android/app/src/main/res/values/colors.xml'),
      contains('<color name="splash_background">#FFFFFF</color>'),
    );
    for (final path in [
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final source = read(path);
      expect(
        source,
        contains(
          '<item name="android:windowSplashScreenBackground">@color/splash_background</item>',
        ),
        reason: path,
      );
      expect(source, contains('@drawable/splash_logo'), reason: path);
    }
  });

  test('dedicated splash drawable is used on Android 11 and lower', () {
    expect(
      File(
        'android/app/src/main/res/drawable-nodpi/splash_logo.png',
      ).existsSync(),
      isTrue,
    );
    for (final path in [
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ]) {
      expect(read(path), contains('@drawable/splash_logo'), reason: path);
    }
  });

  test('AndroidX SplashScreen is installed before super.onCreate', () {
    expect(
      read('android/app/build.gradle.kts'),
      contains('androidx.core:core-splashscreen:1.0.1'),
    );
    final activities = Directory('android/app/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('MainActivity.kt'));
    expect(activities, isNotEmpty);
    final source = activities.first.readAsStringSync();
    expect(source, contains('installSplashScreen()'));
    expect(
      source.indexOf('installSplashScreen()'),
      lessThan(source.indexOf('super.onCreate(savedInstanceState)')),
    );
  });
}
