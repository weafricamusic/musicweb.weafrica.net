import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/artist_identity_cache.dart';

class ArtistIdentityService {
  ArtistIdentityService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  static final ArtistIdentityCache _cache = ArtistIdentityCache();

  final SupabaseClient _client;

  String? currentFirebaseUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final t = uid.trim();
    return t.isEmpty ? null : t;
  }

  /// Canonical API used by newer modules.
  Future<String?> resolveArtistId({bool forceRefresh = false}) => resolveArtistIdForCurrentUser(forceRefresh: forceRefresh);

  Future<String?> resolveArtistIdForCurrentUser({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.isValid) {
      final cached = _cache.artistId;
      if (cached != null && cached.trim().isNotEmpty) return cached;
    }

    final uid = currentFirebaseUid();
    if (uid == null) return null;

    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('artists')
          .select('id,user_id,firebase_uid')
          .or('user_id.eq.$uid,firebase_uid.eq.$uid')
          .limit(1);

      if (rows.isEmpty) return null;
      final id = rows.first['id']?.toString().trim();
      if (id != null && id.isNotEmpty) {
        _cache.set(id);
        return id;
      }
    } catch (e) {
      developer.log(
        'resolveArtistId failed uid=$uid err=$e',
        name: 'WEAFRICA.ArtistIdentity',
        error: e,
      );
    }

    return null;
  }

  void clearCache() {
    _cache.clear();
  }
}
