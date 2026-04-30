import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/live_session_model.dart';
import '../data/repositories/live_session_repository.dart';

/// Provider for live session repository
final liveSessionRepositoryProvider = Provider<LiveSessionRepository>((ref) {
  return LiveSessionRepository();
});

/// Provider for active live sessions
final liveSessionsProvider = FutureProvider<List<LiveSessionModel>>((ref) async {
  final repository = ref.watch(liveSessionRepositoryProvider);
  return await repository.getActiveSessions();
});

/// Provider for a specific live session
final liveSessionProvider = FutureProvider.family<LiveSessionModel?, String>((ref, sessionId) async {
  final repository = ref.watch(liveSessionRepositoryProvider);
  return await repository.getSession(sessionId);
});

/// Stream provider for live session updates
final liveSessionStreamProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, sessionId) {
  final repository = ref.watch(liveSessionRepositoryProvider);
  return repository.subscribeToSession(sessionId);
});