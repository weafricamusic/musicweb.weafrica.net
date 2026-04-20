class Track {
  final String id;
  final String title;
  final String? artworkUri;
  final String? audioUri;
  final Duration? duration;
  final List<String>? artists;
  final String? album;

  const Track({
    required this.id,
    required this.title,
    this.artworkUri,
    this.audioUri,
    this.duration,
    this.artists,
    this.album,
  });

  // Helper method to compare tracks
  static bool same(Track? a, Track? b) {
    if (a == null || b == null) return false;
    return a.id == b.id;
  }
}
