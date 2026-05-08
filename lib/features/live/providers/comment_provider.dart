import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/realtime/comment_stream_service.dart';
import 'auth_provider.dart';

final commentServiceProvider = Provider<CommentStreamService>((ref) {
  return CommentStreamService(ref.read(supabaseClientProvider));
});

final commentsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, liveSessionId) {
  return ref.read(commentServiceProvider).subscribeToComments(liveSessionId);
});

final sendCommentProvider = Provider<Future<void> Function(String, String)>((ref) {
  return (String liveSessionId, String text) async {
    final user = ref.read(currentUserProvider).value;
    final profile = await ref.read(currentProfileProvider.future);
    
    if (user == null || profile == null) return;
    
    await ref.read(commentServiceProvider).sendComment(
      liveSessionId: liveSessionId,
      userId: user.id,
      username: profile['username'] ?? 'Anonymous',
      text: text,
    );
  };
});
