// Public Firebase web SDK config for project zentho-db83e (Spark).
// The apiKey in this file is the public client SDK key, not a secret.
// Never commit a service-account JSON. Analytics is off (no measurementId).
//
// Console setup is done (do not recreate):
// - Web app nickname "Zentho Web" (Hosting not used)
// - Google sign-in enabled
// - Authorized domains include michaelady.github.io and localhost
// - Firestore default DB, Standard, eur3, production mode
// - firestore.rules published (uid-only on users/{userId}/**;
//   unsigned household invites on households/{id})

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

abstract final class DefaultFirebaseOptions {
  /// True once [web] has a real apiKey, appId, and projectId.
  static bool get isConfigured {
    final options = web;
    return options.apiKey.isNotEmpty &&
        options.appId.isNotEmpty &&
        options.projectId.isNotEmpty;
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // Native targets compile against the public web SDK config until
    // platform-specific FlutterFire apps are added. Google sign-in on web
    // (GitHub Pages) is the supported success path for this release.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCZel_O8VXFdC_wuJoDXH1nDAiUEel9lho',
    appId: '1:1086631824200:web:f93c573a3f71271053c17d',
    messagingSenderId: '1086631824200',
    projectId: 'zentho-db83e',
    authDomain: 'zentho-db83e.firebaseapp.com',
    storageBucket: 'zentho-db83e.firebasestorage.app',
  );
}
