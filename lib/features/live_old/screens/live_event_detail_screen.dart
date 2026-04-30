import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/config/supabase_media_url.dart';
import '../../../app/theme/weafrica_colors.dart';
import '../../../app/widgets/gold_button.dart';

class LiveEventDetailScreen extends StatelessWidget {
  const LiveEventDetailScreen({
    super.key,
    required this.row,
    required this.onWatch,
  });

  final Map<String, dynamic> row;
  final Future<void> Function() onWatch;

  String _s(dynamic v) => (v ?? '').toString().trim();

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _formatNumber(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}K';
    return number.toString();
  }

  String? _resolveThumbUrl() {
    final raw = _s(row['thumbnail_url']);
    if (raw.isEmpty) return null;

    var candidate = raw;

    if (!candidate.startsWith('http://') &&
        !candidate.startsWith('https://') &&
        (candidate.startsWith('//') ||
            candidate.contains('.supabase.co/') ||
            candidate.contains('.functions.supabase.co/'))) {
      candidate = candidate.startsWith('//') ? 'https:$candidate' : 'https://$candidate';
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;

    final normalized = SupabaseMediaUrl.normalize(uri);
    return (normalized ?? uri).toString();
  }

  String _title() => _s(row['title']).isNotEmpty ? _s(row['title']) : 'Live';

  String _host() => _s(row['host_name']).isNotEmpty ? _s(row['host_name']) : 'Host';

  String _category() => _s(row['category']).isNotEmpty ? _s(row['category']) : 'Music';

  String _when() {
    final raw = row['started_at'];
    if (raw == null) return '';

    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '';

    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');

    return 'Started $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = _resolveThumbUrl();
    final viewers = _asInt(row['viewer_count']);
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: WeAfricaColors.stageBlack,
      appBar: AppBar(
        title: const Text('LIVE'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          /// 🔥 Thumbnail Card
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: WeAfricaColors.cardDark,
                image: thumb != null
                    ? DecorationImage(
                        image: NetworkImage(thumb),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: Stack(
                children: [
                  /// Gradient overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.20),
                            Colors.black.withValues(alpha: 0.80),
                          ],
                        ),
                      ),
                    ),
                  ),

                  /// LIVE badge
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: WeAfricaColors.error,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),

                  /// Viewer count
                  Positioned(
                    right: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility, size: 14, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            _formatNumber(viewers),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  /// Title + meta
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [_host(), _category(), if (_when().isNotEmpty) _when()].join(' • '),
                          style: const TextStyle(color: Colors.white70),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          /// 🔥 WATCH BUTTON
          GoldButton(
            label: 'WATCH',
            fullWidth: true,
            onPressed: () async {
              try {
                await onWatch();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to open live: $e'),
                    backgroundColor: WeAfricaColors.error,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}