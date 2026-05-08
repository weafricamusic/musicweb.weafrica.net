import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/realtime/viewer_tracking_service.dart';
import 'auth_provider.dart';

final viewerTrackingServiceProvider = Provider<ViewerTrackingService>((ref) {
  return ViewerTrackingService(ref.read(supabaseClientProvider));
});

final viewerCountProvider = StreamProvider.family<int, String>((ref, liveSessionId) {
  return ref.read(viewerTrackingServiceProvider).watchViewerCount(liveSessionId);
});

final joinLiveProvider = Provider<Future<void> Function(String)>((ref) {
  return (String liveSessionId) async {
    final user = ref.read(currentUserProvider).value;
    final service = ref.read(viewerTrackingServiceProvider);
    
    await service.joinLive(
      liveSessionId: liveSessionId,
      userId: user?.id,
      deviceId: 'device_${DateTime.now().millisecondsSinceEpoch}',
    );
  };
});

final leaveLiveProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final service = ref.read(viewerTrackingServiceProvider);
    await service.leaveLive();
  };
});
