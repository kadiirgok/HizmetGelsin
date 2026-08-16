// Bu şablonu kopyalayıp gerçek değerlerle doldurarak `firebase_options.dart` üretin:
//   1. cp lib/firebase_options.example.dart lib/firebase_options.dart
//   2. Aşağıdaki `REPLACE_...` yer tutucularını kendi Firebase proje değerlerinizle değiştirin
//   (veya FlutterFire CLI ile: flutterfire configure)
// Gerçek `firebase_options.dart` git'e girmez (.gitignore'da).
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_API_KEY',
    appId: '1:REPLACE_PROJECT_NUMBER:android:REPLACE_APP_ID',
    messagingSenderId: 'REPLACE_PROJECT_NUMBER',
    projectId: 'REPLACE_PROJECT_ID',
    storageBucket: 'REPLACE_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_IOS_API_KEY',
    appId: '1:REPLACE_PROJECT_NUMBER:ios:REPLACE_APP_ID',
    messagingSenderId: 'REPLACE_PROJECT_NUMBER',
    projectId: 'REPLACE_PROJECT_ID',
    storageBucket: 'REPLACE_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.app',
  );
}
