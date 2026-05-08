import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/services/realtime/presence_reconciliation_service.dart';
import 'agora_provider.dart';
import 'auth_provider.dart';

final presenceReconciliationServiceProvider = Provider<PresenceReconciliationService>((ref) {
  final supabase = ref.read(supabaseClientProvider);
  final agora = ref.read(agoraServiceProvider);
  return PresenceReconciliationService(supabase, agora);
});
