import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final currentUserProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return client.auth.onAuthStateChange.map((event) {
    return event.session?.user;
  });
});

final currentProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;

  if (user == null) {
    throw Exception('User not logged in');
  }

  final response = await client
      .from('profiles')
      .select()
      .eq('id', user.id)
      .single();

  return response;
});
