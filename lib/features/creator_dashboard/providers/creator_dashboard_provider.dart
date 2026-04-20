import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/utils/user_facing_error.dart';
import '../../../core/services/supabase_service.dart';
import '../../../data/repositories/artist_repository.dart';
import '../../../data/repositories/battle_repository.dart';
import '../../../data/repositories/fan_repository.dart';
import '../../../data/repositories/earnings_repository.dart';
import '../../auth/user_role.dart';
import '../../auth/user_role_resolver.dart';

class CreatorDashboardProvider extends ChangeNotifier {
  CreatorDashboardProvider({
    SupabaseService? supabase,
    ArtistRepository? artistRepo,
    BattleRepository? battleRepo,
    FanRepository? fanRepo,
    EarningsRepository? earningsRepo,
  })  : _supabase = supabase ?? SupabaseService(),
        _artistRepo = artistRepo ?? ArtistRepository(),
        _battleRepo = battleRepo ?? BattleRepository(),
        _fanRepo = fanRepo ?? FanRepository(),
        _earningsRepo = earningsRepo ?? EarningsRepository();

  final SupabaseService _supabase;
  final ArtistRepository _artistRepo;
  final BattleRepository _battleRepo;
  final FanRepository _fanRepo;
  final EarningsRepository _earningsRepo;

  // Data
  Map<String, dynamic>? _artist;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _activeBattles = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _recentMessages = <Map<String, dynamic>>[];
  Map<String, dynamic> _earnings = <String, dynamic>{};
  int _pendingBattles = 0;
  int _unreadMessages = 0;
  bool _isLoading = false;
  String? _error;
  UserRole? _userRole;

  // Realtime
  RealtimeChannel? _realtime;
  Timer? _debounce;

  // Getters
  Map<String, dynamic>? get artist => _artist;
  Map<String, dynamic>? get stats => _stats;
  List<Map<String, dynamic>> get activeBattles => _activeBattles;
  List<Map<String, dynamic>> get recentMessages => _recentMessages;
  Map<String, dynamic> get earnings => _earnings;
  int get pendingBattles => _pendingBattles;
  int get unreadMessages => _unreadMessages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  UserRole? get userRole => _userRole;

  Future<void> loadDashboardData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        _error = 'User not logged in';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final uid = fbUser.uid;

      // Determine user role (Firebase+Supabase backed).
      _userRole = await UserRoleResolver.resolveForFirebaseUid(uid);

      // Get artist profile (best-effort; DJ accounts may not have one).
      _artist = await _artistRepo.getArtistByUserId(uid);

      final artistId = _artist?['id']?.toString();

      if (artistId != null && artistId.trim().isNotEmpty) {
        final resolvedArtistId = artistId.trim();

        final results = await Future.wait([
          _artistRepo.getArtistStats(resolvedArtistId),
          _battleRepo.getActiveBattles(resolvedArtistId, firebaseUid: uid, limit: 20),
          _fanRepo.getMessages(resolvedArtistId, firebaseUid: uid, limit: 3),
          _fanRepo.getUnreadCount(resolvedArtistId, firebaseUid: uid),
          _earningsRepo.getEarningsSummary(resolvedArtistId, firebaseUid: uid),
        ]);

        _stats = (results[0] as Map<String, dynamic>);
        _activeBattles = List<Map<String, dynamic>>.from(results[1] as List);
        _recentMessages = List<Map<String, dynamic>>.from(results[2] as List);
        _unreadMessages = results[3] as int;
        _earnings = (results[4] as Map<String, dynamic>);

        _pendingBattles = _activeBattles.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'pending').length;
      } else {
        _stats = const <String, dynamic>{};
        _activeBattles = const <Map<String, dynamic>>[];
        _recentMessages = const <Map<String, dynamic>>[];
        _earnings = const <String, dynamic>{'available': 0, 'pending': 0, 'total': 0, 'by_source': <String, num>{}};
        _pendingBattles = 0;
        _unreadMessages = 0;
      }

      _isLoading = false;
      notifyListeners();

      // Set up realtime after initial load.
      subscribeToUpdates();
    } catch (e, st) {
      UserFacingError.log('CreatorDashboardProvider.loadDashboardData', e, st);
      _error = UserFacingError.message(
        e,
        fallback: 'Could not load dashboard. Please try again.',
      );
      _isLoading = false;
      notifyListeners();
    }
  }

  void subscribeToUpdates() {
    final artistId = _artist?['id']?.toString().trim();
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (artistId == null || artistId.isEmpty) return;

    _realtime?.unsubscribe();
    _realtime = null;

    // Debounced refresh ping.
    void ping() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _refreshAll(artistId: artistId, firebaseUid: uid);
      });
    }

    final channel = Supabase.instance.client.channel('public:creator_dashboard:$artistId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'battles',
          callback: (_) => ping(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => ping(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallets',
          callback: (_) => ping(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'battle_earnings',
          callback: (_) => ping(),
        )
        .subscribe();

    _realtime = channel;
  }

  Future<void> _refreshAll({required String artistId, required String? firebaseUid}) async {
    try {
      final results = await Future.wait([
        _artistRepo.getArtistStats(artistId),
        _battleRepo.getActiveBattles(artistId, firebaseUid: firebaseUid, limit: 20),
        _fanRepo.getMessages(artistId, firebaseUid: firebaseUid, limit: 3),
        _fanRepo.getUnreadCount(artistId, firebaseUid: firebaseUid),
        _earningsRepo.getEarningsSummary(artistId, firebaseUid: firebaseUid),
      ]);

      _stats = (results[0] as Map<String, dynamic>);
      _activeBattles = List<Map<String, dynamic>>.from(results[1] as List);
      _recentMessages = List<Map<String, dynamic>>.from(results[2] as List);
      _unreadMessages = results[3] as int;
      _earnings = (results[4] as Map<String, dynamic>);

      _pendingBattles = _activeBattles.where((b) => (b['status'] ?? '').toString().toLowerCase() == 'pending').length;
      notifyListeners();
    } catch (e) {
      // Best-effort refresh; do not flip UI into error state.
      debugPrint('⚠️ CreatorDashboardProvider refresh failed: $e');
    }
  }

  Future<bool> acceptBattle(String battleId, String trackId) async {
    final success = await _battleRepo.acceptBattle(battleId, trackId);
    if (success) {
      final artistId = _artist?['id']?.toString().trim();
      if (artistId != null && artistId.isNotEmpty) {
        await _refreshAll(artistId: artistId, firebaseUid: FirebaseAuth.instance.currentUser?.uid);
      }
    }
    return success;
  }

  Future<bool> declineBattle(String battleId) async {
    final success = await _battleRepo.declineBattle(battleId);
    if (success) {
      final artistId = _artist?['id']?.toString().trim();
      if (artistId != null && artistId.isNotEmpty) {
        await _refreshAll(artistId: artistId, firebaseUid: FirebaseAuth.instance.currentUser?.uid);
      }
    }
    return success;
  }

  Future<bool> markMessageRead(String messageId) async {
    final success = await _fanRepo.markAsRead(messageId);
    if (success) {
      final artistId = _artist?['id']?.toString().trim();
      if (artistId != null && artistId.isNotEmpty) {
        await _refreshAll(artistId: artistId, firebaseUid: FirebaseAuth.instance.currentUser?.uid);
      }
    }
    return success;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debounce = null;

    _realtime?.unsubscribe();
    _realtime = null;

    // Best-effort cleanup for any extra channels created via SupabaseService.
    unawaited(_supabase.unsubscribeAll());

    super.dispose();
  }
}
