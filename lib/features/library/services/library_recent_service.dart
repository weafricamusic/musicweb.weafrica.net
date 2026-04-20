import '../../../app/utils/result.dart';
import '../../../services/recent_contexts_service.dart';
import '../../tracks/tracks_repository.dart';
import '../models/library_track.dart';

class LibraryRecentService {
  LibraryRecentService({
    RecentContextsService? recentContexts,
    TracksRepository? tracksRepository,
  })  : _recentContexts = recentContexts ?? RecentContextsService.instance,
        _tracksRepository = tracksRepository ?? TracksRepository();

  final RecentContextsService _recentContexts;
  final TracksRepository _tracksRepository;

  Future<Result<List<LibraryTrack>>> getRecentlyPlayed({int limit = 20}) async {
    try {
      final contexts = await _recentContexts.fetchQuickAccess(limit: limit);
      final trackContexts = contexts.where((c) => c.contextType == 'track').toList(growable: false);

      final ids = <String>[];
      for (final c in trackContexts) {
        final id = c.contextId.trim();
        if (id.isEmpty) continue;
        ids.add(id);
      }

      final resolved = await Future.wait(ids.map(_tracksRepository.getById));
      final out = <LibraryTrack>[];
      for (int i = 0; i < resolved.length; i++) {
        final t = resolved[i];
        if (t == null) continue;
        out.add(
          LibraryTrack(
            track: t,
            downloaded: false,
            lastPlayedAt: trackContexts.length > i ? trackContexts[i].lastPlayedAt : null,
          ),
        );
      }

      return Result.success(out);
    } catch (e) {
      return Result.failure(Exception('Failed to load recently played: $e'));
    }
  }
}
