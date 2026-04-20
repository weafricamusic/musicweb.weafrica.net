import 'package:shared_preferences/shared_preferences.dart';

import '../features/tracks/track.dart';

class LikedTracksStore {
  LikedTracksStore._();

  static final instance = LikedTracksStore._();

  static const _prefsKey = 'liked_tracks';

  final Set<String> _liked = <String>{};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_prefsKey) ?? const <String>[];
    _liked
      ..clear()
      ..addAll(items.where((e) => e.trim().isNotEmpty));
    _loaded = true;
  }

  String keyFor(Track track) {
    final id = track.id?.trim();
    if (id != null && id.isNotEmpty) return 'id:$id';

    final uri = track.audioUri;
    if (uri != null) return 'uri:${uri.toString()}';

    return 't:${track.title}|a:${track.artist}';
  }

  bool isLiked(Track track) {
    final key = keyFor(track);
    return _liked.contains(key);
  }
  Future<bool> setLiked(Track track, bool liked) async {
    await load();
    final key = keyFor(track);
    if (liked) {
      _liked.add(key);
    } else {
      _liked.remove(key);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _liked.toList(growable: false));
    return liked;
  }

  Future<bool> toggle(Track track) async {
    final next = !isLiked(track);
    return setLiked(track, next);
  }
}
