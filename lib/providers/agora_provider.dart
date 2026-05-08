import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/agora_service_export.dart';

// This automatically uses the right implementation for each platform
final agoraServiceProvider = Provider((ref) {
  // The exported AgoraService class will be either:
  // - Original native version on Android/iOS
  // - Web version on Chrome
  return AgoraService();
});
