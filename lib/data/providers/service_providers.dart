import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/agora_service.dart';
import '../services/live_session_service.dart';
import '../services/realtime/presence_reconciliation_service.dart';
import '../services/realtime/viewer_tracking_service.dart';
import '../services/realtime/comment_stream_service.dart';

/// Provider for the AgoraService singleton.
final agoraServiceProvider = Provider<AgoraService>((ref) {
  final svc = AgoraService();
  ref.onDispose(() {
    svc.dispose();
  });
  return svc;
});

/// Provider for PresenceReconciliationService.
final presenceReconciliationProvider = Provider<PresenceReconciliationService>((ref) {
  final supabase = Supabase.instance.client;
  final agora = ref.read(agoraServiceProvider);
  final svc = PresenceReconciliationService(supabase, agora);
  ref.onDispose(() => svc.dispose());
  return svc;
});

/// Provider for ViewerTrackingService.
final viewerTrackingProvider = Provider<ViewerTrackingService>((ref) {
  final supabase = Supabase.instance.client;
  final svc = ViewerTrackingService(supabase);
  ref.onDispose(() {});
  return svc;
});

/// Provider for CommentStreamService.
final commentStreamProvider = Provider<CommentStreamService>((ref) {
  final supabase = Supabase.instance.client;
  final svc = CommentStreamService(supabase);
  ref.onDispose(() {});
  return svc;
});

/// Provider for LiveSessionService
final liveSessionService = Provider<LiveSessionService>((ref) {
  return LiveSessionService();
});

/// Provider for Agora initialization state
final agoraInitializedProvider = FutureProvider<void>((ref) async {
  final agora = ref.read(agoraServiceProvider);
  await agora.initialize();
});

/// Provider for remote UID
final remoteUidProvider = Provider<int?>((ref) {
  return ref.watch(agoraServiceProvider).remoteUid.value;
});

/// Provider for isJoined state
final isJoinedProvider = Provider<bool>((ref) {
  return ref.watch(agoraServiceProvider).isJoined.value;
});
