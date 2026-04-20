class AdModel {
  const AdModel({
    required this.id,
    required this.title,
    this.audioUrl,
    this.videoUrl,
    this.imageUrl,
    required this.durationSeconds,
    required this.advertiser,
    this.clickUrl,
    this.isSkippable = false,
  });

  final String id;
  final String title;
  final String? audioUrl;
  final String? videoUrl;
  final String? imageUrl;
  final int durationSeconds;
  final String advertiser;
  final String? clickUrl;
  final bool isSkippable;

  static AdModel? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final id = (json['id'] ?? '').toString().trim();
    final title = (json['title'] ?? json['name'] ?? 'Sponsored').toString().trim();
    final audioUrl = (json['audio_url'] ?? json['audioUrl'] ?? '').toString().trim();
    final videoUrl = (json['video_url'] ?? json['videoUrl'] ?? '').toString().trim();

    if (id.isEmpty) return null;
    if (audioUrl.isEmpty && videoUrl.isEmpty) return null;

    final imageUrl = (json['image_url'] ?? json['imageUrl'] ?? json['artwork_url'] ?? json['artworkUrl'] ?? json['thumbnail_url'] ?? json['thumbnailUrl'])
        ?.toString()
        .trim();

    final advertiser = (json['advertiser'] ?? json['company_name'] ?? json['companyName'] ?? 'WeAfrica Music').toString().trim();

    final clickUrl = (json['click_url'] ?? json['clickUrl'] ?? json['cta_link'] ?? json['ctaLink'])?.toString().trim();

    final rawDuration = json['duration_seconds'] ?? json['durationSeconds'] ?? json['duration'] ?? 0;
    final durationSeconds = rawDuration is num
        ? rawDuration.round()
        : int.tryParse(rawDuration.toString().trim()) ?? 0;

    final rawSkippable = json['is_skippable'] ?? json['isSkippable'] ?? false;
    final isSkippable = rawSkippable is bool
        ? rawSkippable
        : rawSkippable.toString().trim().toLowerCase() == 'true';

    return AdModel(
      id: id,
      title: title.isEmpty ? 'Sponsored' : title,
      audioUrl: audioUrl.isEmpty ? null : audioUrl,
      videoUrl: videoUrl.isEmpty ? null : videoUrl,
      imageUrl: (imageUrl == null || imageUrl.isEmpty) ? null : imageUrl,
      durationSeconds: durationSeconds,
      advertiser: advertiser.isEmpty ? 'WeAfrica Music' : advertiser,
      clickUrl: (clickUrl == null || clickUrl.isEmpty) ? null : clickUrl,
      isSkippable: isSkippable,
    );
  }
}
