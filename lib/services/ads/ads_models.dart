class AdsCreative {
  const AdsCreative({
    required this.id,
    required this.title,
    required this.audioUrl,
    required this.videoUrl,
    required this.imageUrl,
    required this.advertiser,
    required this.clickUrl,
    required this.durationSeconds,
    required this.isSkippable,
  });

  final String id;
  final String title;
  final String? audioUrl;
  final String? videoUrl;
  final String? imageUrl;
  final String advertiser;
  final String? clickUrl;
  final int durationSeconds;
  final bool isSkippable;

  bool get hasPlayableMedia {
    final a = (audioUrl ?? '').trim();
    final v = (videoUrl ?? '').trim();
    return a.isNotEmpty || v.isNotEmpty;
  }

  static AdsCreative? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));

    final id = (m['id'] ?? '').toString().trim();
    if (id.isEmpty) return null;

    String? normUrl(Object? v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    int normInt(Object? v) {
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '').toString()) ?? 0;
    }

    return AdsCreative(
      id: id,
      title: (m['title'] ?? 'Sponsored').toString().trim().isEmpty
          ? 'Sponsored'
          : (m['title'] ?? 'Sponsored').toString().trim(),
      audioUrl: normUrl(m['audio_url'] ?? m['audioUrl']),
      videoUrl: normUrl(m['video_url'] ?? m['videoUrl']),
      imageUrl: normUrl(m['image_url'] ?? m['imageUrl']),
      advertiser: (m['advertiser'] ?? 'WeAfrica Music').toString().trim().isEmpty
          ? 'WeAfrica Music'
          : (m['advertiser'] ?? 'WeAfrica Music').toString().trim(),
      clickUrl: normUrl(m['click_url'] ?? m['clickUrl']),
      durationSeconds: normInt(m['duration_seconds'] ?? m['durationSeconds']),
      isSkippable: (m['is_skippable'] ?? m['isSkippable']) == true,
    );
  }
}

enum AdPlacement {
  interstitial,
  rewarded,
  banner,
  native,
}

extension AdPlacementValue on AdPlacement {
  String get value {
    switch (this) {
      case AdPlacement.interstitial:
        return 'interstitial';
      case AdPlacement.rewarded:
        return 'rewarded';
      case AdPlacement.banner:
        return 'banner';
      case AdPlacement.native:
        return 'native';
    }
  }
}

enum AdTrackEvent {
  impression,
  click,
  completion,
}

extension AdTrackEventValue on AdTrackEvent {
  String get value {
    switch (this) {
      case AdTrackEvent.impression:
        return 'impression';
      case AdTrackEvent.click:
        return 'click';
      case AdTrackEvent.completion:
        return 'completion';
    }
  }
}
