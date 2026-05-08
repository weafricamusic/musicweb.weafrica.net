import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/services/agora_service.dart';

final agoraServiceProvider = Provider<AgoraService>((ref) {
  final service = AgoraService();
  ref.onDispose(() => service.dispose());
  return service;
});

final agoraInitializedProvider = FutureProvider<void>((ref) async {
  final agora = ref.read(agoraServiceProvider);
  await agora.initialize();
});

final isJoinedProvider = Provider<bool>((ref) {
  return ref.watch(agoraServiceProvider).isJoined.value;
});

final remoteUidProvider = Provider<int?>((ref) {
  return ref.watch(agoraServiceProvider).remoteUid.value;
});
