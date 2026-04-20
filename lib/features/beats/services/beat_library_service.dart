import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/beat_generation.dart';

class BeatLibraryService {
  static const String _key = 'weafrica.beats.savedBeats.v1';
  static const int _maxItems = 50;

  Future<List<SavedBeat>> getSavedBeats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final beats = SavedBeat.listFromPrefsString(raw);
    return beats..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveBeat(SavedBeat beat) async {
    final prefs = await SharedPreferences.getInstance();
    final beats = await getSavedBeats();

    final existingIndex = beats.indexWhere((b) => b.id == beat.id);
    if (existingIndex >= 0) {
      beats[existingIndex] = beat;
    } else {
      beats.insert(0, beat);
    }

    final trimmed = beats.take(_maxItems).toList(growable: false);
    await prefs.setString(_key, SavedBeat.listToPrefsString(trimmed));

    developer.log('Saved beat ${beat.id}', name: 'WEAFRICA.Beats.Library');
  }

  Future<void> updateBeat(SavedBeat beat) async {
    await saveBeat(beat);
  }

  Future<void> deleteBeat(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final beats = await getSavedBeats();
    final filtered = beats.where((b) => b.id != id).toList(growable: false);
    await prefs.setString(_key, SavedBeat.listToPrefsString(filtered));

    developer.log('Deleted beat $id', name: 'WEAFRICA.Beats.Library');
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
