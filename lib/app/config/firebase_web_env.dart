import 'package:firebase_core/firebase_core.dart';

class FirebaseWebEnv {
  static FirebaseOptions? _options;
  
  static Future<void> load() async {
    // Use the same config from web/index.html
    _options = const FirebaseOptions(
      apiKey: 'AIzaSyBy7DgF8Vk39ek75gO7iIi_f8spwDJbgLY',
      authDomain: 'weafrica-music-85cdc.firebaseapp.com',
      projectId: 'weafrica-music-85cdc',
      storageBucket: 'weafrica-music-85cdc.firebasestorage.app',
      messagingSenderId: '985705961084',
      appId: '1:985705961084:web:b494fce32e4a41b8c45bf9',
    );
  }
  
  static FirebaseOptions? tryOptions() {
    return _options;
  }
}
