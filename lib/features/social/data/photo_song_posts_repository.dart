import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tracks/track.dart';

class PhotoSongPostsRepository {
  PhotoSongPostsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> createPost({
    required String creatorUid,
    required XFile image,
    required Track song,
    required String caption,
    required int songStartSeconds,
    required int songDurationSeconds,
  }) async {
    final imageUrl = await _uploadPostImage(
      creatorUid: creatorUid,
      image: image,
    );

    final normalizedImageUrl = _normalizeUrl(imageUrl);
    if (normalizedImageUrl == null) {
      throw StateError('Post image upload did not return a valid URL.');
    }

    final songId = (song.id ?? '').trim();
    if (songId.isEmpty) {
      throw StateError('Selected song has no ID. Choose another song.');
    }

    final trimmedCreatorUid = creatorUid.trim();
    if (trimmedCreatorUid.isEmpty) {
      throw StateError('Creator UID is required.');
    }

    final safeCaption = caption.trim();

    await _client.from('photo_song_posts').insert({
      'creator_uid': trimmedCreatorUid,
      'image_url': normalizedImageUrl,
      'song_id': songId,
      'song_start': songStartSeconds,
      'song_duration': songDurationSeconds,
      'caption': safeCaption.isEmpty ? null : safeCaption,
    });
  }

  Future<String> _uploadPostImage({
    required String creatorUid,
    required XFile image,
  }) async {
    final ext = _safeExt(image.path);
    final path =
        'posts/$creatorUid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bytes = await File(image.path).readAsBytes();

    await _client.storage.from('post_images').uploadBinary(path, bytes);
    return _client.storage.from('post_images').getPublicUrl(path);
  }

  String _safeExt(String inputPath) {
    final lower = inputPath.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  String? _normalizeUrl(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return null;
  }
}
