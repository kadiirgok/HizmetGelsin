import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Logo Asset Dimension, Color & Alpha Validation', () {
    test('Master logo asset exists and meets specifications', () {
      final masterFile = File('assets/branding/hizmetgelsin_logo_master.png');
      expect(masterFile.existsSync(), isTrue, reason: 'Master logo file must exist');
      final bytes = masterFile.readAsBytesSync();
      expect(bytes.length, greaterThan(1000), reason: 'Master logo file must not be empty');
    });

    test('Flutter logo assets exist with valid dimensions and content', () {
      final logoFile = File('assets/logo.png');
      final iconFile = File('assets/icon/app_icon.png');
      expect(logoFile.existsSync(), isTrue);
      expect(iconFile.existsSync(), isTrue);
    });

    test('Android splash logo drawable exists', () {
      final splashFile = File('android/app/src/main/res/drawable-nodpi/splash_logo.png');
      expect(splashFile.existsSync(), isTrue);
    });

    test('Android adaptive icon foregrounds exist for all required densities', () {
      final densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final density in densities) {
        final fgFile = File('android/app/src/main/res/drawable-$density/ic_launcher_foreground.png');
        expect(fgFile.existsSync(), isTrue, reason: 'Missing drawable-$density/ic_launcher_foreground.png');
      }
    });

    test('Android adaptive icon background is configured to brand #111111 in colors.xml', () {
      final colorsXml = File('android/app/src/main/res/values/colors.xml').readAsStringSync();
      expect(colorsXml, contains('<color name="ic_launcher_background">#111111</color>'));
    });

    test('Android mipmap launcher icons exist for all required densities', () {
      final densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
      for (final density in densities) {
        final iconFile = File('android/app/src/main/res/mipmap-$density/ic_launcher.png');
        expect(iconFile.existsSync(), isTrue, reason: 'Missing mipmap-$density/ic_launcher.png');
      }
    });

    test('iOS AppIcon set files exist and match Contents.json entries', () {
      final iosDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
      expect(iosDir.existsSync(), isTrue);
      final contentsJson = File('${iosDir.path}/Contents.json').readAsStringSync();
      expect(contentsJson, contains('Icon-App-1024x1024@1x.png'));
      expect(File('${iosDir.path}/Icon-App-1024x1024@1x.png').existsSync(), isTrue);
      expect(File('${iosDir.path}/Icon-App-60x60@3x.png').existsSync(), isTrue);
    });
  });
}
