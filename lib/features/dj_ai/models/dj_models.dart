import '../../tracks/track.dart';

class DjSong {
  const DjSong({
    required this.id,
    required this.bpm,
    required this.energy,
    this.genre,
  });

  final String id;
  final int bpm;
  final double energy;
  final String? genre;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bpm': bpm,
        'energy': energy,
        if (genre != null && genre!.trim().isNotEmpty) 'genre': genre,
      };

  static DjSong fromTrack(
    Track t, {
    required int fallbackBpm,
    double fallbackEnergy = 0.7,
  }) {
    final id = (t.id ?? t.audioUri?.toString() ?? '${t.title}|${t.artist}').trim();
    return DjSong(
      id: id.isEmpty ? '${t.title}|${t.artist}' : id,
      bpm: fallbackBpm,
      energy: fallbackEnergy,
      genre: t.genre,
    );
  }
}

class DjNextRequest {
  const DjNextRequest({
    this.battleType = '1v1',
    this.battleId,
    this.style,
    this.currentSongId,
    required this.currentSongBpm,
    this.currentSongEnergy,
    this.currentSongGenre,
    required this.likesPerMin,
    required this.coinsPerMin,
    this.viewersChange,
    this.battleTimeRemaining,
    this.audienceDeltaPerMin,
    required this.songPool,
  });

  final String battleType; // "1v1" | "dj_set"
  final String? battleId;
  final String? style;
  final String? currentSongId;
  final int currentSongBpm;
  final double? currentSongEnergy;
  final String? currentSongGenre;
  final int likesPerMin;
  final int coinsPerMin;
  final int? viewersChange;
  final int? battleTimeRemaining;
  final int? audienceDeltaPerMin;
  final List<DjSong> songPool;

  Map<String, dynamic> toJson() => {
        'battle_type': battleType,
      if (battleId != null && battleId!.trim().isNotEmpty) 'battle_id': battleId,
      if (style != null && style!.trim().isNotEmpty) 'style': style,
        'current_song_id': currentSongId,
        'current_song_bpm': currentSongBpm,
        'current_song_energy': currentSongEnergy,
        'current_song_genre': currentSongGenre,
        'likes_per_min': likesPerMin,
        'coins_per_min': coinsPerMin,
      // Battle Pressure AI metrics
      // Prefer viewers_change if provided; otherwise fall back to legacy audience_delta_per_min.
      'viewers_change': viewersChange ?? audienceDeltaPerMin,
      'battle_time_remaining': battleTimeRemaining,
        'audience_delta_per_min': audienceDeltaPerMin,
        'song_pool': songPool.map((s) => s.toJson()).toList(growable: false),
      };
}

class DjNextResponse {
  const DjNextResponse({
    required this.decision,
    required this.nextSongId,
    this.energyAction,
    this.genreAction,
    this.vibeAction,
    this.reasons = const <String>[],
  });

  final String decision;
  final String nextSongId;
  final String? energyAction;
  final String? genreAction;
  final String? vibeAction;
  final List<String> reasons;

  factory DjNextResponse.fromJson(Map<String, dynamic> m) {
    List<String> parseReasons(Object? raw) {
      if (raw is List) return raw.map((e) => e.toString()).toList(growable: false);
      return const <String>[];
    }

    return DjNextResponse(
      decision: (m['decision'] ?? '').toString(),
      nextSongId: (m['next_song_id'] ?? m['nextSongId'] ?? '').toString(),
      energyAction: m['energy_action']?.toString(),
      genreAction: m['genre_action']?.toString(),
      vibeAction: m['vibe_action']?.toString(),
      reasons: parseReasons(m['reasons']),
    );
  }
}
