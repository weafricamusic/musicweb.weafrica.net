enum AlbumStatus {
  draft,
  published,
  archived,
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.status,
    this.artistId,
    this.artistName,
    this.description,
    this.coverUrl,
    this.publishedAt,
    this.updatedAt,
    this.trackCount = 0,
  });

  final String id;
  final String title;

  final String? artistId;
  final String? artistName;

  final String? description;
  final String? coverUrl;

  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  final int trackCount;
  final AlbumStatus status;

  bool get isPublished => status == AlbumStatus.published;
  bool get isDraft => status == AlbumStatus.draft;

  /// Backwards-compat getters for existing UI.
  String? get artist => artistName;

  /// Strict parse from an albums row selected with known columns.
  factory Album.fromSupabase(Map<String, dynamic> map) {
    final id = (map['id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      throw const FormatException('Album missing required field: id');
    }

    final title = (map['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      throw FormatException('Album $id missing required field: title');
    }

    final createdAt = _parseDateTime(map['created_at']);
    if (createdAt == null) {
      throw FormatException('Album $id missing required field: created_at');
    }

    final status = _parseStatus(map);

    return Album(
      id: id,
      title: title,
      artistId: (map['artist_id'] as String?)?.trim(),
      artistName: (map['artist_name'] as String?)?.trim(),
      description: (map['description'] as String?)?.trim(),
      coverUrl: (map['cover_url'] as String?)?.trim(),
      publishedAt: _parseDateTime(map['published_at']),
      createdAt: createdAt,
      updatedAt: _parseDateTime(map['updated_at']),
      trackCount: (map['track_count'] as int?) ?? 0,
      status: status,
    );
  }

  /// Legacy/best-effort parse for older screens or unknown schemas.
  ///
  /// Keep all guessing here so the rest of the app can be strict.
  factory Album.fromSupabaseLegacy(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString().trim();

    final titleRaw = (row['title'] ?? row['name'] ?? '').toString().trim();
    final title = titleRaw.isEmpty ? 'Untitled album' : titleRaw;

    final descriptionRaw = (row['description'] ?? row['about'] ?? '').toString().trim();
    final description = descriptionRaw.isEmpty ? null : descriptionRaw;

    final coverRaw = (row['cover_url'] ?? row['artwork_url'] ?? row['image_url'] ?? row['cover'] ?? '')
        .toString()
        .trim();
    final coverUrl = coverRaw.isEmpty ? null : coverRaw;

    String? artistName;
    final artistRaw = (row['artist'] ?? row['artist_name'] ?? '').toString().trim();
    if (artistRaw.isNotEmpty) {
      artistName = artistRaw;
    } else {
      final artists = row['artists'];
      if (artists is Map) {
        final name = (artists['stage_name'] ?? artists['name'] ?? artists['artist_name'] ?? '').toString().trim();
        if (name.isNotEmpty) artistName = name;
      }
    }

    final createdAt = _parseDateTime(row['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final publishedAt = _parseDateTime(row['published_at'] ?? row['release_at']);

    final status = _parseStatus(row.map((k, v) => MapEntry(k.toString(), v)));

    return Album(
      id: id,
      title: title,
      artistId: (row['artist_id'] ?? '').toString().trim().isEmpty ? null : (row['artist_id'] ?? '').toString().trim(),
      artistName: artistName,
      description: description,
      coverUrl: coverUrl,
      publishedAt: publishedAt,
      createdAt: createdAt,
      updatedAt: _parseDateTime(row['updated_at']),
      trackCount: (row['track_count'] as int?) ?? 0,
      status: status,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static AlbumStatus _parseStatus(Map<String, dynamic> map) {
    final raw = (map['status'] as String?)?.toLowerCase().trim();
    if (raw == 'published') return AlbumStatus.published;
    if (raw == 'draft') return AlbumStatus.draft;
    if (raw == 'archived') return AlbumStatus.archived;

    // Legacy fields
    final isPublished = map['is_published'] == true;
    final hasPublishedAt = map['published_at'] != null;
    if (isPublished || hasPublishedAt) return AlbumStatus.published;

    return AlbumStatus.draft;
  }
}
