class WeAfricaPowerVoice {
  const WeAfricaPowerVoice._();

  /// Core motivational messages for studio entry.
  ///
  /// Kept intentionally short and punchy for the overlay UI.
  static const List<String> _coreMessages = <String>[
    'The continent is waiting for your sound.',
    "Your voice is not a noise. It's a signal.",
    "Africa doesn't need copycats. It needs you.",
    "Build something they can't ignore.",
    'Your ancestors dreamed of this moment.',
    'You are not just an artist. You are a movement.',
    'Your sound is building your legacy.',
    'Africa is ready for your voice.',
    'Consistency turns artists into icons.',
    'Every upload is a step to greatness.',
  ];

  static int get coreMessagesCount => _coreMessages.length;

  static String coreMessageAt(int index) {
    if (_coreMessages.isEmpty) return '';
    final i = index % _coreMessages.length;
    return _coreMessages[i];
  }

  // ---- Brand / entry ----
  static const String brand = 'WEAFRICA';

  static const String entryLine1 = 'Africa is listening.';
  static const String entryLine2 = 'What empire will you build today?';

  // ---- Daily command (deterministic per day) ----
  static const List<String> _dailyCommands = <String>[
    'Move. Release. Dominate.',
    'Africa rewards the relentless.',
    'Streams follow strategy. Legacy follows action.',
    'No excuses. Build your empire.',
    'Own your sound. Own your future.',
    'Drop. Promote. Repeat.',
  ];

  static int _dailyIndex(DateTime now) {
    // Stable per local calendar day.
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final seed = (y * 10000) + (m * 100) + d;
    return seed % _dailyCommands.length;
  }

  static String dailyCommand({DateTime? now}) {
    final t = now ?? DateTime.now();
    return _dailyCommands[_dailyIndex(t)];
  }

  /// Random-ish motivational line with optional personalization.
  ///
  /// If [messageIndex] is provided, it is used (useful for no-repeat rotation).
  /// Otherwise we default to a time-based pick from the core message pool.
  static String studioMotivation({
    String? who,
    DateTime? now,
    int? messageIndex,
  }) {
    final name = (who ?? '').trim();
    final index = messageIndex ??
        ((now ?? DateTime.now()).microsecondsSinceEpoch % _coreMessages.length);

    final line = _coreMessages.isEmpty ? dailyCommand(now: now) : coreMessageAt(index);
    if (name.isEmpty || name.toLowerCase() == 'artist') return line;
    return '$name — $line';
  }

  /// Contextual messages based on artist activity.
  ///
  /// When no special context applies, falls back to [studioMotivation] and can
  /// use [messageIndex] for non-repeating rotation.
  static String contextualMessage({
    required String who,
    bool hasSongs = false,
    bool hasEarnings = false,
    bool hasActiveBattle = false,
    int daysSinceLastUpload = 999,
    int? messageIndex,
    DateTime? now,
  }) {
    // Recently active artists
    if (daysSinceLastUpload < 3 && hasSongs) {
      return '$who, your momentum is building. Keep going.';
    }

    // Inactive for a while
    if (daysSinceLastUpload > 7 && hasSongs) {
      return "$who, Africa hasn't heard from you in a while. They're waiting.";
    }

    // New artists with no content
    if (!hasSongs) {
      return '$who, your journey starts now. Drop your first track.';
    }

    // Artists with earnings
    if (hasEarnings) {
      return '$who, your talent is paying off. Check your growth.';
    }

    // Artists in battles
    if (hasActiveBattle) {
      return '$who, the stage is yours. Go win.';
    }

    // Default
    return studioMotivation(who: who, now: now, messageIndex: messageIndex);
  }

  static String timeBasedMessage(String who, {DateTime? now}) {
    final hour = (now ?? DateTime.now()).hour;

    if (hour < 12) {
      return 'Morning, $who. The continent is waking up to your sound.';
    } else if (hour < 17) {
      return 'Afternoon, $who. Keep creating. Africa is listening.';
    } else {
      return 'Evening, $who. Your music travels while you rest.';
    }
  }

  // ---- Studio CTAs ----
  static const String ctaEnterArena = 'Enter the Arena';
  static const String ctaTrain = 'Train Like a Champion';

  static const String ctaOpenCreatorStudio = 'Enter Creator Studio';

  static const String ctaDropTrack = 'Drop Now';
  static const String ctaReleaseVideo = 'Release Visuals';
  static const String ctaBuildCatalog = 'Build My Catalog';

  static const String ctaTrackRise = 'Track My Rise';
  static const String ctaActivateRevenue = 'Activate Revenue';
  static const String ctaGrowEmpire = 'Grow My Empire';
  static const String ctaClaimStage = 'Claim My Stage';
  static const String ctaStayReady = 'Stay Ready';
  static const String ctaUpgradeEmpire = 'Upgrade My Empire';
  static const String ctaCompleteProfile = 'Complete My Profile';
  static const String ctaEngageFans = 'Engage Fans';
  static const String ctaShowYourPower = 'Show Your Power';
  static const String ctaProveIt = 'Prove It';
  static const String ctaClaimLegacy = 'Claim My Legacy';

  // ---- Studio tab headlines (short + punchy) ----
  static const String musicHeadline = 'Silence is defeat.';
  static const String musicTagline = 'Release your first track. Make Africa hear your sound.';

  static const String battleHeadline = 'You don’t wait. You conquer.';
  static const String battleTagline = 'The stage is yours the moment you step up. Africa is watching.';

  static const String analyticsHeadline = 'Numbers obey action.';
  static const String analyticsTagline = 'Streams, plays, impact — they follow your move.';

  static const String earningsHeadline = 'Income is power realized.';
  static const String earningsTagline = 'Every stream is currency. Every fan is capital.';

  static const String profileHeadline = 'Your name is a continent-wide brand.';
  static const String profileTagline = 'Build it. Protect it. Expand it.';

  static const String notificationsHeadline = 'Signals. Updates. Momentum.';
  static const String notificationsTagline = 'Stay ready. Your next move starts here.';

  static const String fansHeadline = 'No audience? Then earn one.';
  static const String fansTagline = 'They exist to believe in you. Command their attention.';

  static const String videosHeadline = 'If they can’t see you, you don’t exist.';
  static const String videosTagline = 'Be visible. Be unstoppable.';

  static const String achievementsHeadline = 'Legends aren’t announced.';
  static const String achievementsTagline = 'They are proven, screen by screen, stream by stream.';

  // ---- Empty states ----
  static const String emptySongs = 'No songs yet. Drop your first track.';
  static const String emptyVideos = 'No videos yet. Be seen. Be remembered.';
  static const String emptyAlbums = 'No albums yet. Build your catalog.';
  static const String emptyBattles = 'The arena is quiet—for now. Prepare your first battle.';
  static const String emptyNotifications = 'No notifications yet. Stay sharp.';
  static const String emptyBattleInvites = 'No invites yet. Stay ready.';

  static const String noDataSignal = 'No signal yet. Reload and keep moving.';

  static const String emptyBio = 'No bio yet. Own your story.';
  static const String emptyAchievements = 'No milestones yet. Prove it.';
  static const String emptyLink = 'Not claimed yet.';

  // ---- Truthful build-locked messaging (no fake promises) ----
  static const String lockedInBuildTitle = 'Locked. Not negotiable.';
  static const String lockedInBuildBody =
      'This section is locked in this build. Keep moving — your empire still grows today.';

  static const String payoutsLockedTitle = 'Payouts are locked in this build.';
  static const String payoutsLockedBody =
      'Revenue is real. Withdrawals will open when payouts are enabled for your account.';
}
