import '../../features/artist_dashboard/screens/artist_profile_screen.dart';
import '../../features/live/screens/live_swipe_watch_screen.dart';
import '../../features/creator/creator_upload_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../services/content_access_gate.dart';
import '../../services/creator_finance_api.dart';
import '../../services/playback_ad_gate.dart';
import '../../services/playback_skips_gate.dart';
import '../../services/live_priority_access_gate.dart';
import '../../services/notification_service.dart';
import '../../services/ad_service.dart';
import '../../app/services/country_service.dart';
import '../auth/auth_actions.dart';
import '../auth/creator_profile_provisioner.dart';
import '../auth/user_profile_provisioner.dart';
import '../auth/user_role.dart';
import '../auth/user_role_resolver.dart';
import '../auth/user_role_intent_store.dart';
import '../auth/user_role_store.dart';
import '../../home/home_tab.dart';
import '../library/library_tab_real.dart';
import '../live/live_screen.dart';
import '../live/models/live_args.dart';
import '../live/models/live_battle.dart';
import '../live/services/battle_matching_api.dart';
import '../live/services/battle_invite_service.dart';
import '../player/mini_player.dart';
import '../player/playback_controller.dart';
import '../player/player_routes.dart';
import '../settings/about_weafrica_music_page.dart';
import '../settings/creator_support_about_screen.dart';
import '../settings/role_based_settings_screen.dart';
import '../pulse/reels/feed_screen.dart';
import '../search/search_screen.dart';
import '../notifications/notifications_screen.dart';
import '../notifications/services/announcements_store.dart';
import '../notifications/services/notification_center_store.dart';
import '../subscriptions/role_based_subscription_screen.dart';
import '../subscriptions/models/subscription_capabilities.dart';
import '../subscriptions/models/subscription_plan.dart';
import '../subscriptions/subscriptions_controller.dart';
import '../subscriptions/widgets/contextual_upgrade_modal.dart';
import '../subscriptions/widgets/upgrade_prompt_factory.dart';
import '../artist/dashboard/screens/artist_stats_screen.dart';
import '../artist_dashboard/screens/artist_live_battles_screen.dart';
import '../artist_dashboard/screens/artist_earnings_screen.dart';
import '../dj_dashboard/screens/dj_live_battles_screen.dart';
import '../dj_dashboard/screens/dj_earnings_screen.dart';
import '../dj_dashboard/screens/dj_stats_screen.dart';
import '../ads/models/ad_model.dart';
import '../ads/services/ad_scheduler.dart';
import '../ads/widgets/video_ad_player.dart';
import '../../audio/audio.dart';
import '../studio/screens/studio_entry_screen.dart';
import '../live/screens/go_live_setup_screen.dart';
import '../upload/screens/upload_track_screen.dart';
import '../upload/screens/upload_video_screen.dart';
import '../social/screens/photo_song_post_mockup_screen.dart';
import '../wallet/wallet_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const double _navHeight = 80;
  int _index = 0;
  int _studioOpenTick = 0;

  String? _autoSelectedCreatorModeForUid;

  String? _roleUid;
  String? _didProvisionCountryForUid;
  bool _isProvisioningCountry = false;
  Future<UserRole>? _roleFuture;
  String? _roleFutureKey;
  int _roleRefreshToken = 0;
  String? _didProvisionForUid;
  bool _isProvisioningCreatorProfile = false;

  UserRole _roleIntent = UserRole.consumer;
  VoidCallback? _roleIntentListener;

  String? _warnedRoleMismatchForUid;

  StreamSubscription<void>? _adSub;
  bool _showingInterstitial = false;

  StreamSubscription<SkipGateEvent>? _skipGateSub;
  bool _showingSkipLimitModal = false;

  StreamSubscription<ContentAccessGateEvent>? _contentGateSub;
  bool _showingContentGateModal = false;

  StreamSubscription<LivePriorityAccessGateEvent>? _livePriorityGateSub;
  bool _showingLivePriorityGateModal = false;

  final BattleInviteService _battleInviteService = BattleInviteService();
  static const BattleMatchingApi _battleMatchingApi = BattleMatchingApi();
  StreamSubscription<List<Map<String, dynamic>>>? _battleInviteSub;
  String? _realtimeUid;
  String? _battleInviteUid;
  final Set<String> _seenBattleInviteIds = <String>{};
  String? _lastInviteSnackId;
  bool _showingBattleInviteDialog = false;

  int? _coinBalance;
  bool _coinBalanceLoading = false;
  DateTime? _coinBalanceFetchedAt;

  DateTime? _subscriptionFetchedAt;

  void _refreshSubscription({bool force = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final last = _subscriptionFetchedAt;
    if (!force && last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }

    _subscriptionFetchedAt = now;
    unawaited(SubscriptionsController.instance.refreshMe());
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _refreshCoinBalance({bool force = false}) async {
    if (_coinBalanceLoading) return;
    if (!mounted) return;

    final now = DateTime.now();
    final last = _coinBalanceFetchedAt;
    if (!force && last != null && now.difference(last) < const Duration(seconds: 20)) {
      return;
    }

    setState(() => _coinBalanceLoading = true);
    try {
      final summary = await const CreatorFinanceApi().fetchMyWalletSummary();
      if (!mounted) return;
      setState(() {
        _coinBalance = summary.coinBalance.round();
        _coinBalanceFetchedAt = DateTime.now();
      });
    } catch (_) {
      // Best-effort only; keep last known balance.
    } finally {
      if (mounted) setState(() => _coinBalanceLoading = false);
    }
  }

  void _openProfilePage({required UserRole roleForUi}) {
    _open(context, ArtistProfileScreen());
  }

  Future<void> _openGoLiveSetup({
    required UserRole roleForUi,
    bool battleModeEnabled = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to continue.')),
      );
      return;
    }

    final displayName = user.displayName?.trim();
    final hostName =
        (displayName == null || displayName.isEmpty) ? 'Creator' : displayName;

    _open(
      context,
      GoLiveSetupScreen(
        role: roleForUi,
        hostId: user.uid,
        hostName: hostName,
        initialBattleModeEnabled: battleModeEnabled,
      ),
    );
  }

  Future<void> _openCreatorCreateSheet({required UserRole roleForUi}) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          tween: Tween<double>(begin: 0.97, end: 1.0),
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    tileColor: AppColors.brandOrange.withValues(alpha: 0.16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: AppColors.brandOrange.withValues(alpha: 0.45),
                      ),
                    ),
                    leading: const Icon(
                      Icons.radio_button_checked,
                      color: AppColors.brandOrange,
                    ),
                    title: const Text('GO LIVE NOW'),
                    subtitle: const Text('Start streaming instantly'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_openGoLiveSetup(roleForUi: roleForUi));
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: const Text('Photo + Song Post'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _open(
                        context,
                        PhotoSongPostMockupScreen(role: roleForUi),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.music_note_outlined),
                    title: const Text('Upload Song'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _open(
                        context,
                        UploadTrackScreen(creatorIntent: roleForUi),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.ondemand_video_outlined),
                    title: const Text('Upload Video'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _open(
                        context,
                        UploadVideoScreen(creatorIntent: roleForUi),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.sports_mma_outlined),
                    title: const Text('Start Battle'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(
                        _openGoLiveSetup(
                          roleForUi: roleForUi,
                          battleModeEnabled: true,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openWalletPage({required UserRole roleForUi}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => WalletScreen(roleOverride: roleForUi),
          ),
        )
        .then((_) {
      if (!mounted) return;
      unawaited(_refreshCoinBalance(force: true));
    });
  }

  void _openNotificationsPage() {
    // Best-effort: refresh announcements so the page is always up-to-date.
    unawaited(AnnouncementsStore.instance.refresh(limit: 10));
    // Clear OS badge (best-effort). Unread count is server-backed.
    unawaited(NotificationService.instance.clearBadge());
    _open(context, const NotificationsScreen());
  }

  // TODO: Wire this up from the profile icon/menu.
  // ignore: unused_element
  void _openProfileMenuSheet({required UserRole roleForUi}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final VoidCallback? walletCallback = (roleForUi == UserRole.dj)
            ? () {
                Navigator.of(sheetContext).pop();
                _open(context, const DjEarningsScreen());
              }
            : (roleForUi == UserRole.artist)
                ? () {
                    Navigator.of(sheetContext).pop();
                    _open(context, const ArtistEarningsScreen());
                  }
                : null;

        return _ProfileMenuSheet(
          roleForUi: roleForUi,
          onViewProfile: () {
            Navigator.of(sheetContext).pop();
            _open(context, ArtistProfileScreen());
          },
          onOpenSettings: () {
            Navigator.of(sheetContext).pop();
            _open(context, RoleBasedSettingsScreen(roleOverride: roleForUi));
          },
          onOpenSubscription: () {
            Navigator.of(sheetContext).pop();
            _open(context, RoleBasedSubscriptionScreen(roleOverride: roleForUi));
          },
          onOpenWalletEarnings: walletCallback,
          onOpenLikedSongs: () {
            Navigator.of(sheetContext).pop();
            _open(context, const LibraryTab(initialFilter: 'LIKED'));
          },
          onOpenDownloads: () {
            Navigator.of(sheetContext).pop();
            _open(context, const LibraryTab(initialFilter: 'DOWNLOADED'));
          },
          onOpenListeningHistory: () {
            Navigator.of(sheetContext).pop();
            _open(context, const LibraryTab(initialFilter: 'RECENTLY PLAYED'));
          },
          onOpenAnalytics: (roleForUi == UserRole.artist || roleForUi == UserRole.dj)
              ? () {
                  Navigator.of(sheetContext).pop();
                  if (roleForUi == UserRole.dj) {
                    _open(context, const DjStatsScreen());
                  } else {
                    _open(context, const ArtistStatsScreen());
                  }
                }
              : null,
          onHelpSupport: () {
            Navigator.of(sheetContext).pop();
            _open(context, const CreatorSupportAboutScreen());
          },
          onAbout: () {
            Navigator.of(sheetContext).pop();
            _open(context, const AboutWeAfricaMusicPage());
          },
          onSignOut: () async {
            Navigator.of(sheetContext).pop();
            try {
              await AuthActions.signOut();
            } catch (_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not sign out. Please try again.')),
              );
            }
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Make sure entitlements are fresh early (affects ads + premium features).
    SubscriptionsController.instance.initialize();
    _refreshSubscription(force: true);

    // Fetch announcements as the shell starts so the Home banner and bell badge
    // can render immediately.
    unawaited(AnnouncementsStore.instance.refresh(limit: 10));

    // Fetch unread notification count (server-backed).
    unawaited(NotificationCenterStore.instance.refreshUnreadCount());

    // Best-effort: show wallet coins in the top bar.
    unawaited(_refreshCoinBalance());

    // React to role intent changes (Listener vs Artist/DJ) immediately.
    _roleIntent = UserRoleIntentStore.notifier.value;
    _roleIntentListener = () {
      if (!mounted) return;
      setState(() => _roleIntent = UserRoleIntentStore.notifier.value);
    };
    UserRoleIntentStore.notifier.addListener(_roleIntentListener!);
    // Sync from persisted storage.
    unawaited(UserRoleIntentStore.getRole());

    // Global ads gating: show an interstitial placeholder when the gate says so.
    // PlaybackAdGate already checks subscription entitlements.
    _adSub = PlaybackAdGate.instance.interstitialDue.listen((event) {
      unawaited(
        _showInterstitialIfPossible(
          forceResumeAfter: event.forceResumeAfter,
          requiredMedia: event.requiredMedia,
        ),
      );
    });

    // Ticket 2.14: consumer soft limit (skips/hour). The gate emit events
    // from non-UI layers (audio handler, notification controls), so we render
    // the existing contextual upgrade modal here.
    _skipGateSub = PlaybackSkipsGate.instance.events.listen((event) {
      if (!mounted) return;
      if (_showingSkipLimitModal) return;

      final prompt = UpgradePromptFactory.forConsumerCapability(
        ConsumerCapability.skips,
        nearLimitLabel: event.nearLimitLabel,
      );

      _showingSkipLimitModal = true;
      unawaited(() async {
        try {
          await showContextualUpgradeModal(
            context,
            prompt: prompt,
            source: 'consumer_skip_gate:${event.type.name}',
          );
        } finally {
          _showingSkipLimitModal = false;
        }
      }());
    });

    _contentGateSub = ContentAccessGate.instance.events.listen((event) {
      if (!mounted) return;
      if (_showingContentGateModal) return;

      final prompt = UpgradePromptFactory.forConsumerCapability(event.capability);

      _showingContentGateModal = true;
      unawaited(() async {
        try {
          await showContextualUpgradeModal(
            context,
            prompt: prompt,
            source: 'content_access_gate:${event.reason.name}',
          );
        } finally {
          _showingContentGateModal = false;
        }
      }());
    });

    _livePriorityGateSub = LivePriorityAccessGate.instance.events.listen((event) {
      if (!mounted) return;
      if (_showingLivePriorityGateModal) return;

      final prompt = UpgradePromptFactory.forConsumerCapability(event.capability);

      _showingLivePriorityGateModal = true;
      unawaited(() async {
        try {
          final upgraded = await showContextualUpgradeModal(
            context,
            prompt: prompt,
            source: 'live_priority_gate:${event.accessTier}',
          );

          if (upgraded) {
            LivePriorityAccessGate.instance.notifyUpgraded(
              channelId: event.channelId,
              accessTier: event.accessTier,
            );
          }
        } finally {
          _showingLivePriorityGateModal = false;
        }
      }());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSubscription();
      unawaited(NotificationCenterStore.instance.refreshUnreadCount());
    }
  }

  void _syncRealtimeListenersForUid(String? uid) {
    if (_realtimeUid == uid) return;
    _seenBattleInviteIds.clear();
    _lastInviteSnackId = null;
    _realtimeUid = uid;

    if (uid == null || uid.isEmpty) {
      NotificationCenterStore.instance.stopRealtimeSync();
      _stopBattleInviteListener();
      return;
    }

    NotificationCenterStore.instance.startRealtimeSync(uid: uid);
    _startBattleInviteListener(uid);
  }

  void _startBattleInviteListener(String uid) {
    if (_battleInviteUid == uid && _battleInviteSub != null) return;

    _stopBattleInviteListener();
    _battleInviteUid = uid;

    _battleInviteSub = _battleInviteService.getPendingInvites(uid).listen(
      (rows) {
        if (!mounted || rows.isEmpty) return;

        final invites = rows.map(BattleInvite.fromMap).toList(growable: false);
        final newInvites = invites.where((invite) {
          final id = invite.id.trim();
          return id.isNotEmpty && !_seenBattleInviteIds.contains(id);
        }).toList(growable: false);

        if (newInvites.isEmpty) return;

        for (final invite in newInvites) {
          _seenBattleInviteIds.add(invite.id.trim());
        }

        if (_seenBattleInviteIds.length > 300) {
          final overflow = _seenBattleInviteIds.length - 300;
          _seenBattleInviteIds.removeAll(
            _seenBattleInviteIds.take(overflow).toList(growable: false),
          );
        }

        unawaited(_showBattleInvitePrompt(newInvites.first));
        unawaited(NotificationCenterStore.instance.refreshUnreadCount());
      },
      onError: (_, _) {
        // Best-effort stream; we still have push + polling fallback.
      },
    );
  }

  void _stopBattleInviteListener() {
    _battleInviteUid = null;
    _battleInviteSub?.cancel();
    _battleInviteSub = null;
  }

  void _showBattleInviteSnackBar(BattleInvite invite) {
    if (!mounted) return;

    final inviteId = invite.id.trim();
    if (inviteId.isEmpty || _lastInviteSnackId == inviteId) return;
    _lastInviteSnackId = inviteId;

    final senderHandle = invite.fromUserName.trim();
    final sender = senderHandle.isEmpty ? 'Another creator' : senderHandle;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$sender invited you to a live battle.'),
          duration: const Duration(seconds: 7),
          action: SnackBarAction(
            label: 'View',
            onPressed: _openBattleInvitesInbox,
          ),
        ),
      );
  }

  Future<void> _showBattleInvitePrompt(BattleInvite invite) async {
    if (!mounted || _showingBattleInviteDialog) return;

    _showingBattleInviteDialog = true;
    try {
      final from = invite.fromUserName.trim().isNotEmpty
          ? invite.fromUserName.trim()
          : 'Another creator';
      final exp = invite.expiresAt.toLocal().toString().split('.').first;
      var busy = false;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) {
          return StatefulBuilder(
            builder: (dialogCtx, setState) {
              Future<void> respond(String action) async {
                if (busy) return;
                setState(() => busy = true);
                try {
                  if (action == 'accept') {
                    final battle = await _battleMatchingApi.respondToInvite(
                      inviteId: invite.id,
                      action: 'accept',
                    );
                    if (!dialogCtx.mounted || !mounted) return;
                    Navigator.of(dialogCtx).pop();
                    await _openBattleFromInvite(invite: invite, battle: battle);
                    return;
                  }

                  if (action == 'decline') {
                    await _battleMatchingApi.respondToInvite(
                      inviteId: invite.id,
                      action: 'decline',
                    );
                    if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                    return;
                  }

                  Navigator.of(dialogCtx).pop();
                  _openBattleInvitesInbox();
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not process battle invite. Please try again.')),
                  );
                } finally {
                  if (dialogCtx.mounted) setState(() => busy = false);
                }
              }

              return AlertDialog(
                title: const Text('Battle invite'),
                content: Text('$from invited you to a live battle. Expires $exp.'),
                actions: [
                  TextButton(
                    onPressed: busy ? null : () => respond('view'),
                    child: const Text('View'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : () => respond('decline'),
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : () => respond('accept'),
                    child: const Text('Accept'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      _showingBattleInviteDialog = false;
    }
  }

  Future<void> _openBattleFromInvite({
    required BattleInvite invite,
    required LiveBattle battle,
  }) async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    final role = await UserRoleResolver.resolveCurrentUser();
    final displayName = user?.displayName?.trim();
    final hostName = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : role.label;

    final participants = <String>{
      invite.fromUid.trim(),
      uid,
      battle.hostAId?.trim() ?? '',
      battle.hostBId?.trim() ?? '',
    }.where((value) => value.isNotEmpty).toList(growable: false);

    _open(
      context,
      LiveScreen(
        args: LiveArgs(
          liveId: battle.channelId,
          channelId: battle.channelId,
          role: role == UserRole.consumer ? _roleIntent : role,
          hostId: uid,
          hostName: hostName,
          isBattle: true,
          battleId: battle.battleId,
          battleArtists: participants,
        ),
      ),
    );
  }

  void _openBattleInvitesInbox() {
    final page = _roleIntent == UserRole.dj
        ? const DjLiveBattlesScreen()
        : ArtistLiveBattlesScreen();
    _open(context, page);
  }

  void _maybeProvisionCreatorProfile(String uid) {
    if (_roleIntent == UserRole.consumer) return;
    if (_isProvisioningCreatorProfile) return;

    // Only attempt once per UID (per session). If the user changes the intent,
    // they can sign out/in to retry.
    if (_didProvisionForUid == uid) return;

    _isProvisioningCreatorProfile = true;
    CreatorProfileProvisioner.ensureForCurrentUser(intent: _roleIntent)
        .then((_) {
          if (!mounted) return;
          setState(() {
            _didProvisionForUid = uid;
            _isProvisioningCreatorProfile = false;
            _roleRefreshToken++;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _didProvisionForUid = uid;
            _isProvisioningCreatorProfile = false;
          });
        });
  }

  void _maybeProvisionCountryCode({required String uid, required UserRole role}) {
    if (_isProvisioningCountry) return;
    if (_didProvisionCountryForUid == uid) return;

    _isProvisioningCountry = true;
    () async {
      final cc = await CountryService.ensureCountryCodeCached();
      await UserProfileProvisioner.provisionForCurrentUser(
        intent: role,
        countryCode: cc,
      );
    }()
        .then((_) {
          if (!mounted) return;
          setState(() {
            _didProvisionCountryForUid = uid;
            _isProvisioningCountry = false;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _didProvisionCountryForUid = uid;
            _isProvisioningCountry = false;
          });
        });
  }

  Future<void> _showInterstitialIfPossible({
    bool forceResumeAfter = false,
    InterstitialRequiredMedia? requiredMedia,
  }) async {
    if (_showingInterstitial) return;
    if (!mounted) return;

    _showingInterstitial = true;

    final bool handlerWasPlaying =
      (isWeAfricaAudioInitialized && maybeWeafricaAudioHandler?.player.playing == true);
    final bool shouldResumeAfter = handlerWasPlaying || forceResumeAfter;

    try {
      PlaybackAdGate.instance.setInterstitialShowing(true);

      // Prevent the ad audio from mixing with the current song.
      if (handlerWasPlaying || forceResumeAfter) {
        try {
          await maybeWeafricaAudioHandler?.pause();
        } catch (_) {}
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _InterstitialPlaceholderDialog(requiredMedia: requiredMedia),
      );
    } finally {
      PlaybackAdGate.instance.setInterstitialShowing(false);

      // Resume playback automatically for users (especially Free) so the ad
      // doesn't feel like it "stops" music forever.
      if (shouldResumeAfter) {
        try {
          await maybeWeafricaAudioHandler?.play();
        } catch (_) {}
      }

      _showingInterstitial = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _syncRealtimeListenersForUid(null);

    _adSub?.cancel();
    _adSub = null;

    _skipGateSub?.cancel();
    _skipGateSub = null;

    _contentGateSub?.cancel();
    _contentGateSub = null;

    _livePriorityGateSub?.cancel();
    _livePriorityGateSub = null;

    final listener = _roleIntentListener;
    if (listener != null) {
      UserRoleIntentStore.notifier.removeListener(listener);
    }
    _roleIntentListener = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        final uid = snap.data?.uid;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncRealtimeListenersForUid(uid);
        });

        if (uid != null) {
          // Kick off provisioning after build to avoid setState during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _maybeProvisionCreatorProfile(uid);
          });
        }

        final roleKey = '${uid ?? 'no-user'}|$_roleRefreshToken';

        if (_roleUid != uid ||
            _roleFuture == null ||
            _roleFutureKey != roleKey) {
          _roleUid = uid;
          _roleFutureKey = roleKey;
          _roleFuture = uid == null
              ? Future.value(UserRole.consumer)
              : UserRoleResolver.resolveForFirebaseUid(uid);
          // After login, default to Home before optionally auto-opening Studio.
          if (uid == null) _index = 0;
        }

        return FutureBuilder<UserRole>(
          key: ValueKey(uid ?? 'no-user'),
          future: _roleFuture,
          builder: (context, roleSnap) {
            final resolvedRole = roleSnap.data ?? UserRole.consumer;

            final resolvedIsCreator = resolvedRole == UserRole.artist || resolvedRole == UserRole.dj;
            final intentIsCreator = _roleIntent == UserRole.artist || _roleIntent == UserRole.dj;
            final intentIsConsumer = _roleIntent == UserRole.consumer;

            // UI mode rules:
            // - If backend still says consumer but user chose creator mode, show creator UI.
            // - If backend says creator and user chose Listener mode, honor Listener UI.
            // - Otherwise use the resolved role.
            final UserRole roleForUi = (uid != null && !resolvedIsCreator && intentIsCreator)
                ? _roleIntent
                : (uid != null && resolvedIsCreator && intentIsConsumer)
                    ? UserRole.consumer
                    : resolvedRole;

            // Web (and fresh installs) often default the role-intent to Listener even when
            // the account is a creator. If the backend resolves a creator role and the user
            // has never explicitly chosen an intent, default them into Studio mode.
            if (uid != null &&
                resolvedIsCreator &&
                intentIsConsumer &&
                UserRoleIntentStore.hasLoaded &&
                !UserRoleIntentStore.hasExplicitValue &&
                _autoSelectedCreatorModeForUid != uid) {
              _autoSelectedCreatorModeForUid = uid;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(() async {
                  try {
                    await UserRoleIntentStore.setRole(resolvedRole);
                  } catch (_) {
                    // Best-effort only; if persistence fails we still keep the session stable.
                  }
                }());
              });
            }

            final UserRole? studioRole = (roleForUi == UserRole.artist || roleForUi == UserRole.dj) ? roleForUi : null;
            final hasStudio = studioRole != null;

            // Keep role-specific navigation simple and explicit.
            // Consumers: Home, Trending, Music, Live, Library
            // Artist/DJ:  Home, +Create, Studio, Library, Profile
            final showMusicTab = !hasStudio;
            final createIndex = hasStudio ? 1 : -1;

            // For creators, Studio appears at index 2 (Home, +Create, Studio, Library, Profile).
            final studioIndex = hasStudio ? 2 : -1;
            final profileIndex = hasStudio ? 4 : -1;

            if (uid != null &&
                intentIsCreator &&
                resolvedRole == UserRole.consumer &&
                roleSnap.connectionState == ConnectionState.done &&
                _warnedRoleMismatchForUid != uid) {
              _warnedRoleMismatchForUid = uid;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Your account is still updating. Please try again in a moment.',
                    ),
                    duration: Duration(seconds: 6),
                  ),
                );
              });
            }

            if (roleSnap.connectionState == ConnectionState.done) {
              // Persist role for other services (analytics, FCM, etc.).
              UserRoleStore.setRole(roleForUi);

              if (uid != null) {
                _maybeProvisionCountryCode(uid: uid, role: roleForUi);
              }
            }

            final safeBottom = MediaQuery.paddingOf(context).bottom;
            final shellWidth = MediaQuery.sizeOf(context).width;
            final isPhone = shellWidth < 600;

            // Only show the mini player on Home.
            final showMiniPlayerOnThisTab = _index == 0;

            final isTrendingTab = !hasStudio && _index == 1;
            final isStudioTabActive = studioIndex >= 0 && _index == studioIndex;
            // On phones, Studio has it own navigation (app bar + bottom nav).
            // Hide the shell chrome when Studio is active to avoid stacked nav bars.
            final hideShellChromeForStudio = isPhone && isStudioTabActive;

            // Show the top actions (Profile/Search/Notifications) on all tabs
            // except Trending (which is an immersive full-screen feed).
            final showShellAppBar = !isTrendingTab && !hideShellChromeForStudio;

            final pages = hasStudio
                ? <Widget>[
                    const HomeTab(),
                    const CreatorUploadScreen(),
                    Theme(
                      data: buildDarkTheme(),
                      child: StudioEntryScreen(
                        role: studioRole,
                        isActive: _index == 2,
                        openTick: _studioOpenTick,
                      ),
                    ),
                    const LibraryTab(),
                    ArtistProfileScreen(),
                  ]
                : <Widget>[
                    const HomeTab(),
                    const ReelFeedScreen(),
                    const LiveSwipeWatchScreen(),
                    const LibraryTab(),
                    ArtistProfileScreen(),
                  ];
            final destinations = hasStudio
                ? <NavigationDestination>[
                    const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                    const NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Create'),
                    const NavigationDestination(icon: Icon(Icons.mic_outlined), selectedIcon: Icon(Icons.mic), label: 'Studio'),
                    const NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
                    const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
                  ]
                : <NavigationDestination>[
                    const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                    const NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt), label: 'Trending'),
                    const NavigationDestination(icon: Icon(Icons.live_tv_outlined), selectedIcon: Icon(Icons.live_tv), label: 'Live'),
                    const NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
                    const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
                  ];
            if (_index >= pages.length) {
              // If the role changed (creator -> consumer), keep the app stable.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _index = 0);
              });
            }

            return PopScope(
              canPop: !hideShellChromeForStudio,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                if (hideShellChromeForStudio) {
                  if (mounted) setState(() => _index = 0);
                }
              },
              child: Scaffold(
              extendBody: true,
              extendBodyBehindAppBar: isTrendingTab,
              appBar: showShellAppBar
                  ? AppBar(
                      toolbarHeight: 64,
                      backgroundColor: Colors.transparent,
                      centerTitle: false,
                      titleSpacing: 12,
                      title: InkWell(
                        onTap: () {
                          if (!mounted) return;
                          setState(() => _index = 0);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          child: Builder(
                            builder: (context) {
                              final w = MediaQuery.sizeOf(context).width;
                              final label = w < 380 ? 'WEAFRICA' : 'WEAFRICA MUSIC';

                              return ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (bounds) {
                                  return const LinearGradient(
                                    colors: [
                                      AppColors.brandPurple,
                                      AppColors.brandPink,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds);
                                },
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                      ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      actions: [
                        IconButton(
                          tooltip: 'Search',
                          onPressed: () => _open(context, const SearchScreen()),
                          icon: const Icon(Icons.search),
                        ),
                        AnimatedBuilder(
                          animation: NotificationCenterStore.instance,
                          builder: (context, _) {
                            final count = NotificationCenterStore.instance.unreadCount;

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                IconButton(
                                  tooltip: 'Notifications',
                                  onPressed: _openNotificationsPage,
                                  icon: const Icon(Icons.notifications_none),
                                ),
                                if (count > 0)
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: _BellBadge(count: count),
                                  ),
                              ],
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Tooltip(
                            message: 'Coins',
                            child: InkWell(
                              onTap: () => _openWalletPage(roleForUi: roleForUi),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.surface2,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.monetization_on_outlined,
                                      size: 18,
                                      color: AppColors.stageGold,
                                    ),
                                    if (_coinBalance != null) ...[
                                      const SizedBox(width: 6),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 52),
                                        child: Text(
                                          '${_coinBalance!}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Tooltip(
                            message: 'Profile',
                            child: InkWell(
                              onTap: () => _openProfilePage(roleForUi: roleForUi),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 36,
                                width: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.surface2,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Icon(Icons.person_outline, size: 18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : null,
              body: SafeArea(
                bottom: false,
                child: IndexedStack(
                  index: _index.clamp(0, pages.length - 1),
                  children: pages,
                ),
              ),
              bottomNavigationBar: hideShellChromeForStudio
                  ? null
                  : AnimatedBuilder(
                      animation: PlaybackController.instance,
                      builder: (context, _) {
                        final hasTrack = PlaybackController.instance.current != null;
                        final showMiniPlayer = hasTrack && showMiniPlayerOnThisTab;

                        return SafeArea(
                          top: false,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 220),
                            opacity: isTrendingTab ? 0.20 : 1.0,
                            child: Container(
                              color: AppColors.surface,
                              padding: EdgeInsets.only(bottom: safeBottom),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (showMiniPlayer) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        12,
                                        10,
                                      ),
                                      child: MiniPlayer(
                                        onTap: () => openPlayer(context),
                                      ),
                                    ),
                                  ],
                                  NavigationBarTheme(
                                    data: NavigationBarThemeData(
                                      backgroundColor: AppColors.surface,
                                      indicatorColor: AppColors.brandOrange
                                          .withValues(alpha: 0.22),
                                      labelTextStyle:
                                          WidgetStateProperty.resolveWith(
                                        (states) {
                                          final isSelected = states.contains(
                                            WidgetState.selected,
                                          );
                                          return Theme.of(
                                            context,
                                          ).textTheme.labelSmall?.copyWith(
                                            color: isSelected
                                                ? AppColors.brandOrange
                                                : AppColors.textMuted,
                                            fontWeight: FontWeight.w600,
                                          );
                                        },
                                      ),
                                      iconTheme:
                                          WidgetStateProperty.resolveWith((
                                        states,
                                      ) {
                                        final isSelected = states.contains(
                                          WidgetState.selected,
                                        );
                                        return IconThemeData(
                                          color: isSelected
                                              ? AppColors.brandOrange
                                              : AppColors.textMuted,
                                        );
                                      }),
                                    ),
                                    child: NavigationBar(
                                      height: _navHeight,
                                      selectedIndex: _index.clamp(
                                        0,
                                        destinations.length - 1,
                                      ),
                                      onDestinationSelected: (i) async {
                                        if (hasStudio && i == createIndex) {
                                          await _openCreatorCreateSheet(
                                            roleForUi: roleForUi,
                                          );
                                          return;
                                        }

                                        final isStudioDestination =
                                            studioIndex >= 0 && i == studioIndex;

                                        if (hasStudio && i == profileIndex) {
                                          if (!mounted) return;
                                          setState(() => _index = i);
                                          return;
                                        }

                                        // On phones, open Studio as a full-screen flow
                                        // so it own navigation isn't stacked with the shell tabs.
                                        if (isPhone &&
                                            isStudioDestination &&
                                            studioRole != null) {
                                          _studioOpenTick++;
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => Theme(
                                                data: buildDarkTheme(),
                                                child: StudioEntryScreen(
                                                  role: studioRole,
                                                  isActive: true,
                                                  openTick: _studioOpenTick,
                                                ),
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        if (!mounted) return;
                                        setState(() {
                                          _index = i;
                                          if (isStudioDestination) {
                                            _studioOpenTick++;
                                          }
                                        });
                                      },
                                      destinations: destinations,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            );
          },
        );
      },
    );
  }
}

class _InterstitialPlaceholderDialog extends StatefulWidget {
  const _InterstitialPlaceholderDialog({this.requiredMedia});

  final InterstitialRequiredMedia? requiredMedia;

  @override
  State<_InterstitialPlaceholderDialog> createState() =>
      _InterstitialPlaceholderDialogState();
}

class _InterstitialPlaceholderDialogState
    extends State<_InterstitialPlaceholderDialog> {
  // Free-tier ads should be a short interstitial (Spotify-like).
  static const int _minSeconds = 3;
  static const int _maxSeconds = 30;
  static const int _fallbackSeconds = 5;
  static const int _noAdSeconds = 2;

  late int _remaining = _fallbackSeconds;
  int _totalSeconds = _fallbackSeconds;
  Timer? _timer;
  AudioPlayer? _audioPlayer;
  StreamSubscription<PlayerState>? _adStateSub;
  AdModel? _ad;

  String? _trackedImpressionForAdId;
  bool _trackedCompletion = false;

  bool _closing = false;

  @override
  void initState() {
    super.initState();

    // Start the countdown immediately so the user is never stuck waiting on a
    // slow ad fetch or audio load.
    _startCountdown(_fallbackSeconds);

    unawaited(_loadAndPlayAd());
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    _timer = null;

    final safe = seconds <= 0 ? _fallbackSeconds : seconds;
    final s = safe.clamp(1, _maxSeconds);
    _totalSeconds = s;
    _remaining = s;

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        _remaining = (_remaining - 1).clamp(0, _totalSeconds);
      });

      if (_remaining <= 0) {
        t.cancel();
        _timer = null;
        _finish();
      }
    });
  }

  void _finish() {
    if (_closing) return;
    _closing = true;

    _timer?.cancel();
    _timer = null;
    _adStateSub?.cancel();
    _adStateSub = null;

    // Stop ad audio before closing.
    try {
      _audioPlayer?.stop();
    } catch (_) {}

    final ad = _ad;
    if (ad != null && !_trackedCompletion) {
      _trackedCompletion = true;
      unawaited(AdService().trackCompletion(ad.id));
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _skip() {
    if (_closing) return;
    _closing = true;

    _timer?.cancel();
    _timer = null;
    _adStateSub?.cancel();
    _adStateSub = null;

    // Stop ad audio before closing.
    try {
      _audioPlayer?.stop();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _handleAdClick() async {
    final ad = _ad;
    final url = ad?.clickUrl;
    if (ad == null || url == null || url.trim().isEmpty) return;

    unawaited(AdService().trackClick(ad.id));

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Ignore failures; ad continues.
    }
  }

  Future<void> _loadAndPlayAd() async {
    try {
      // Don't let ad fetching delay the countdown.
      AdModel? ad;

      // Prefer scheduler-based rotation (e.g. 70% video preference).
      try {
        final required = widget.requiredMedia == InterstitialRequiredMedia.video
            ? AdRequiredMedia.video
            : (widget.requiredMedia == InterstitialRequiredMedia.audio
                ? AdRequiredMedia.audio
                : null);

        ad = await AdScheduler()
            .getRandomAd(placement: 'interstitial', requiredMedia: required)
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
      } catch (_) {
        // ignore
      }

      // Backwards-compatible fallback to the original endpoint.
      // NOTE: The fallback endpoint can't currently filter by media type, so
      // we only use it when no required media is specified.
      if (widget.requiredMedia == null) {
        ad ??= await AdService()
            .getNextAd(placement: 'interstitial')
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
      }

      if (!mounted) return;

      if (ad == null) {
        // No ad available: keep the interruption minimal.
        _startCountdown(_noAdSeconds);
        return;
      }

      setState(() => _ad = ad);

      if (kDebugMode) {
        debugPrint('📺 Interstitial ad loaded: id=${ad.id}');
        debugPrint('   video_url: ${ad.videoUrl}');
        debugPrint('   audio_url: ${ad.audioUrl}');
      }

      final seconds = (ad.durationSeconds <= 0 ? _fallbackSeconds : ad.durationSeconds)
          .clamp(_minSeconds, _maxSeconds);
      _startCountdown(seconds);

      if (_trackedImpressionForAdId != ad.id) {
        _trackedImpressionForAdId = ad.id;
        unawaited(AdService().trackImpression(ad.id));
      }

      final videoUrl = (ad.videoUrl ?? '').trim();
      if (videoUrl.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('🎬 Interstitial using VIDEO path');
        }
        // Video ads are handled by AdPlayer; keep countdown running.
        return;
      }

      final url = (ad.audioUrl ?? '').trim();
      if (url.isEmpty) return;

      if (kDebugMode) {
        debugPrint('🔊 Interstitial using AUDIO path');
      }

      final player = AudioPlayer();
      _audioPlayer = player;

      _adStateSub?.cancel();
      _adStateSub = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _finish();
        }
      });

      // Avoid hanging on slow streams: best-effort play.
      await player
          .setAudioSource(AudioSource.uri(Uri.parse(url)))
          .timeout(const Duration(seconds: 2));
      await player.play().timeout(const Duration(seconds: 1));
    } catch (e) {
      // Ignore ad failures; countdown continues.
      try {
        await _audioPlayer?.dispose();
      } catch (_) {}
      _audioPlayer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _adStateSub?.cancel();
    _adStateSub = null;
    _audioPlayer?.dispose();
    _audioPlayer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final seconds = (ad?.durationSeconds ?? _fallbackSeconds);
    final clampedSeconds = (seconds <= 0 ? _fallbackSeconds : seconds)
        .clamp(_minSeconds, _maxSeconds);

    final videoUrl = (ad?.videoUrl ?? '').trim();
    final audioUrl = (ad?.audioUrl ?? '').trim();

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (ad?.clickUrl ?? '').trim().isEmpty ? null : _handleAdClick,
          child: VideoAdPlayer(
            ad: <String, dynamic>{
              'id': ad?.id,
              'title': ad?.title ?? 'Sponsored',
              'video_url': videoUrl.isNotEmpty ? videoUrl : null,
              'audio_url': audioUrl.isNotEmpty ? audioUrl : null,
              'advertiser': ad?.advertiser,
              'click_url': ad?.clickUrl,
              'is_skippable': ad?.isSkippable ?? false,
            },
            onComplete: _finish,
            onSkip: _skip,
            durationSeconds: clampedSeconds,
          ),
        ),
      ),
    );
  }
}

class _BellBadge extends StatelessWidget {
  const _BellBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.brandOrange,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.background, width: 2),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.background,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _TopBarNotificationsSheet extends StatefulWidget {
  const _TopBarNotificationsSheet();

  @override
  State<_TopBarNotificationsSheet> createState() => _TopBarNotificationsSheetState();
}

class _TopBarNotificationsSheetState extends State<_TopBarNotificationsSheet> {
  late final Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(40);
    return (rows as List<dynamic>).whereType<Map<String, dynamic>>().toList();
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  String _timeLabel(BuildContext context, DateTime? createdAt) {
    if (createdAt == null) return '';
    final dt = createdAt.toLocal();
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';

    return MaterialLocalizations.of(context).formatShortDate(dt);
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: safeBottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.76,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                height: 5,
                width: 54,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_none, color: AppColors.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'NOTIFICATIONS',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load notifications. Please try again.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                              ),
                        ),
                      );
                    }

                    final items = snapshot.data ?? const <Map<String, dynamic>>[];
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No notifications yet.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                              ),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final n = items[index];
                        final title = (n['title'] ?? n['type'] ?? 'Notification').toString();
                        final body = (n['body'] ?? n['message'] ?? '').toString().trim();
                        final createdAt = _parseDate(n['created_at'] ?? n['createdAt']);
                        final time = _timeLabel(context, createdAt);

                        return ListTile(
                          tileColor: AppColors.surface2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          leading: const Icon(Icons.notifications_none, color: AppColors.textMuted),
                          title: Text(
                            title,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          subtitle: body.isEmpty
                              ? null
                              : Text(
                                  body,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textMuted,
                                      ),
                                ),
                          trailing: time.isEmpty
                              ? null
                              : Text(
                                  time,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuSheet extends StatelessWidget {
  const _ProfileMenuSheet({
    required this.roleForUi,
    required this.onViewProfile,
    required this.onOpenSettings,
    required this.onOpenSubscription,
    required this.onOpenLikedSongs,
    required this.onOpenDownloads,
    required this.onOpenListeningHistory,
    required this.onHelpSupport,
    required this.onAbout,
    required this.onSignOut,
    this.onOpenAnalytics,
    this.onOpenWalletEarnings,
  });

  final UserRole roleForUi;
  final VoidCallback onViewProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenSubscription;
  final VoidCallback? onOpenWalletEarnings;
  final VoidCallback onOpenLikedSongs;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenListeningHistory;
  final VoidCallback? onOpenAnalytics;
  final VoidCallback onHelpSupport;
  final VoidCallback onAbout;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    final user = FirebaseAuth.instance.currentUser;
    final displayName = (user?.displayName ?? '').trim();
    final email = (user?.email ?? '').trim();
    final photoUrl = (user?.photoURL ?? '').trim();

    final primaryLabel = displayName.isNotEmpty
        ? displayName
        : (email.isNotEmpty ? email : 'Account');

    final isCreator = roleForUi == UserRole.artist || roleForUi == UserRole.dj;
    final roleLabel = switch (roleForUi) {
      UserRole.artist => 'Artist',
      UserRole.dj => 'DJ',
      UserRole.consumer => 'Listener',
    };

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: safeBottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            children: [
              Center(
                child: Container(
                  height: 5,
                  width: 54,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: photoUrl.isEmpty
                          ? const Icon(Icons.person, size: 20)
                          : Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.person, size: 20);
                              },
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            primaryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            roleLabel,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (email.isNotEmpty && email != primaryLabel) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: AnimatedBuilder(
                  animation: SubscriptionsController.instance,
                  builder: (context, _) {
                    final subs = SubscriptionsController.instance;
                    final planId = subs.currentPlanId.trim().isEmpty ? 'free' : subs.currentPlanId.trim();
                    final planName = displayNameForPlanId(planId).toUpperCase();
                    final isPremium = subs.isPremiumActive;

                    final title = isPremium ? '$planName PLAN' : 'FREE PLAN';
                    final subtitle = subs.loadingMe
                        ? 'Checking subscription…'
                        : (subs.me == null)
                            ? 'No active subscription'
                            : 'Status: ${subs.me!.status}';

                    return Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: isPremium ? AppColors.brandOrange : AppColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _MenuTile(icon: Icons.person_outline, title: 'View Profile', onTap: onViewProfile),
              _MenuTile(icon: Icons.settings_outlined, title: 'Settings', onTap: onOpenSettings),
              _MenuTile(icon: Icons.credit_card_outlined, title: 'Subscription', onTap: onOpenSubscription),
              if (onOpenWalletEarnings != null)
                _MenuTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Wallet & Earnings',
                  onTap: onOpenWalletEarnings!,
                ),
              _MenuTile(icon: Icons.favorite_outline, title: 'Liked Songs', onTap: onOpenLikedSongs),
              _MenuTile(icon: Icons.download_for_offline_outlined, title: 'Downloads', onTap: onOpenDownloads),
              _MenuTile(icon: Icons.history, title: 'Listening History', onTap: onOpenListeningHistory),
              if (isCreator && onOpenAnalytics != null)
                _MenuTile(
                  icon: Icons.insights_outlined,
                  title: 'Analytics',
                  onTap: onOpenAnalytics!,
                ),
              const SizedBox(height: 8),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 8),
              _MenuTile(icon: Icons.help_outline, title: 'Help & Support', onTap: onHelpSupport),
              _MenuTile(icon: Icons.info_outline, title: 'About WeAfrica', onTap: onAbout),
              const SizedBox(height: 8),
              Container(height: 1, color: AppColors.border),
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.logout,
                title: 'Sign Out',
                onTap: onSignOut,
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final dangerColor = Theme.of(context).colorScheme.error;
    final color = danger ? dangerColor : AppColors.text;

    return ListTile(
      tileColor: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      leading: Icon(icon, color: danger ? dangerColor : AppColors.textMuted),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
