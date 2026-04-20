class ArtistIdentityCache {
  String? _artistId;
  DateTime? _cacheTime;

  static const Duration cacheDuration = Duration(minutes: 5);

  String? get artistId => _artistId;

  bool get isValid {
    final t = _cacheTime;
    if (t == null) return false;
    return DateTime.now().difference(t) < cacheDuration;
  }

  void set(String artistId) {
    _artistId = artistId;
    _cacheTime = DateTime.now();
  }

  void clear() {
    _artistId = null;
    _cacheTime = null;
  }
}
