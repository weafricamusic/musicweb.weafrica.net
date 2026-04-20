bool isPlaceholderArtwork(String value) {
  final v = value.trim().toLowerCase();
  // Common placeholder used in some rows.
  return v == 'thumbnails/me.jpg' ||
      v.endsWith('/thumbnails/me.jpg') ||
      v.contains('/storage/v1/object/public/thumbnails/me.jpg') ||
      v.contains('/storage/v1/object/thumbnails/me.jpg');
}

/// Picks the first non-empty artwork-like value from a row.
///
/// This keeps Flutter resilient if the backend uses different field names
/// (`artwork_url`, `thumbnail_url`, `thumbnail`, `image_url`, etc).
String? pickArtworkValue(
  Map<String, dynamic> row, {
  required List<String> keys,
}) {
  for (final key in keys) {
    final raw = row[key];
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) continue;
    if (isPlaceholderArtwork(s)) continue;
    return s;
  }
  return null;
}
