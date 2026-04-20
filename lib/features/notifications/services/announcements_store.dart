import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement.dart';

/// In-memory store for admin announcements.
///
/// Fetches announcements from Supabase and keeps them cached so the Home banner,
/// notification bell, and Notifications page can all render the same data.
class AnnouncementsStore extends ChangeNotifier {
  AnnouncementsStore._();

  static final AnnouncementsStore instance = AnnouncementsStore._();

  List<Announcement> _items = const <Announcement>[];
  bool _isLoading = false;
  Object? _lastError;

  Future<void>? _inFlight;

  List<Announcement> get items => _items;
  bool get isLoading => _isLoading;
  Object? get lastError => _lastError;

  Future<void> refresh({int limit = 10}) {
    final existing = _inFlight;
    if (existing != null) return existing;

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    final future = _refreshInternal(limit: limit);
    _inFlight = future;

    return future.whenComplete(() {
      if (_inFlight == future) _inFlight = null;
    });
  }

  Future<void> _refreshInternal({required int limit}) async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('announcements')
          .select()
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (rows as List<dynamic>).whereType<Map<String, dynamic>>();
      _items = list.map(Announcement.fromSupabase).toList(growable: false);
    } catch (e) {
      _lastError = e;
      developer.log('AnnouncementsStore.refresh failed', error: e);
      // Keep the previously cached items on failure.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
