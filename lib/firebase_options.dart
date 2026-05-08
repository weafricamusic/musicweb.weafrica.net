import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBy7DgF8Vk39ek75gO7iIi_f8spwDJbgLY',
    authDomain: 'weafrica-music-85cdc.firebaseapp.com',
    projectId: 'weafrica-music-85cdc',
    storageBucket: 'weafrica-music-85cdc.firebasestorage.app',
    messagingSenderId: '985705961084',
    appId: '1:985705961084:web:b494fce32e4a41b8c45bf9',
  );

  static const FirebaseOptions android = web;
  static const FirebaseOptions ios = web;
}
