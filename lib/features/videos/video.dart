import '../../app/config/supabase_env.dart';

class Video {
  final String id;
  final String title;
  final String? artistId;
  final String? creatorUid;
  final String? battleId;
  final String? thumbnailUrl;
  final String? videoUrl;
  final DateTime? createdAt;
  final String? caption;
  final String? description;
  final String? category;
  final int? viewsCount;
  final int? likesCount;
  final int? commentsCount;
  final bool? allowDownload;
  final String? downloadUrl;
  final bool isExclusive;

  const Video({
    required this.id,
    required this.title,
    this.artistId,
    this.creatorUid,
    this.battleId,
    this.thumbnailUrl,
    this.videoUrl,
    this.createdAt,
    this.caption,
    this.description,
    this.category,
    this.viewsCount,
    this.likesCount,
    this.commentsCount,
    this.allowDownload,
    this.downloadUrl,
    this.isExclusive = false,
  });

  // Getters for compatibility
  Uri? get thumbnailUri => thumbnailUrl != null ? Uri.tryParse(thumbnailUrl!) : null;
  Uri? get videoUri => videoUrl != null ? Uri.tryParse(videoUrl!) : null;
  Uri? get downloadUri => downloadUrl != null ? Uri.tryParse(downloadUrl!) : null;
  
  int get likeCount => likesCount ?? 0;
  int get commentCount => commentsCount ?? 0;

  static Video fromSupabase(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final title = (row['title'] ?? '').toString();

    String? getString(String key) {
      final val = row[key];
      return val?.toString().trim();
    }

    String? normalizeUrl(String? raw) {
      if (raw == null) return null;
      var out = raw.trim();
      if (out.isEmpty) return null;

      out = out.replaceAll('%3CSUPABASE_URL%3E', '<SUPABASE_URL>');
      final baseUrl = SupabaseEnv.supabaseUrl.trim();

      if (out.contains('<SUPABASE_URL>') && baseUrl.isNotEmpty) {
        out = out.replaceAll('<SUPABASE_URL>', baseUrl);
      }

      if (out.startsWith('http://') || out.startsWith('https://')) {
        return out;
      }

      if (out.startsWith('/')) {
        return '$baseUrl$out';
      }

      if (out.startsWith('storage/v1/object/public/') || out.startsWith('storage/v1/object/')) {
        return '$baseUrl/${out.startsWith('/') ? out.substring(1) : out}';
      }

      return out;
    }

    return Video(
      id: id,
      title: title.isEmpty ? 'Untitled' : title,
      videoUrl: normalizeUrl(getString('video_url') ?? getString('videoUrl') ?? getString('url')),
      thumbnailUrl: normalizeUrl(getString('thumbnail_url') ?? getString('thumbnailUrl') ?? getString('thumbnail') ?? getString('image_url') ?? getString('imageUrl')),
      artistId: getString('artist_id'),
      creatorUid: getString('user_id'),
      battleId: getString('battle_id'),
      createdAt: row['created_at'] != null ? DateTime.tryParse(row['created_at'].toString()) : null,
      caption: getString('caption'),
      description: getString('description'),
      category: getString('category'),
      viewsCount: row['views_count'] as int?,
      likesCount: row['likes_count'] as int?,
      commentsCount: row['comments_count'] as int?,
      allowDownload: row['allow_download'] == true,
      downloadUrl: normalizeUrl(getString('download_url')),
      isExclusive: row['is_exclusive'] == true,
    );
  }
}