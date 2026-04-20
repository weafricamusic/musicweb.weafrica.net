import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:weafrica_music/features/notifications/services/notification_center_api.dart';

class NotificationCenterStore extends ChangeNotifier {
  NotificationCenterStore._();

  static final NotificationCenterStore instance = NotificationCenterStore._();

  int _unreadCount = 0;
  bool _loading = false;
  Object? _lastError;
  Future<void>? _inFlight;

  String? _activeUid;
  RealtimeChannel? _channel;
  Timer? _fallbackPoller;

  int get unreadCount => _unreadCount;
  bool get isLoading => _loading;
  Object? get lastError => _lastError;

  Future<void> refreshUnreadCount({bool force = false}) {
    final existing = _inFlight;
    if (!force && existing != null) return existing;

    _loading = true;
    notifyListeners();

    final future = _refreshInternal();
    _inFlight = future;

    return future.whenComplete(() {
      if (_inFlight == future) _inFlight = null;
    });
  }

  Future<void> _refreshInternal() async {
    try {
      final count = await NotificationCenterApi.instance.getUnreadCount();
      _unreadCount = count;
      _lastError = null;
    } catch (e) {
      _lastError = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void startRealtimeSync({required String uid}) {
    if (uid.trim().isEmpty) return;
    if (_activeUid == uid && _channel != null) return;

    stopRealtimeSync();
    _activeUid = uid;

    final client = Supabase.instance.client;
    _channel = client
        .channel('public:notifications:unread:$uid:${DateTime.now().millisecondsSinceEpoch}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        callback: (payload) {
          final targetUid =
              payload.newRecord['user_uid']?.toString() ?? payload.oldRecord['user_uid']?.toString();
          if (targetUid == uid) {
            unawaited(refreshUnreadCount());
          }
        },
      )
      ..subscribe();

    _fallbackPoller = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(refreshUnreadCount());
    });

    unawaited(refreshUnreadCount(force: true));
  }

  void stopRealtimeSync() {
    _activeUid = null;

    _fallbackPoller?.cancel();
    _fallbackPoller = null;

    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(channel.unsubscribe());
      Supabase.instance.client.removeChannel(channel);
    }
  }

  void setUnreadCount(int value) {
    _unreadCount = value;
    notifyListeners();
  }
}
