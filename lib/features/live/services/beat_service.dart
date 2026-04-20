import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/beat_model.dart';

class BeatService {
  final _supabase = Supabase.instance.client;

  static const String _defaultAiBeatsBucket = 'ai_beats';

  // Curated / featured beat(s) that should always be selectable.
  // NOTE: We store the *object path* (not a signed URL) because signed URLs expire.
  static final List<BeatModel> _curatedBeats = <BeatModel>[
    BeatModel(
      id: 'curated-ai-beats-be7c3364',
      name: 'Artist Live Battle Instrument',
      genre: 'Instrumental',
      duration: 120,
      bpm: 120,
      storageBucket: _defaultAiBeatsBucket,
      storagePath:
          'be7c3364bd4e276e433e431f6eab9a0f436701c0e71effd453e7ab919b67d574.wav',
    ),
    BeatModel(
      id: 'curated-ai-beats-faddawam-sgidongo-house',
      name: 'Amapiano Instruments (Sgidongo House)',
      genre: 'Amapiano',
      duration: 120,
      bpm: 112,
      storageBucket: _defaultAiBeatsBucket,
      // Object path as stored in Supabase Storage (decoded from the signed URL).
      storagePath: 'faddawam - faddawam  sgidongo house mp3 - Sonauto.wav',
    ),
  ];

  static final List<BeatModel> _fallbackBeats = <BeatModel>[
    BeatModel(
      id: 'fallback-afrobeats-120',
      name: 'Afrobeats Pulse',
      genre: 'Afrobeats',
      duration: 30,
      bpm: 120,
    ),
    BeatModel(
      id: 'fallback-amapiano-112',
      name: 'Amapiano Groove',
      genre: 'Amapiano',
      duration: 30,
      bpm: 112,
    ),
    BeatModel(
      id: 'fallback-dancehall-98',
      name: 'Dancehall Bounce',
      genre: 'Dancehall',
      duration: 30,
      bpm: 98,
    ),
    BeatModel(
      id: 'fallback-afrohouse-126',
      name: 'Afrohouse Drive',
      genre: 'Afrohouse',
      duration: 30,
      bpm: 126,
    ),
  ];

  Future<List<BeatModel>> getAvailableBeats() async {
    try {
      final response = await _supabase
          .from('ai_beat_audio_jobs')
          .select('*')
          .eq('status', 'succeeded')
          .order('created_at', ascending: false)
          .limit(20);

      final beats = (response as List)
          .map((json) => BeatModel.fromJson(json))
          .toList(growable: false);

      if (beats.isNotEmpty) {
        return _mergeCurated(beats);
      }
    } catch (_) {
      // Fall back to static defaults when backend rows are unavailable.
    }

    return _mergeCurated(List<BeatModel>.from(_fallbackBeats, growable: false));
  }

  Future<BeatModel?> getBeatById(String beatId) async {
    final trimmedBeatId = beatId.trim();
    if (trimmedBeatId.isEmpty) return null;

    try {
      final response = await _supabase
          .from('ai_beat_audio_jobs')
          .select('*')
          .eq('id', trimmedBeatId)
          .eq('status', 'succeeded')
          .maybeSingle();

      if (response is Map<String, dynamic>) {
        return BeatModel.fromJson(response);
      }
    } catch (_) {
      // Ignore backend errors and attempt fallback lookup.
    }

    for (final beat in _fallbackBeats) {
      if (beat.id == trimmedBeatId) return beat;
    }

    for (final beat in _curatedBeats) {
      if (beat.id == trimmedBeatId) return beat;
    }

    return null;
  }

  List<BeatModel> _mergeCurated(List<BeatModel> beats) {
    if (_curatedBeats.isEmpty) return beats;

    final existingIds = beats.map((b) => b.id).toSet();
    final curatedToAdd = _curatedBeats.where((b) => !existingIds.contains(b.id)).toList(growable: false);
    if (curatedToAdd.isEmpty) return beats;

    return <BeatModel>[...curatedToAdd, ...beats];
  }
}
